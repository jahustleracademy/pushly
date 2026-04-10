export type CreditLedgerEntryType = 'earn' | 'redeem' | 'reset';

export type RedeemSource = 'app' | 'shield';

export type DailyCredits = {
  dateKey: string;
  balance: number;
  earned: number;
  spent: number;
  updatedAt: string;
};

export type CreditLedgerEntry = {
  id: string;
  occurredAt: string;
  dateKey: string;
  type: CreditLedgerEntryType;
  creditsDelta: number;
  reason: string;
  metadata?: Record<string, string | number | boolean | null>;
};

export type CreditLedger = {
  entries: CreditLedgerEntry[];
};

export type RedeemRequest = {
  id: string;
  requestedAt: string;
  source: RedeemSource;
  requestedMinutes: number;
  requiredCredits: number;
};

export type UnlockWindowStatus = 'active' | 'expired';

export type UnlockWindow = {
  id: string;
  source: RedeemSource;
  startedAt: string;
  endsAt: string;
  minutes: number;
  spentCredits: number;
  status: UnlockWindowStatus;
};

export type DailyResetPolicy = {
  dateKeyFor: (at: Date) => string;
  shouldReset: (currentDateKey: string, stateDateKey: string) => boolean;
};

export type ChallengeRewardPolicy = {
  creditsPerPushup: number;
  minutesPerCredit: number;
  creditsForPushups: (pushupCount: number) => number;
  creditsForRepDelta: (previousRepCount: number, currentRepCount: number) => number;
  creditsForMinutes: (minutes: number) => number;
};

export type CreditsSnapshot = {
  dailyCredits: DailyCredits;
  ledger: CreditLedger;
  activeUnlockWindow: UnlockWindow | null;
  lastRedeemRequest: RedeemRequest | null;
  updatedAt: string;
};

export type CreditsRuntimeState = {
  hydrated: boolean;
  dailyCredits: DailyCredits;
  ledger: CreditLedger;
  activeUnlockWindow: UnlockWindow | null;
  lastRedeemRequest: RedeemRequest | null;
  lastError: string | null;
};

export type CollectCreditsInput = {
  sourceSessionId: string;
  repCount: number;
};

export type RedeemResult = {
  request: RedeemRequest;
  unlockWindow: UnlockWindow;
};
