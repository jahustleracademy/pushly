import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { CreditsSnapshot } from '@/features/credits/domain/models';
import { CreditsRuntimeStore, InsufficientCreditsError } from '@/features/credits/application/creditsRuntime';
import type { ShieldRuntimeService } from '@/features/credits/integration/screenTimeShieldService';

function makeSnapshot(overrides?: Partial<CreditsSnapshot>): CreditsSnapshot {
  return {
    dailyCredits: {
      dateKey: '2026-04-10',
      balance: 0,
      earned: 0,
      spent: 0,
      updatedAt: '2026-04-10T10:00:00.000Z'
    },
    ledger: { entries: [] },
    activeUnlockWindow: null,
    lastRedeemRequest: null,
    updatedAt: '2026-04-10T10:00:00.000Z',
    ...overrides
  };
}

function makeHarness(initialSnapshot: CreditsSnapshot) {
  let stored = initialSnapshot;
  const saves: CreditsSnapshot[] = [];

  const persistence = {
    loadSnapshot: vi.fn(async () => stored),
    saveSnapshot: vi.fn(async (snapshot: CreditsSnapshot) => {
      stored = snapshot;
      saves.push(snapshot);
    })
  };

  const shield: ShieldRuntimeService = {
    beginTimedUnlock: vi.fn(async () => undefined),
    endTimedUnlock: vi.fn(async () => undefined),
    ensureShieldingActive: vi.fn(async () => undefined)
  };

  const runtime = new CreditsRuntimeStore(shield, {
    persistence,
    clock: {
      now: () => new Date(),
      setTimer: (handler, delayMs) => setTimeout(handler, delayMs),
      clearTimer: (handle) => clearTimeout(handle)
    },
    createEntryId: () => `entry_${Math.random().toString(36).slice(2, 8)}`,
    createRequestId: () => `request_${Math.random().toString(36).slice(2, 8)}`
  });

  return {
    runtime,
    persistence,
    shield,
    getStored: () => stored,
    saves
  };
}

describe('credits runtime integration', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-04-10T10:00:00.000Z'));
  });

  it('collects credits from push-up progress once per rep delta', async () => {
    const harness = makeHarness(makeSnapshot());
    await harness.runtime.bootstrap();

    await harness.runtime.collectCreditsFromPushupProgress({ sourceSessionId: 's1', repCount: 3 });
    await harness.runtime.collectCreditsFromPushupProgress({ sourceSessionId: 's1', repCount: 3 });
    await harness.runtime.collectCreditsFromPushupProgress({ sourceSessionId: 's1', repCount: 5 });

    const state = harness.runtime.getState();
    expect(state.dailyCredits.earned).toBe(10);
    expect(state.dailyCredits.balance).toBe(10);
  });

  it('rejects redeem when credits are insufficient', async () => {
    const harness = makeHarness(makeSnapshot());
    await harness.runtime.bootstrap();

    await expect(harness.runtime.redeemMinutes(5, 'app')).rejects.toBeInstanceOf(InsufficientCreditsError);
  });

  it('redeems credits and activates unlock window', async () => {
    const harness = makeHarness(makeSnapshot({
      dailyCredits: {
        dateKey: '2026-04-10',
        balance: 20,
        earned: 20,
        spent: 0,
        updatedAt: '2026-04-10T10:00:00.000Z'
      }
    }));
    await harness.runtime.bootstrap();

    await harness.runtime.redeemMinutes(15, 'app');

    const state = harness.runtime.getState();
    expect(state.dailyCredits.balance).toBe(5);
    expect(state.activeUnlockWindow).not.toBeNull();
    expect(harness.shield.beginTimedUnlock).toHaveBeenCalledTimes(1);
  });

  it('ends unlock and re-shields after window expiry', async () => {
    const harness = makeHarness(makeSnapshot({
      dailyCredits: {
        dateKey: '2026-04-10',
        balance: 10,
        earned: 10,
        spent: 0,
        updatedAt: '2026-04-10T10:00:00.000Z'
      }
    }));
    await harness.runtime.bootstrap();
    await harness.runtime.redeemMinutes(1, 'app');

    await vi.advanceTimersByTimeAsync(60_100);

    const state = harness.runtime.getState();
    expect(state.activeUnlockWindow).toBeNull();
    expect(harness.shield.endTimedUnlock).toHaveBeenCalledTimes(1);
  });

  it('applies daily reset on startup when date changed', async () => {
    const harness = makeHarness(makeSnapshot({
      dailyCredits: {
        dateKey: '2026-04-09',
        balance: 50,
        earned: 60,
        spent: 10,
        updatedAt: '2026-04-09T20:00:00.000Z'
      },
      activeUnlockWindow: {
        id: 'u1',
        source: 'app',
        startedAt: '2026-04-09T19:00:00.000Z',
        endsAt: '2026-04-09T20:00:00.000Z',
        minutes: 60,
        spentCredits: 60,
        status: 'active'
      }
    }));

    await harness.runtime.bootstrap();
    const state = harness.runtime.getState();

    expect(state.dailyCredits.dateKey).toBe('2026-04-10');
    expect(state.dailyCredits.balance).toBe(0);
    expect(state.dailyCredits.earned).toBe(0);
    expect(state.dailyCredits.spent).toBe(0);
    expect(state.activeUnlockWindow).toBeNull();
    expect(harness.shield.ensureShieldingActive).toHaveBeenCalledTimes(1);
  });

  it('reconciles expired unlocks at startup', async () => {
    const harness = makeHarness(makeSnapshot({
      activeUnlockWindow: {
        id: 'u1',
        source: 'shield',
        startedAt: '2026-04-10T08:00:00.000Z',
        endsAt: '2026-04-10T09:00:00.000Z',
        minutes: 60,
        spentCredits: 60,
        status: 'active'
      }
    }));

    await harness.runtime.bootstrap();
    const state = harness.runtime.getState();

    expect(state.activeUnlockWindow).toBeNull();
    expect(harness.shield.endTimedUnlock).toHaveBeenCalledTimes(1);
    expect(harness.saves.length).toBeGreaterThan(0);
    expect(harness.getStored().activeUnlockWindow).toBeNull();
  });
});
