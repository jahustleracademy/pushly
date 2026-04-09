import type {
  AppOptionId,
  AppSelectionOption,
  AuthMethodId,
  AttemptOptionId,
  OnboardingAnswers,
  OnboardingStepId,
  PaywallPlanOption,
  SelectionOption
} from './types';

export const ONBOARDING_STEP_ORDER: OnboardingStepId[] = [
  'hero',
  'quizIntro',
  'name',
  'distractingApps',
  'scrollMinutes',
  'feelings',
  'attempts',
  'diagnosis',
  'reframe',
  'mechanic',
  'protectApps',
  'trust',
  'screenTimePermission',
  'cameraCalibration',
  'pushUpTrial',
  'rating',
  'auth',
  'paywall',
  'setupPreview'
];

export const DEFAULT_ONBOARDING_ANSWERS: OnboardingAnswers = {
  name: '',
  distractingApps: [],
  dailyScrollMinutes: 96,
  feelings: [],
  attempts: [],
  protectedApps: [],
  planId: 'yearly',
  screenTimeStatus: 'not_determined',
  screenTimeSelection: {
    appCount: 0,
    categoryCount: 0,
    webDomainCount: 0,
    hasSelection: false,
    lastUpdatedAt: null
  },
  shieldStatus: 'inactive',
  pushUpRepCount: 0,
  pushUpState: 'idle',
  pushUpInstruction: 'Kalibriere dich im Frame.',
  pushUpFormEvidenceScore: 0,
  pushUpTestPassed: false,
  authMethod: ''
};

export const DISTRACTING_APP_OPTIONS: AppSelectionOption[] = [
  { id: 'tiktok', label: 'TikTok', iconLibrary: 'fa6', iconName: 'tiktok', iconStyle: 'brand', brandColor: '#FFFFFF' },
  { id: 'instagram', label: 'Instagram', iconLibrary: 'fa6', iconName: 'instagram', iconStyle: 'brand', brandColor: '#FFFFFF' },
  { id: 'youtube', label: 'YouTube', iconLibrary: 'fa6', iconName: 'youtube', iconStyle: 'brand', brandColor: '#FFFFFF' },
  { id: 'x', label: 'X', iconLibrary: 'fa6', iconName: 'x-twitter', iconStyle: 'brand', brandColor: '#FFFFFF' },
  { id: 'snapchat', label: 'Snapchat', iconLibrary: 'fa6', iconName: 'snapchat', iconStyle: 'brand', brandColor: '#FFFFFF' },
  { id: 'reddit', label: 'Reddit', iconLibrary: 'fa6', iconName: 'reddit-alien', iconStyle: 'brand', brandColor: '#FFFFFF' },
  { id: 'facebook', label: 'Facebook', iconLibrary: 'fa6', iconName: 'facebook-f', iconStyle: 'brand', brandColor: '#FFFFFF' },
  { id: 'whatsapp', label: 'WhatsApp', iconLibrary: 'fa6', iconName: 'whatsapp', iconStyle: 'brand', brandColor: '#FFFFFF' },
  { id: 'pinterest', label: 'Pinterest', iconLibrary: 'fa6', iconName: 'pinterest-p', iconStyle: 'brand', brandColor: '#FFFFFF' }
];

export const FEELING_OPTIONS: SelectionOption[] = [
  { id: 'unfocused', label: 'Unfokussiert', iconLibrary: 'ion', iconName: 'eye-off-outline' },
  { id: 'guilty', label: 'Schlechtes Gewissen', iconLibrary: 'ion', iconName: 'alert-circle-outline' },
  { id: 'drained', label: 'Leer und müde', iconLibrary: 'ion', iconName: 'battery-dead-outline' },
  { id: 'restless', label: 'Innerlich unruhig', iconLibrary: 'ion', iconName: 'flash-outline' },
  { id: 'behind', label: 'Hinterher', iconLibrary: 'ion', iconName: 'timer-outline' },
  { id: 'disconnected', label: 'Nicht bei dir', iconLibrary: 'ion', iconName: 'moon-outline' }
];

export const ATTEMPT_OPTIONS: SelectionOption[] = [
  { id: 'screenTime', label: 'Screen-Time-Limits', iconLibrary: 'ion', iconName: 'timer-outline' },
  { id: 'deleteApps', label: 'Apps löschen', iconLibrary: 'ion', iconName: 'trash-outline' },
  { id: 'grayscale', label: 'Graustufenmodus', iconLibrary: 'ion', iconName: 'contrast-outline' },
  { id: 'detox', label: 'Digital Detox', iconLibrary: 'ion', iconName: 'leaf-outline' },
  { id: 'browserOnly', label: 'Nur Browser', iconLibrary: 'ion', iconName: 'globe-outline' },
  { id: 'nothingWorked', label: 'Nichts davon', iconLibrary: 'ion', iconName: 'close-circle-outline' }
];

export const PAYWALL_PLAN_OPTIONS: PaywallPlanOption[] = [
  {
    id: 'yearly',
    title: 'Jährlich',
    price: '59,99 €',
    subline: '12 Monate Zugriff',
    monthlyEquivalent: '4,99 € / Monat',
    badge: 'BELIEBTESTER PLAN'
  },
  {
    id: 'monthly',
    title: 'Monatlich',
    price: '17,99 €',
    subline: 'monatlich kündbar',
    monthlyEquivalent: '17,99 € / Monat'
  }
];

export const TRUST_BULLETS = [
  'Echte Reibung statt klickbarer Erinnerungen.',
  'Die Sperre greift genau im Impuls.'
];

export const SETUP_PREVIEW_STEPS = [
  'Screen-Time-Schutz ist aktiv',
  'Reps entsperren Trigger in Echtzeit'
];

export const AUTH_METHOD_OPTIONS: { id: AuthMethodId; label: string; description: string; icon: string }[] = [
  { id: 'apple', label: 'Mit Apple fortfahren', description: 'Am schnellsten.', icon: 'logo-apple' },
  { id: 'email', label: 'Mit E-Mail fortfahren', description: 'Klassisch.', icon: 'mail-outline' },
  { id: 'skip', label: 'Später sichern', description: 'Jetzt starten.', icon: 'arrow-forward-outline' }
];

export const PUSHLY_TRIAL_REP_TARGET = 3;

export const getAppOption = (id: AppOptionId) =>
  DISTRACTING_APP_OPTIONS.find((option) => option.id === id) ?? DISTRACTING_APP_OPTIONS[0];

export const getDiagnosisScore = (answers: OnboardingAnswers) => {
  const baseScore =
    34 +
    answers.distractingApps.length * 8 +
    answers.feelings.length * 9 +
    Math.round(answers.dailyScrollMinutes / 4) +
    answers.attempts.length * 4;

  return Math.max(48, Math.min(baseScore, 94));
};

export const getAverageComparison = () => 36;

export const getRecommendedPushUps = (answers: OnboardingAnswers) => {
  return Math.max(12, Math.min(Math.round(answers.dailyScrollMinutes / 3.2), 42));
};

export const getMonthlyHoursLost = (answers: OnboardingAnswers) => {
  return Math.round((answers.dailyScrollMinutes * 30) / 60);
};
