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
export type GoalId = 'sleep' | 'focus' | 'discipline' | 'energy' | '';
export type AgeRangeId = 'under18' | '18to24' | '25to34' | '35plus' | '';
export type ReminderSlotId = 'morning' | 'afternoon' | 'evening' | '';
export type ExerciseTypeId = 'pushups' | 'squats' | 'mixed' | '';

export type OnboardingStepId =
  | 'hero'
  | 'quizIntro'
  | 'name'
  | 'goals'
  | 'distractingApps'
  | 'scrollMinutes'
  | 'targetMinutes'
  | 'feelings'
  | 'ageRange'
  | 'attempts'
  | 'diagnosis'
  | 'reframe'
  | 'reframeGain'
  | 'mechanic'
  | 'reminderTime'
  | 'exerciseChoice'
  | 'setupBridge'
  | 'journey'
  | 'protectApps'
  | 'trust'
  | 'trustRating'
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
  goalId: GoalId;
  distractingApps: AppOptionId[];
  dailyScrollMinutes: number;
  targetScrollMinutes: number;
  feelings: FeelingOptionId[];
  ageRange: AgeRangeId;
  attempts: AttemptOptionId[];
  reminderSlot: ReminderSlotId;
  exerciseType: ExerciseTypeId;
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
