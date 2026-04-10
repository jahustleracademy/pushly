import { addMinutesToDate, challengeRewardPolicy, createEmptyDailyCredits, dailyResetPolicy, normalizeRequestedMinutes } from '@/features/credits/domain/policies';
import type {
  CollectCreditsInput,
  CreditLedgerEntry,
  CreditsRuntimeState,
  CreditsSnapshot,
  RedeemRequest,
  RedeemResult,
  RedeemSource,
  UnlockWindow
} from '@/features/credits/domain/models';
import { loadCreditsSnapshot, saveCreditsSnapshot } from '@/features/credits/infrastructure/storage';
import { screenTimeShieldService, type ShieldRuntimeService } from '@/features/credits/integration/screenTimeShieldService';

export class InsufficientCreditsError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InsufficientCreditsError';
  }
}

export class InvalidRedeemRequestError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InvalidRedeemRequestError';
  }
}

const MAX_LEDGER_ENTRIES = 500;
const ONE_MINUTE_MS = 60_000;
const EXPIRE_RETRY_MS = 15_000;

type Listener = () => void;
type TimerHandle = ReturnType<typeof setTimeout>;

type RuntimePersistence = {
  loadSnapshot: (now: Date) => Promise<CreditsSnapshot>;
  saveSnapshot: (snapshot: CreditsSnapshot) => Promise<void>;
};

type RuntimeClock = {
  now: () => Date;
  setTimer: (handler: () => void, delayMs: number) => TimerHandle;
  clearTimer: (handle: TimerHandle) => void;
};

type RuntimeDependencies = {
  persistence: RuntimePersistence;
  clock: RuntimeClock;
  createEntryId: () => string;
  createRequestId: () => string;
};

const defaultDependencies: RuntimeDependencies = {
  persistence: {
    loadSnapshot: loadCreditsSnapshot,
    saveSnapshot: saveCreditsSnapshot
  },
  clock: {
    now: () => new Date(),
    setTimer: (handler, delayMs) => setTimeout(handler, delayMs),
    clearTimer: (handle) => clearTimeout(handle)
  },
  createEntryId: () => `ledger_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
  createRequestId: () => `redeem_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`
};

function toISO(at: Date) {
  return at.toISOString();
}

function createInitialState(now: Date): CreditsRuntimeState {
  const dateKey = dailyResetPolicy.dateKeyFor(now);

  return {
    hydrated: false,
    dailyCredits: createEmptyDailyCredits(dateKey, toISO(now)),
    ledger: { entries: [] },
    activeUnlockWindow: null,
    lastRedeemRequest: null,
    lastError: null
  };
}

export class CreditsRuntimeStore {
  private state: CreditsRuntimeState;
  private listeners = new Set<Listener>();
  private sessionRepCursor = new Map<string, number>();
  private unlockExpiryTimer: TimerHandle | null = null;
  private bootstrapPromise: Promise<void> | null = null;
  private persistQueue: Promise<void> = Promise.resolve();

  constructor(
    private readonly shieldService: ShieldRuntimeService,
    private readonly deps: RuntimeDependencies = defaultDependencies
  ) {
    this.state = createInitialState(this.deps.clock.now());
  }

  subscribe = (listener: Listener) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  getState = () => this.state;

  bootstrap = async () => {
    if (this.bootstrapPromise) {
      return this.bootstrapPromise;
    }

    this.bootstrapPromise = this.bootstrapInternal();
    try {
      await this.bootstrapPromise;
    } finally {
      this.bootstrapPromise = null;
    }
  };

  collectCreditsFromPushupProgress = async (input: CollectCreditsInput) => {
    await this.ensureBootstrapped();
    this.applyDailyResetIfNeeded(this.deps.clock.now());

    const previousRepCount = this.sessionRepCursor.get(input.sourceSessionId) ?? 0;
    if (input.repCount <= previousRepCount) {
      return 0;
    }

    this.sessionRepCursor.set(input.sourceSessionId, input.repCount);
    const awardedCredits = challengeRewardPolicy.creditsForRepDelta(previousRepCount, input.repCount);
    if (awardedCredits <= 0) {
      return 0;
    }

    const at = this.deps.clock.now();
    const atISO = toISO(at);
    const entry = this.buildLedgerEntry({
      atISO,
      type: 'earn',
      creditsDelta: awardedCredits,
      reason: 'pushup_progress',
      metadata: {
        sourceSessionId: input.sourceSessionId,
        previousRepCount,
        currentRepCount: input.repCount,
        creditsPerPushup: challengeRewardPolicy.creditsPerPushup
      }
    });

    this.setState((previous) => ({
      ...previous,
      dailyCredits: {
        ...previous.dailyCredits,
        balance: previous.dailyCredits.balance + awardedCredits,
        earned: previous.dailyCredits.earned + awardedCredits,
        updatedAt: atISO
      },
      ledger: {
        entries: [...previous.ledger.entries, entry].slice(-MAX_LEDGER_ENTRIES)
      }
    }));

    await this.persistCurrentState();
    return awardedCredits;
  };

  redeemMinutes = async (minutes: number, source: RedeemSource = 'app'): Promise<RedeemResult> => {
    await this.ensureBootstrapped();
    this.applyDailyResetIfNeeded(this.deps.clock.now());

    const requestedMinutes = normalizeRequestedMinutes(minutes);
    if (requestedMinutes <= 0) {
      throw new InvalidRedeemRequestError('Bitte gib mindestens 1 Minute zum Einloesen an.');
    }

    const requiredCredits = challengeRewardPolicy.creditsForMinutes(requestedMinutes);
    if (requiredCredits <= 0) {
      throw new InvalidRedeemRequestError('Einloeseanfrage ist ungueltig.');
    }

    if (this.state.dailyCredits.balance < requiredCredits) {
      throw new InsufficientCreditsError('Nicht genug Credits vorhanden.');
    }

    const now = this.deps.clock.now();
    const request: RedeemRequest = {
      id: this.deps.createRequestId(),
      requestedAt: toISO(now),
      source,
      requestedMinutes,
      requiredCredits
    };

    const previousWindow = this.state.activeUnlockWindow;
    const previousWindowStillActive = previousWindow ? new Date(previousWindow.endsAt).getTime() > now.getTime() : false;

    const baseStart = previousWindowStillActive && previousWindow ? new Date(previousWindow.startedAt) : now;
    const baseEnd = previousWindowStillActive && previousWindow ? new Date(previousWindow.endsAt) : now;
    const nextEnd = addMinutesToDate(baseEnd, requestedMinutes);
    const totalMinutes = Math.max(1, Math.ceil((nextEnd.getTime() - baseStart.getTime()) / ONE_MINUTE_MS));

    const unlockWindow: UnlockWindow = {
      id: previousWindowStillActive && previousWindow ? previousWindow.id : `unlock_${now.getTime()}`,
      source,
      startedAt: toISO(baseStart),
      endsAt: toISO(nextEnd),
      minutes: totalMinutes,
      spentCredits: (previousWindowStillActive && previousWindow ? previousWindow.spentCredits : 0) + requiredCredits,
      status: 'active'
    };

    const previousState = this.state;
    const nextState = this.makeRedeemNextState({
      previous: previousState,
      atISO: request.requestedAt,
      requiredCredits,
      unlockWindow,
      source,
      requestedMinutes,
      request
    });

    let unlockStarted = false;
    if (!previousWindowStillActive) {
      await this.shieldService.beginTimedUnlock();
      unlockStarted = true;
    }

    this.setState(() => nextState);

    try {
      await this.persistCurrentState();
    } catch (error) {
      this.setState(() => previousState);
      if (unlockStarted) {
        await this.shieldService.endTimedUnlock().catch(() => {
          // Rollback best effort.
        });
      }
      this.setError(error);
      throw error;
    }

    this.scheduleUnlockExpiry(unlockWindow);

    return { request, unlockWindow };
  };

  reconcileRuntime = async () => {
    await this.ensureBootstrapped();
    this.applyDailyResetIfNeeded(this.deps.clock.now());
    await this.reconcileUnlockWindow();
  };

  private makeRedeemNextState(input: {
    previous: CreditsRuntimeState;
    atISO: string;
    requiredCredits: number;
    unlockWindow: UnlockWindow;
    source: RedeemSource;
    requestedMinutes: number;
    request: RedeemRequest;
  }): CreditsRuntimeState {
    const entry = this.buildLedgerEntry({
      atISO: input.atISO,
      type: 'redeem',
      creditsDelta: -input.requiredCredits,
      reason: 'redeem_minutes',
      metadata: {
        source: input.source,
        requestedMinutes: input.requestedMinutes,
        requiredCredits: input.requiredCredits,
        unlockEndsAt: input.unlockWindow.endsAt
      }
    });

    return {
      ...input.previous,
      dailyCredits: {
        ...input.previous.dailyCredits,
        balance: input.previous.dailyCredits.balance - input.requiredCredits,
        spent: input.previous.dailyCredits.spent + input.requiredCredits,
        updatedAt: input.atISO
      },
      ledger: {
        entries: [...input.previous.ledger.entries, entry].slice(-MAX_LEDGER_ENTRIES)
      },
      activeUnlockWindow: input.unlockWindow,
      lastRedeemRequest: input.request,
      lastError: null
    };
  }

  private async bootstrapInternal() {
    const snapshot = await this.deps.persistence.loadSnapshot(this.deps.clock.now());
    this.setState((previous) => ({
      ...previous,
      hydrated: true,
      dailyCredits: snapshot.dailyCredits,
      ledger: snapshot.ledger,
      activeUnlockWindow: snapshot.activeUnlockWindow,
      lastRedeemRequest: snapshot.lastRedeemRequest,
      lastError: null
    }));

    this.applyDailyResetIfNeeded(this.deps.clock.now());
    await this.reconcileUnlockWindow();
  }

  private async ensureBootstrapped() {
    if (!this.state.hydrated) {
      await this.bootstrap();
    }
  }

  private applyDailyResetIfNeeded(now: Date) {
    const currentDateKey = dailyResetPolicy.dateKeyFor(now);
    const stateDateKey = this.state.dailyCredits.dateKey;

    if (!dailyResetPolicy.shouldReset(currentDateKey, stateDateKey)) {
      return;
    }

    const atISO = toISO(now);
    const resetEntry = this.buildLedgerEntry({
      atISO,
      type: 'reset',
      creditsDelta: 0,
      reason: 'daily_reset',
      metadata: {
        previousDateKey: stateDateKey,
        newDateKey: currentDateKey,
        previousBalance: this.state.dailyCredits.balance
      }
    });

    this.sessionRepCursor.clear();
    this.clearUnlockTimer();

    this.setState((previous) => ({
      ...previous,
      dailyCredits: createEmptyDailyCredits(currentDateKey, atISO),
      ledger: {
        entries: [...previous.ledger.entries, resetEntry].slice(-MAX_LEDGER_ENTRIES)
      },
      activeUnlockWindow: null,
      lastRedeemRequest: null
    }));

    void this.persistCurrentState();
    void this.shieldService.ensureShieldingActive().catch((error) => {
      this.setError(error);
    });
  }

  private async reconcileUnlockWindow() {
    const window = this.state.activeUnlockWindow;
    if (!window) {
      this.clearUnlockTimer();
      return;
    }

    const now = this.deps.clock.now();
    const endsAt = new Date(window.endsAt);

    if (Number.isNaN(endsAt.getTime()) || endsAt.getTime() <= now.getTime()) {
      await this.expireUnlockWindow(window.id);
      return;
    }

    try {
      await this.shieldService.beginTimedUnlock();
    } catch (error) {
      this.setError(error);
    }

    this.scheduleUnlockExpiry(window);
  }

  private async expireUnlockWindow(expectedId: string) {
    const current = this.state.activeUnlockWindow;
    if (!current || current.id !== expectedId) {
      return;
    }

    this.clearUnlockTimer();

    try {
      await this.shieldService.endTimedUnlock();
    } catch (error) {
      this.setError(error);
      this.unlockExpiryTimer = this.deps.clock.setTimer(() => {
        void this.expireUnlockWindow(expectedId);
      }, EXPIRE_RETRY_MS);
      return;
    }

    this.setState((previous) => {
      if (!previous.activeUnlockWindow || previous.activeUnlockWindow.id !== expectedId) {
        return previous;
      }

      return {
        ...previous,
        activeUnlockWindow: null
      };
    });

    await this.persistCurrentState();
  }

  private scheduleUnlockExpiry(window: UnlockWindow) {
    this.clearUnlockTimer();

    const end = new Date(window.endsAt).getTime();
    const delay = Math.max(0, end - this.deps.clock.now().getTime());

    this.unlockExpiryTimer = this.deps.clock.setTimer(() => {
      void this.expireUnlockWindow(window.id);
    }, delay);
  }

  private clearUnlockTimer() {
    if (!this.unlockExpiryTimer) {
      return;
    }

    this.deps.clock.clearTimer(this.unlockExpiryTimer);
    this.unlockExpiryTimer = null;
  }

  private buildLedgerEntry(input: {
    atISO: string;
    type: CreditLedgerEntry['type'];
    creditsDelta: number;
    reason: string;
    metadata?: CreditLedgerEntry['metadata'];
  }): CreditLedgerEntry {
    return {
      id: this.deps.createEntryId(),
      occurredAt: input.atISO,
      dateKey: dailyResetPolicy.dateKeyFor(new Date(input.atISO)),
      type: input.type,
      creditsDelta: input.creditsDelta,
      reason: input.reason,
      metadata: input.metadata
    };
  }

  private makeSnapshot(): CreditsSnapshot {
    return {
      dailyCredits: this.state.dailyCredits,
      ledger: this.state.ledger,
      activeUnlockWindow: this.state.activeUnlockWindow,
      lastRedeemRequest: this.state.lastRedeemRequest,
      updatedAt: toISO(this.deps.clock.now())
    };
  }

  private async persistCurrentState() {
    const snapshot = this.makeSnapshot();
    const operation = this.persistQueue.then(() => this.deps.persistence.saveSnapshot(snapshot));
    this.persistQueue = operation.then(() => undefined).catch(() => undefined);
    await operation;
  }

  private setState(updater: (previous: CreditsRuntimeState) => CreditsRuntimeState) {
    this.state = updater(this.state);
    this.emit();
  }

  private setError(error: unknown) {
    const message = error instanceof Error ? error.message : 'Unbekannter Runtime-Fehler';
    this.setState((previous) => ({
      ...previous,
      lastError: message
    }));
  }

  private emit() {
    this.listeners.forEach((listener) => listener());
  }
}

export const creditsRuntimeStore = new CreditsRuntimeStore(screenTimeShieldService);
