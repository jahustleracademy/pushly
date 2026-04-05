import AsyncStorage from '@react-native-async-storage/async-storage';
import { DEFAULT_ONBOARDING_ANSWERS } from './data';
import type { OnboardingDraft } from './types';

export const ONBOARDING_COMPLETED_KEY = '@pushly_onboarding_completed_v1';
export const ONBOARDING_DRAFT_KEY = '@pushly_onboarding_draft_v1';

export async function getOnboardingCompleted() {
  const value = await AsyncStorage.getItem(ONBOARDING_COMPLETED_KEY);
  return value === 'true';
}

export async function markOnboardingCompleted() {
  await AsyncStorage.setItem(ONBOARDING_COMPLETED_KEY, 'true');
}

export async function loadOnboardingDraft(): Promise<OnboardingDraft> {
  const value = await AsyncStorage.getItem(ONBOARDING_DRAFT_KEY);

  if (!value) {
    return {
      stepIndex: 0,
      answers: DEFAULT_ONBOARDING_ANSWERS
    };
  }

  try {
    const parsed = JSON.parse(value) as OnboardingDraft;

    return {
      stepIndex: typeof parsed.stepIndex === 'number' ? parsed.stepIndex : 0,
      answers: {
        ...DEFAULT_ONBOARDING_ANSWERS,
        ...parsed.answers
      }
    };
  } catch {
    return {
      stepIndex: 0,
      answers: DEFAULT_ONBOARDING_ANSWERS
    };
  }
}

export async function saveOnboardingDraft(draft: OnboardingDraft) {
  await AsyncStorage.setItem(ONBOARDING_DRAFT_KEY, JSON.stringify(draft));
}

export async function clearOnboardingDraft() {
  await AsyncStorage.removeItem(ONBOARDING_DRAFT_KEY);
}
