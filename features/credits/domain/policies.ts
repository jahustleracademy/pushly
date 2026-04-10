import type { ChallengeRewardPolicy, DailyResetPolicy, DailyCredits } from './models';

export const CREDITS_PER_PUSHUP = 2;
export const MINUTES_PER_CREDIT = 1;

export const dailyResetPolicy: DailyResetPolicy = {
  dateKeyFor: (at) => {
    const year = at.getFullYear();
    const month = `${at.getMonth() + 1}`.padStart(2, '0');
    const day = `${at.getDate()}`.padStart(2, '0');
    return `${year}-${month}-${day}`;
  },
  shouldReset: (currentDateKey, stateDateKey) => currentDateKey !== stateDateKey
};

export const challengeRewardPolicy: ChallengeRewardPolicy = {
  creditsPerPushup: CREDITS_PER_PUSHUP,
  minutesPerCredit: MINUTES_PER_CREDIT,
  creditsForPushups: (pushupCount) => Math.max(0, Math.floor(pushupCount)) * CREDITS_PER_PUSHUP,
  creditsForRepDelta: (previousRepCount, currentRepCount) => {
    const delta = Math.max(0, Math.floor(currentRepCount) - Math.floor(previousRepCount));
    return delta * CREDITS_PER_PUSHUP;
  },
  creditsForMinutes: (minutes) => Math.max(0, Math.ceil(minutes / MINUTES_PER_CREDIT))
};

export function createEmptyDailyCredits(dateKey: string, atISO: string): DailyCredits {
  return {
    dateKey,
    balance: 0,
    earned: 0,
    spent: 0,
    updatedAt: atISO
  };
}

export function normalizeRequestedMinutes(minutes: number): number {
  if (!Number.isFinite(minutes)) {
    return 0;
  }

  return Math.max(0, Math.floor(minutes));
}

export function addMinutesToDate(from: Date, minutes: number) {
  return new Date(from.getTime() + minutes * 60_000);
}
