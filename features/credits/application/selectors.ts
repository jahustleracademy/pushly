import type { CreditLedgerEntry, CreditsRuntimeState } from '@/features/credits/domain/models';
import { challengeRewardPolicy } from '@/features/credits/domain/policies';

export type TodayActivityItem = {
  id: string;
  at: string;
  type: CreditLedgerEntry['type'];
  label: string;
  creditsDelta: number;
};

export type DailyHistoryItem = {
  dateKey: string;
  earnedCredits: number;
  redeemedCredits: number;
  pushups: number;
  redeemedMinutes: number;
};

export function getTodayPushups(state: CreditsRuntimeState) {
  return Math.floor(state.dailyCredits.earned / challengeRewardPolicy.creditsPerPushup);
}

export function getTodayRedeemedMinutes(state: CreditsRuntimeState) {
  return state.dailyCredits.spent * challengeRewardPolicy.minutesPerCredit;
}

export function getAvailableMinutes(state: CreditsRuntimeState) {
  return state.dailyCredits.balance * challengeRewardPolicy.minutesPerCredit;
}

export function getRemainingUnlockMs(state: CreditsRuntimeState, now = Date.now()) {
  if (!state.activeUnlockWindow) {
    return 0;
  }

  const end = new Date(state.activeUnlockWindow.endsAt).getTime();
  if (!Number.isFinite(end)) {
    return 0;
  }

  return Math.max(0, end - now);
}

export function getTodayActivity(state: CreditsRuntimeState): TodayActivityItem[] {
  const dateKey = state.dailyCredits.dateKey;
  return state.ledger.entries
    .filter((entry) => entry.dateKey === dateKey)
    .slice()
    .reverse()
    .map((entry) => ({
      id: entry.id,
      at: entry.occurredAt,
      type: entry.type,
      label: buildActivityLabel(entry),
      creditsDelta: entry.creditsDelta
    }));
}

export function getDailyHistory(state: CreditsRuntimeState, limit = 7): DailyHistoryItem[] {
  const byDay = new Map<string, DailyHistoryItem>();

  for (const entry of state.ledger.entries) {
    const current = byDay.get(entry.dateKey) ?? {
      dateKey: entry.dateKey,
      earnedCredits: 0,
      redeemedCredits: 0,
      pushups: 0,
      redeemedMinutes: 0
    };

    if (entry.type === 'earn') {
      current.earnedCredits += Math.max(0, entry.creditsDelta);
    }

    if (entry.type === 'redeem') {
      const spent = Math.max(0, -entry.creditsDelta);
      current.redeemedCredits += spent;
      current.redeemedMinutes += spent * challengeRewardPolicy.minutesPerCredit;
    }

    current.pushups = Math.floor(current.earnedCredits / challengeRewardPolicy.creditsPerPushup);
    byDay.set(entry.dateKey, current);
  }

  return Array.from(byDay.values())
    .sort((a, b) => (a.dateKey > b.dateKey ? -1 : 1))
    .slice(0, Math.max(1, limit));
}

export function formatRemainingUnlock(ms: number) {
  if (ms <= 0) {
    return 'endet gleich';
  }

  const minutes = Math.floor(ms / 60_000);
  const seconds = Math.floor((ms % 60_000) / 1000);
  return `${minutes}m ${`${seconds}`.padStart(2, '0')}s`;
}

function buildActivityLabel(entry: CreditLedgerEntry) {
  if (entry.type === 'earn') {
    const reps = typeof entry.metadata?.currentRepCount === 'number' && typeof entry.metadata?.previousRepCount === 'number'
      ? Math.max(0, entry.metadata.currentRepCount - entry.metadata.previousRepCount)
      : Math.floor(Math.max(0, entry.creditsDelta) / challengeRewardPolicy.creditsPerPushup);
    return `Push-ups +${reps}`;
  }

  if (entry.type === 'redeem') {
    const minutes = typeof entry.metadata?.requestedMinutes === 'number'
      ? entry.metadata.requestedMinutes
      : Math.max(0, -entry.creditsDelta);
    return `Free Time ${minutes}m`;
  }

  return 'Tagesreset';
}
