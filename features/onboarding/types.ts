import type {
  ProtectedSelectionSummary,
  PushUpDetectionState,
  ScreenTimeAuthorizationStatus,
  ShieldStatus
} from '@/lib/native/pushly-native';

export type AppOptionId =
  | 'instagram'
  | 'tiktok'
  | 'youtube'
  | 'x'
  | 'snapchat'
  | 'reddit'
  | 'facebook'
  | 'whatsapp'
  | 'pinterest';

export type FeelingOptionId =
  | 'unfocused'
  | 'guilty'
  | 'drained'
  | 'restless'
  | 'behind'
  | 'disconnected';

export type AttemptOptionId =
  | 'screenTime'
  | 'deleteApps'
  | 'grayscale'
  | 'detox'
  | 'browserOnly'
  | 'nothingWorked';

export type PaywallPlanId = 'yearly' | 'monthly';
export type AuthMethodId = 'apple' | 'email' | 'skip' | '';

export type OnboardingStepId =
  | 'hero'
  | 'quizIntro'
  | 'name'
  | 'distractingApps'
  | 'scrollMinutes'
  | 'feelings'
  | 'attempts'
  | 'diagnosis'
  | 'reframe'
  | 'mechanic'
  | 'protectApps'
  | 'trust'
  | 'paywall'
  | 'screenTimePermission'
  | 'cameraCalibration'
  | 'pushUpTrial'
  | 'rating'
  | 'auth'
  | 'setupPreview';

export type IconLibrary = 'fa6' | 'ion';

export type SelectionOption<T extends string = string> = {
  id: T;
  label: string;
  description?: string;
  iconLibrary: IconLibrary;
  iconName: string;
  iconStyle?: 'brand' | 'solid';
  brandColor?: string;
};

export type AppSelectionOption = SelectionOption<AppOptionId>;

export type PaywallPlanOption = {
  id: PaywallPlanId;
  title: string;
  price: string;
  subline: string;
  monthlyEquivalent: string;
  badge?: string;
};

export type OnboardingAnswers = {
  name: string;
  distractingApps: AppOptionId[];
  dailyScrollMinutes: number;
  feelings: FeelingOptionId[];
  attempts: AttemptOptionId[];
  protectedApps: AppOptionId[];
  planId: PaywallPlanId;
  screenTimeStatus: ScreenTimeAuthorizationStatus;
  screenTimeSelection: ProtectedSelectionSummary;
  shieldStatus: ShieldStatus;
  pushUpRepCount: number;
  pushUpState: PushUpDetectionState;
  pushUpInstruction: string;
  pushUpFormEvidenceScore: number;
  pushUpTestPassed: boolean;
  authMethod: AuthMethodId;
};

export type OnboardingDraft = {
  stepIndex: number;
  answers: OnboardingAnswers;
};
