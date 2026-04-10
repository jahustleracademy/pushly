import AsyncStorage from '@react-native-async-storage/async-storage';
import { PushlyNative } from '@/lib/native/pushly-native';
import type {
  CreditsSnapshot,
  DailyCredits,
  UnlockWindow,
  CreditLedgerEntry,
  RedeemRequest
} from '@/features/credits/domain/models';
import { createEmptyDailyCredits, dailyResetPolicy } from '@/features/credits/domain/policies';

const CREDITS_SNAPSHOT_KEY = '@pushly_credits_snapshot_v1';
const MAX_LEDGER_ENTRIES = 500;

export async function loadCreditsSnapshot(now = new Date()): Promise<CreditsSnapshot> {
  const nowISO = now.toISOString();
  const todayKey = dailyResetPolicy.dateKeyFor(now);

  const [rawAsyncSnapshot, rawSharedSnapshot] = await Promise.all([
    AsyncStorage.getItem(CREDITS_SNAPSHOT_KEY),
    PushlyNative.getSharedCreditsSnapshot().catch(() => null)
  ]);

  const asyncSnapshot = parseSnapshotCandidate(rawAsyncSnapshot, todayKey, nowISO);
  const sharedSnapshot = parseSnapshotCandidate(rawSharedSnapshot, todayKey, nowISO);

  const resolved = pickMostRecentSnapshot(asyncSnapshot, sharedSnapshot) ?? createEmptySnapshot(todayKey, nowISO);

  await Promise.allSettled([
    writeAsyncSnapshotIfNewer(resolved),
    writeSharedSnapshotIfNewer(resolved)
  ]);

  return resolved;
}

export async function saveCreditsSnapshot(snapshot: CreditsSnapshot) {
  const safe = sanitizeSnapshot(snapshot);

  await Promise.all([
    writeAsyncSnapshotIfNewer(safe),
    writeSharedSnapshotIfNewer(safe)
  ]);
}

export async function clearCreditsSnapshot() {
  const now = new Date();
  const empty = createEmptySnapshot(dailyResetPolicy.dateKeyFor(now), now.toISOString());

  await Promise.all([
    AsyncStorage.removeItem(CREDITS_SNAPSHOT_KEY),
    PushlyNative.setSharedCreditsSnapshot(JSON.stringify(empty))
  ]);
}

async function writeAsyncSnapshotIfNewer(next: CreditsSnapshot) {
  const currentRaw = await AsyncStorage.getItem(CREDITS_SNAPSHOT_KEY);
  const current = parseSnapshotCandidate(currentRaw, next.dailyCredits.dateKey, next.updatedAt);

  if (!shouldOverwrite(current, next)) {
    return;
  }

  await AsyncStorage.setItem(CREDITS_SNAPSHOT_KEY, JSON.stringify(next));
}

async function writeSharedSnapshotIfNewer(next: CreditsSnapshot) {
  const currentRaw = await PushlyNative.getSharedCreditsSnapshot().catch(() => null);
  const current = parseSnapshotCandidate(currentRaw, next.dailyCredits.dateKey, next.updatedAt);

  if (!shouldOverwrite(current, next)) {
    return;
  }

  await PushlyNative.setSharedCreditsSnapshot(JSON.stringify(next));
}

function shouldOverwrite(current: CreditsSnapshot | null, next: CreditsSnapshot) {
  if (!current) {
    return true;
  }

  const currentTime = safeTimestamp(current.updatedAt);
  const nextTime = safeTimestamp(next.updatedAt);

  if (nextTime > currentTime) {
    return true;
  }

  if (nextTime < currentTime) {
    return false;
  }

  return next.ledger.entries.length >= current.ledger.entries.length;
}

function safeTimestamp(value: string) {
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) {
    return 0;
  }

  return timestamp;
}

function createEmptySnapshot(todayKey: string, nowISO: string): CreditsSnapshot {
  return {
    dailyCredits: createEmptyDailyCredits(todayKey, nowISO),
    ledger: { entries: [] },
    activeUnlockWindow: null,
    lastRedeemRequest: null,
    updatedAt: nowISO
  };
}

function sanitizeSnapshot(snapshot: CreditsSnapshot): CreditsSnapshot {
  return {
    ...snapshot,
    dailyCredits: sanitizeDailyCredits(snapshot.dailyCredits, snapshot.dailyCredits.dateKey, snapshot.updatedAt),
    ledger: {
      entries: sanitizeLedgerEntries(snapshot.ledger.entries).slice(-MAX_LEDGER_ENTRIES)
    },
    activeUnlockWindow: sanitizeUnlockWindow(snapshot.activeUnlockWindow),
    lastRedeemRequest: sanitizeRedeemRequest(snapshot.lastRedeemRequest),
    updatedAt: typeof snapshot.updatedAt === 'string' ? snapshot.updatedAt : new Date().toISOString()
  };
}

function parseSnapshotCandidate(raw: string | null, fallbackDateKey: string, nowISO: string): CreditsSnapshot | null {
  if (!raw) {
    return null;
  }

  try {
    const parsed = JSON.parse(raw) as Partial<CreditsSnapshot>;
    const dailyCredits = sanitizeDailyCredits(parsed.dailyCredits, fallbackDateKey, nowISO);
    const ledgerEntries = sanitizeLedgerEntries(parsed.ledger?.entries ?? []);
    const activeUnlockWindow = sanitizeUnlockWindow(parsed.activeUnlockWindow ?? null);
    const lastRedeemRequest = sanitizeRedeemRequest(parsed.lastRedeemRequest ?? null);

    return {
      dailyCredits,
      ledger: {
        entries: ledgerEntries.slice(-MAX_LEDGER_ENTRIES)
      },
      activeUnlockWindow,
      lastRedeemRequest,
      updatedAt: typeof parsed.updatedAt === 'string' ? parsed.updatedAt : nowISO
    };
  } catch {
    return null;
  }
}

function pickMostRecentSnapshot(a: CreditsSnapshot | null, b: CreditsSnapshot | null): CreditsSnapshot | null {
  if (!a) {
    return b;
  }

  if (!b) {
    return a;
  }

  if (shouldOverwrite(a, b)) {
    return b;
  }

  return a;
}

function sanitizeDailyCredits(candidate: CreditsSnapshot['dailyCredits'] | undefined, fallbackDateKey: string, nowISO: string): DailyCredits {
  if (!candidate || typeof candidate !== 'object') {
    return createEmptyDailyCredits(fallbackDateKey, nowISO);
  }

  const balance = toNonNegativeInt((candidate as DailyCredits).balance);
  const earned = toNonNegativeInt((candidate as DailyCredits).earned);
  const spent = toNonNegativeInt((candidate as DailyCredits).spent);
  const dateKey = typeof (candidate as DailyCredits).dateKey === 'string' ? (candidate as DailyCredits).dateKey : fallbackDateKey;

  return {
    dateKey,
    balance,
    earned,
    spent,
    updatedAt: typeof (candidate as DailyCredits).updatedAt === 'string' ? (candidate as DailyCredits).updatedAt : nowISO
  };
}

function sanitizeLedgerEntries(entries: unknown[]): CreditLedgerEntry[] {
  if (!Array.isArray(entries)) {
    return [];
  }

  return entries
    .map((entry): CreditLedgerEntry | null => {
      if (!entry || typeof entry !== 'object') {
        return null;
      }

      const candidate = entry as CreditLedgerEntry;
      if (typeof candidate.id !== 'string' || typeof candidate.occurredAt !== 'string' || typeof candidate.dateKey !== 'string' || typeof candidate.reason !== 'string') {
        return null;
      }

      if (candidate.type !== 'earn' && candidate.type !== 'redeem' && candidate.type !== 'reset') {
        return null;
      }

      if (!Number.isFinite(candidate.creditsDelta)) {
        return null;
      }

      return {
        ...candidate,
        creditsDelta: Math.trunc(candidate.creditsDelta)
      };
    })
    .filter((entry): entry is CreditLedgerEntry => entry !== null);
}

function sanitizeUnlockWindow(window: unknown): UnlockWindow | null {
  if (!window || typeof window !== 'object') {
    return null;
  }

  const candidate = window as UnlockWindow;
  if (
    typeof candidate.id !== 'string' ||
    typeof candidate.startedAt !== 'string' ||
    typeof candidate.endsAt !== 'string' ||
    typeof candidate.minutes !== 'number' ||
    typeof candidate.spentCredits !== 'number'
  ) {
    return null;
  }

  if (candidate.status !== 'active' && candidate.status !== 'expired') {
    return null;
  }

  if (candidate.source !== 'app' && candidate.source !== 'shield') {
    return null;
  }

  return {
    ...candidate,
    minutes: toNonNegativeInt(candidate.minutes),
    spentCredits: toNonNegativeInt(candidate.spentCredits)
  };
}

function sanitizeRedeemRequest(candidate: unknown): RedeemRequest | null {
  if (!candidate || typeof candidate !== 'object') {
    return null;
  }

  const request = candidate as RedeemRequest;
  if (
    typeof request.id !== 'string' ||
    typeof request.requestedAt !== 'string' ||
    (request.source !== 'app' && request.source !== 'shield') ||
    typeof request.requestedMinutes !== 'number' ||
    typeof request.requiredCredits !== 'number'
  ) {
    return null;
  }

  return {
    ...request,
    requestedMinutes: toNonNegativeInt(request.requestedMinutes),
    requiredCredits: toNonNegativeInt(request.requiredCredits)
  };
}

function toNonNegativeInt(value: unknown): number {
  if (!Number.isFinite(value)) {
    return 0;
  }

  return Math.max(0, Math.trunc(value as number));
}

export const __storageTestUtils = {
  parseSnapshotCandidate,
  pickMostRecentSnapshot,
  shouldOverwrite,
  sanitizeSnapshot
};
