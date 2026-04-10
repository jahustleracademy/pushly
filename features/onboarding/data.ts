import type {
  AgeRangeId,
  AppOptionId,
  AppSelectionOption,
  AuthMethodId,
  AttemptOptionId,
  ExerciseTypeId,
  GoalId,
  OnboardingAnswers,
  OnboardingStepId,
  PaywallPlanOption,
  ReminderSlotId,
  SelectionOption
} from './types';

export const ONBOARDING_STEP_ORDER: OnboardingStepId[] = [
  'hero',
  'quizIntro',
  'name',
  'goals',
  'scrollMinutes',
  'targetMinutes',
  'distractingApps',
  'feelings',
  'ageRange',
  'attempts',
  'diagnosis',
  'reframe',
  'reframeGain',
  'mechanic',
  'reminderTime',
  'exerciseChoice',
  'screenTimePermission',
  'cameraCalibration',
  'pushUpTrial',
  'setupBridge',
  'rating',
  'paywall',
  'journey',
  'auth'
];

export const DEFAULT_ONBOARDING_ANSWERS: OnboardingAnswers = {
  name: '',
  goalId: '',
  distractingApps: [],
  dailyScrollMinutes: 96,
  targetScrollMinutes: 60,
  feelings: [],
  ageRange: '',
  attempts: [],
  reminderSlot: '',
  exerciseType: '',
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
  { id: 'drained', label: 'Leer im Kopf', iconLibrary: 'ion', iconName: 'battery-dead-outline' },
  { id: 'restless', label: 'Innerlich unruhig', iconLibrary: 'ion', iconName: 'flash-outline' },
  { id: 'behind', label: 'Unter Zeitdruck', iconLibrary: 'ion', iconName: 'timer-outline' },
  { id: 'disconnected', label: 'Nicht richtig bei mir', iconLibrary: 'ion', iconName: 'moon-outline' }
];

export const ATTEMPT_OPTIONS: SelectionOption[] = [
  { id: 'screenTime', label: 'Screen-Time-Limits', iconLibrary: 'ion', iconName: 'timer-outline' },
  { id: 'deleteApps', label: 'Apps gelöscht', iconLibrary: 'ion', iconName: 'trash-outline' },
  { id: 'grayscale', label: 'Graustufenmodus', iconLibrary: 'ion', iconName: 'contrast-outline' },
  { id: 'detox', label: 'Digital Detox', iconLibrary: 'ion', iconName: 'leaf-outline' },
  { id: 'browserOnly', label: 'Nur im Browser genutzt', iconLibrary: 'ion', iconName: 'globe-outline' },
  { id: 'nothingWorked', label: 'Nichts hat dauerhaft geholfen', iconLibrary: 'ion', iconName: 'close-circle-outline' }
];

export const GOAL_OPTIONS: { id: GoalId; title: string; subtitle: string; icon: string }[] = [
  { id: 'sleep', title: 'Besser schlafen', subtitle: 'Weniger Abend-Scrollen.', icon: 'moon-outline' },
  { id: 'focus', title: 'Mehr Fokus', subtitle: 'Weniger Ablenkung tagsüber.', icon: 'sparkles-outline' },
  { id: 'discipline', title: 'Mehr Selbstkontrolle', subtitle: 'Impuls stoppen statt nachgeben.', icon: 'shield-checkmark-outline' },
  { id: 'energy', title: 'Mehr Energie', subtitle: 'Weniger mentale Erschöpfung.', icon: 'flash-outline' }
];

export const AGE_RANGE_OPTIONS: { id: AgeRangeId; title: string; icon: string }[] = [
  { id: 'under18', title: 'Unter 18', icon: 'school-outline' },
  { id: '18to24', title: '18-24', icon: 'person-outline' },
  { id: '25to34', title: '25-34', icon: 'people-outline' },
  { id: '35plus', title: '35+', icon: 'sparkles-outline' }
];

export const REMINDER_SLOT_OPTIONS: { id: ReminderSlotId; title: string; subtitle: string; icon: string }[] = [
  { id: 'morning', title: 'Morgens', subtitle: 'Startet fokussiert in den Tag.', icon: 'sunny-outline' },
  { id: 'afternoon', title: 'Nachmittags', subtitle: 'Gut für Durchhänger.', icon: 'partly-sunny-outline' },
  { id: 'evening', title: 'Abends', subtitle: 'Hilft gegen Endlos-Scrollen.', icon: 'moon-outline' }
];

export const EXERCISE_TYPE_OPTIONS: { id: ExerciseTypeId; title: string; subtitle: string; icon: string }[] = [
  { id: 'pushups', title: 'Push-ups', subtitle: 'Klar, direkt, effektiv.', icon: 'barbell-outline' },
  { id: 'squats', title: 'Squats', subtitle: 'Leiser und gelenkschonend.', icon: 'walk-outline' },
  { id: 'mixed', title: 'Gemischt', subtitle: 'Abwechslung je nach Situation.', icon: 'shuffle-outline' }
];

export const PAYWALL_PLAN_OPTIONS: PaywallPlanOption[] = [
  {
    id: 'yearly',
    title: 'Jährlich',
    price: '59,99 €',
    subline: '12 Monate Zugriff',
    monthlyEquivalent: '4,99 € / Monat',
    badge: 'HÄUFIG GEWÄHLT'
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
  'Du musst nicht jedes Mal neu mit dir verhandeln.',
  'Die Regel bleibt gleich: erst Reps, dann Zugriff.'
];

export const SETUP_PREVIEW_STEPS = [
  'Screen-Time-Schutz ist aktiv',
  'Apps entsperren nach deinen Reps'
];

export const AUTH_METHOD_OPTIONS: { id: AuthMethodId; label: string; description: string; icon: string }[] = [
  { id: 'apple', label: 'Mit Apple fortfahren', description: 'Am schnellsten eingerichtet.', icon: 'logo-apple' },
  { id: 'email', label: 'Mit E-Mail fortfahren', description: 'Klassisch mit Login.', icon: 'mail-outline' },
  { id: 'skip', label: 'Später sichern', description: 'Jetzt direkt starten.', icon: 'arrow-forward-outline' }
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

export const getProjectedDaysPerYear = (answers: OnboardingAnswers) => {
  return Math.round((answers.dailyScrollMinutes * 365) / (60 * 24));
};
