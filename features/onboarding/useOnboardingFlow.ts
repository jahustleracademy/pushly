import { useEffect, useState } from 'react';
import {
  AUTH_METHOD_OPTIONS,
  DEFAULT_ONBOARDING_ANSWERS,
  ONBOARDING_STEP_ORDER,
  PUSHLY_TRIAL_REP_TARGET
} from './data';
import {
  clearOnboardingDraft,
  loadOnboardingDraft,
  markOnboardingCompleted,
  saveOnboardingDraft
} from './storage';
import type {
  AppOptionId,
  AuthMethodId,
  AttemptOptionId,
  FeelingOptionId,
  OnboardingAnswers,
  PaywallPlanId
} from './types';
import type { PoseFrame, ProtectedSelectionSummary, ScreenTimeAuthorizationStatus, ShieldStatus } from '@/lib/native/pushly-native';

const MAX_DISTRACTING_APPS = 3;
const MAX_FEELINGS = 2;

export function useOnboardingFlow() {
  const [answers, setAnswers] = useState<OnboardingAnswers>(DEFAULT_ONBOARDING_ANSWERS);
  const [stepIndex, setStepIndex] = useState(0);
  const [hydrated, setHydrated] = useState(false);

  useEffect(() => {
    let mounted = true;

    loadOnboardingDraft().then((draft) => {
      if (!mounted) {
        return;
      }

      setAnswers(draft.answers);
      setStepIndex(Math.max(0, Math.min(draft.stepIndex, ONBOARDING_STEP_ORDER.length - 1)));
      setHydrated(true);
    });

    return () => {
      mounted = false;
    };
  }, []);

  useEffect(() => {
    if (!hydrated) {
      return;
    }

    saveOnboardingDraft({ stepIndex, answers }).catch(() => {
      // Keep the flow usable even if draft persistence fails.
    });
  }, [answers, hydrated, stepIndex]);

  const currentStepId = ONBOARDING_STEP_ORDER[stepIndex];

  useEffect(() => {
    if (currentStepId !== 'protectApps') {
      return;
    }

    if (answers.protectedApps.length > 0 || answers.distractingApps.length === 0) {
      return;
    }

    setAnswers((previous) => ({
      ...previous,
      protectedApps: previous.distractingApps.slice(0, MAX_DISTRACTING_APPS)
    }));
  }, [answers.distractingApps, answers.protectedApps.length, currentStepId]);

  const canContinue = getCanContinue(currentStepId, answers);

  const updateName = (name: string) => {
    setAnswers((previous) => ({ ...previous, name }));
  };

  const updateScrollMinutes = (dailyScrollMinutes: number) => {
    setAnswers((previous) => ({ ...previous, dailyScrollMinutes }));
  };

  const selectPlan = (planId: PaywallPlanId) => {
    setAnswers((previous) => ({ ...previous, planId }));
  };

  const setScreenTimeStatus = (screenTimeStatus: ScreenTimeAuthorizationStatus) => {
    setAnswers((previous) => ({ ...previous, screenTimeStatus }));
  };

  const setScreenTimeSelection = (screenTimeSelection: ProtectedSelectionSummary) => {
    setAnswers((previous) => ({ ...previous, screenTimeSelection }));
  };

  const setShieldStatus = (shieldStatus: ShieldStatus) => {
    setAnswers((previous) => ({ ...previous, shieldStatus }));
  };

  const setPoseFrame = (frame: PoseFrame) => {
    setAnswers((previous) => ({
      ...previous,
      pushUpInstruction: frame.instruction,
      pushUpFormScore: frame.formScore,
      pushUpRepCount: Math.max(previous.pushUpRepCount, frame.repCount),
      pushUpState: frame.state,
      pushUpTestPassed: previous.pushUpTestPassed || frame.repCount >= PUSHLY_TRIAL_REP_TARGET
    }));
  };

  const selectAuthMethod = (authMethod: AuthMethodId) => {
    setAnswers((previous) => ({ ...previous, authMethod }));
  };

  const toggleDistractingApp = (appId: AppOptionId) => {
    setAnswers((previous) => ({
      ...previous,
      distractingApps: toggleSelection(previous.distractingApps, appId, MAX_DISTRACTING_APPS)
    }));
  };

  const toggleProtectedApp = (appId: AppOptionId) => {
    setAnswers((previous) => ({
      ...previous,
      protectedApps: toggleSelection(previous.protectedApps, appId, MAX_DISTRACTING_APPS)
    }));
  };

  const toggleFeeling = (feelingId: FeelingOptionId) => {
    setAnswers((previous) => ({
      ...previous,
      feelings: toggleSelection(previous.feelings, feelingId, MAX_FEELINGS)
    }));
  };

  const toggleAttempt = (attemptId: AttemptOptionId) => {
    setAnswers((previous) => ({
      ...previous,
      attempts: toggleSelection(previous.attempts, attemptId)
    }));
  };

  const goNext = () => {
    if (!canContinue) {
      return;
    }

    setStepIndex((previous) => Math.min(previous + 1, ONBOARDING_STEP_ORDER.length - 1));
  };

  const goBack = () => {
    setStepIndex((previous) => Math.max(previous - 1, 0));
  };

  const complete = async () => {
    await markOnboardingCompleted();
    await clearOnboardingDraft();
  };

  return {
    answers,
    canContinue,
    complete,
    currentStepId,
    goBack,
    goNext,
    hydrated,
    isFirstStep: stepIndex === 0,
    progress: getProgress(stepIndex),
    stepIndex,
    stepCount: ONBOARDING_STEP_ORDER.length,
    toggleAttempt,
    toggleDistractingApp,
    toggleFeeling,
    toggleProtectedApp,
    updateName,
    updateScrollMinutes,
    selectPlan,
    selectAuthMethod,
    setPoseFrame,
    setScreenTimeSelection,
    setScreenTimeStatus,
    setShieldStatus
  };
}

function toggleSelection<T extends string>(current: T[], item: T, max = Number.POSITIVE_INFINITY) {
  if (current.includes(item)) {
    return current.filter((value) => value !== item);
  }

  if (current.length >= max) {
    return [...current.slice(1), item];
  }

  return [...current, item];
}

function getProgress(stepIndex: number) {
  const visibleStartIndex = 2;
  const visibleEndIndex = ONBOARDING_STEP_ORDER.length - 1;

  if (stepIndex < visibleStartIndex) {
    return 0;
  }

  return Math.min((stepIndex - visibleStartIndex + 1) / (visibleEndIndex - visibleStartIndex + 1), 1);
}

function getCanContinue(stepId: string, answers: OnboardingAnswers) {
  switch (stepId) {
    case 'name':
      return answers.name.trim().length >= 2;
    case 'distractingApps':
      return answers.distractingApps.length >= 2;
    case 'scrollMinutes':
      return answers.dailyScrollMinutes >= 15;
    case 'feelings':
      return answers.feelings.length >= 1;
    case 'attempts':
      return answers.attempts.length >= 1;
    case 'protectApps':
      return answers.protectedApps.length >= 1;
    case 'screenTimePermission':
      return answers.screenTimeStatus === 'unsupported' || (answers.screenTimeStatus === 'approved' && answers.screenTimeSelection.hasSelection);
    case 'pushUpTrial':
      return answers.pushUpTestPassed;
    case 'auth':
      return AUTH_METHOD_OPTIONS.some((option) => option.id === answers.authMethod);
    default:
      return true;
  }
}
