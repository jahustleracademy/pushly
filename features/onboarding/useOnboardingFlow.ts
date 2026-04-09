import { useEffect, useRef, useState } from 'react';
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
// Production default: keep JS fallback off and count natively.
// Can be re-enabled temporarily as an explicit safety net during native counter investigations.
const ENABLE_JS_PUSHUP_FALLBACK_IN_TRIAL = false;
const ENABLE_TRIAL_DEBUG_LOGGING = __DEV__;

export function useOnboardingFlow() {
  const [answers, setAnswers] = useState<OnboardingAnswers>(DEFAULT_ONBOARDING_ANSWERS);
  const [stepIndex, setStepIndex] = useState(0);
  const [hydrated, setHydrated] = useState(false);
  const pushupFallbackCounter = useRef<PushupFallbackCounterState>(initialPushupFallbackCounterState());
  const poseFrameCounter = useRef(0);

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
    poseFrameCounter.current += 1;
    const nativeRepCount = Math.max(0, frame.repCount ?? 0);
    if (nativeRepCount > pushupFallbackCounter.current.reps) {
      pushupFallbackCounter.current.reps = nativeRepCount;
    }
    const fallbackRepCount = currentStepId === 'pushUpTrial'
      ? updatePushupFallbackCounter(pushupFallbackCounter.current, frame)
      : pushupFallbackCounter.current.reps;
    const shouldUseFallbackForTrial = ENABLE_JS_PUSHUP_FALLBACK_IN_TRIAL && currentStepId === 'pushUpTrial';
    const resolvedRepCount = shouldUseFallbackForTrial
      ? Math.max(nativeRepCount, fallbackRepCount)
      : nativeRepCount;

    if (ENABLE_TRIAL_DEBUG_LOGGING && currentStepId === 'pushUpTrial' && poseFrameCounter.current % 10 === 0) {
      const debug = frame.pushupDebug;
      console.log('[pushup-trial]', {
        state: debug?.state ?? frame.state,
        repCount: debug?.repCount ?? resolvedRepCount,
        requestedBackend: debug?.requestedBackend ?? frame.requestedBackend ?? frame.poseBackend,
        activeBackend: debug?.activeBackend ?? frame.activeBackend ?? frame.poseBackend,
        compiledWithMediaPipe: debug?.compiledWithMediaPipe ?? frame.compiledWithMediaPipe,
        mediapipeAvailable: debug?.mediapipeAvailable ?? frame.mediapipeAvailable,
        mediapipeInitReason: debug?.mediapipeInitReason ?? frame.mediapipeInitReason,
        fallbackReason: debug?.fallbackReason ?? frame.fallbackReason,
        repBlockedReasons: debug?.repBlockedReasons ?? frame.diagnostics?.repBlockedReasons ?? frame.repDebug?.blockedReasons ?? [],
        countGatePassed: debug?.countGatePassed,
        countGateBlocked: debug?.countGateBlocked,
        countGateBlockReason: debug?.countGateBlockReason,
        descendingSignal: debug?.descendingSignal,
        ascendingSignal: debug?.ascendingSignal,
        torsoDownTravel: debug?.torsoDownTravel,
        torsoRecoveryToTop: debug?.torsoRecoveryToTop,
        shoulderDownTravel: debug?.shoulderDownTravel,
        shoulderRecoveryToTop: debug?.shoulderRecoveryToTop
      });
    }

    setAnswers((previous) => ({
      ...previous,
      pushUpInstruction: frame.instruction,
      pushUpFormEvidenceScore: frame.formEvidenceScore,
      pushUpRepCount: Math.max(previous.pushUpRepCount, resolvedRepCount),
      pushUpState: frame.state,
      pushUpTestPassed: previous.pushUpTestPassed || resolvedRepCount >= PUSHLY_TRIAL_REP_TARGET
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

type PushupFallbackCounterState = {
  phase: 'top' | 'descending' | 'bottom' | 'ascending';
  reps: number;
  cooldownFrames: number;
  bottomFrames: number;
  topFrames: number;
  cycleMinElbowAngle: number;
  cycleTopShoulderY: number | null;
  cycleBottomShoulderY: number | null;
};

function initialPushupFallbackCounterState(): PushupFallbackCounterState {
  return {
    phase: 'top',
    reps: 0,
    cooldownFrames: 0,
    bottomFrames: 0,
    topFrames: 0,
    cycleMinElbowAngle: 180,
    cycleTopShoulderY: null,
    cycleBottomShoulderY: null
  };
}

function updatePushupFallbackCounter(state: PushupFallbackCounterState, frame: PoseFrame): number {
  const elbowAngle = averageElbowAngle(frame);
  const shoulderY = averageShoulderY(frame);

  if (state.cooldownFrames > 0) {
    state.cooldownFrames -= 1;
  }

  if (elbowAngle == null) {
    state.bottomFrames = 0;
    state.topFrames = 0;
    return state.reps;
  }

  let nextPhase = state.phase;
  const topThreshold = 156;
  const descendThreshold = 130;
  const bottomThreshold = 102;
  const recoverThreshold = 150;

  if (nextPhase === 'top') {
    if (shoulderY != null && state.cycleTopShoulderY == null) {
      state.cycleTopShoulderY = shoulderY;
      state.cycleBottomShoulderY = shoulderY;
    }
    if (elbowAngle < descendThreshold) {
      nextPhase = 'descending';
      state.cycleMinElbowAngle = elbowAngle;
      state.bottomFrames = elbowAngle < bottomThreshold ? 1 : 0;
      if (shoulderY != null) {
        state.cycleTopShoulderY = shoulderY;
        state.cycleBottomShoulderY = shoulderY;
      }
    }
  } else if (nextPhase === 'descending') {
    state.cycleMinElbowAngle = Math.min(state.cycleMinElbowAngle, elbowAngle);
    if (shoulderY != null) {
      state.cycleBottomShoulderY = state.cycleBottomShoulderY == null
        ? shoulderY
        : Math.min(state.cycleBottomShoulderY, shoulderY);
    }
    if (elbowAngle < bottomThreshold) {
      state.bottomFrames += 1;
    } else {
      state.bottomFrames = Math.max(0, state.bottomFrames - 1);
    }
    if (state.bottomFrames >= 2) {
      nextPhase = 'bottom';
      state.topFrames = 0;
    } else if (elbowAngle > topThreshold + 4) {
      nextPhase = 'top';
      state.bottomFrames = 0;
    }
  } else if (nextPhase === 'bottom') {
    if (elbowAngle > recoverThreshold) {
      nextPhase = 'ascending';
      state.topFrames = 1;
    }
  } else if (nextPhase === 'ascending') {
    if (elbowAngle > recoverThreshold) {
      state.topFrames += 1;
    } else {
      state.topFrames = Math.max(0, state.topFrames - 1);
    }

    const shoulderTravel =
      state.cycleTopShoulderY != null && state.cycleBottomShoulderY != null
        ? Math.max(0, state.cycleTopShoulderY - state.cycleBottomShoulderY)
        : 0;
    let cycleStrongEnough =
      state.cycleMinElbowAngle <= 112
      && shoulderTravel >= 0.008;
    if (state.cycleTopShoulderY != null && state.cycleBottomShoulderY != null) {
      cycleStrongEnough = cycleStrongEnough && state.cycleBottomShoulderY < state.cycleTopShoulderY;
    }

    if (state.topFrames >= 2 && cycleStrongEnough && state.cooldownFrames == 0) {
      state.reps += 1;
      state.cooldownFrames = 4;
      nextPhase = 'top';
      state.bottomFrames = 0;
      state.topFrames = 0;
      state.cycleMinElbowAngle = 180;
      state.cycleTopShoulderY = shoulderY;
      state.cycleBottomShoulderY = shoulderY;
    } else if (state.topFrames >= 3 && !cycleStrongEnough) {
      // If return to top happened but cycle evidence is weak, re-arm without counting.
      nextPhase = 'top';
      state.bottomFrames = 0;
      state.topFrames = 0;
      state.cycleMinElbowAngle = 180;
      state.cycleTopShoulderY = shoulderY;
      state.cycleBottomShoulderY = shoulderY;
    }
  }

  state.phase = nextPhase;
  return state.reps;
}

function averageElbowAngle(frame: PoseFrame): number | null {
  const left = elbowAngleForSide(frame, 'left');
  const right = elbowAngleForSide(frame, 'right');
  if (left == null && right == null) {
    return null;
  }
  if (left == null) {
    return right;
  }
  if (right == null) {
    return left;
  }
  return (left + right) / 2;
}

function averageShoulderY(frame: PoseFrame): number | null {
  const left = getJoint(frame, 'leftShoulder');
  const right = getJoint(frame, 'rightShoulder');
  const ys = [left?.y, right?.y].filter((value): value is number => typeof value === 'number' && Number.isFinite(value));
  if (ys.length === 0) {
    return null;
  }
  return ys.reduce((sum, value) => sum + value, 0) / ys.length;
}

function elbowAngleForSide(frame: PoseFrame, side: 'left' | 'right'): number | null {
  const shoulder = getJoint(frame, side === 'left' ? 'leftShoulder' : 'rightShoulder');
  const elbow = getJoint(frame, side === 'left' ? 'leftElbow' : 'rightElbow');
  const wrist = getJoint(frame, side === 'left' ? 'leftWrist' : 'rightWrist');
  if (!shoulder || !elbow || !wrist) {
    return null;
  }
  return angle(shoulder.x, shoulder.y, elbow.x, elbow.y, wrist.x, wrist.y);
}

function getJoint(frame: PoseFrame, name: string) {
  return frame.joints.find((joint) => {
    if (joint.name !== name) {
      return false;
    }
    if (!Number.isFinite(joint.x) || !Number.isFinite(joint.y)) {
      return false;
    }
    if (joint.isRenderable === false) {
      return false;
    }
    return (joint.confidence ?? 0) >= 0.12;
  });
}

function angle(ax: number, ay: number, bx: number, by: number, cx: number, cy: number): number {
  const abx = ax - bx;
  const aby = ay - by;
  const cbx = cx - bx;
  const cby = cy - by;
  const dot = abx * cbx + aby * cby;
  const magAB = Math.hypot(abx, aby);
  const magCB = Math.hypot(cbx, cby);
  const denominator = Math.max(1e-4, magAB * magCB);
  const cosine = Math.max(-1, Math.min(1, dot / denominator));
  return (Math.acos(cosine) * 180) / Math.PI;
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
