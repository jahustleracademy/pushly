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
  AgeRangeId,
  AppOptionId,
  AuthMethodId,
  AttemptOptionId,
  ExerciseTypeId,
  FeelingOptionId,
  GoalId,
  OnboardingAnswers,
  PaywallPlanId
} from './types';
import type { PoseFrame, ProtectedSelectionSummary, ScreenTimeAuthorizationStatus, ShieldStatus } from '@/lib/native/pushly-native';

// Production default: keep JS fallback off and count natively.
// Can be re-enabled temporarily as an explicit safety net during native counter investigations.
const ENABLE_JS_PUSHUP_FALLBACK_IN_TRIAL = false;
const ENABLE_TRIAL_DEBUG_LOGGING = __DEV__;
const PUSHUP_TRIAL_LOG_MODE: 'compact' | 'verbose' = __DEV__ ? 'verbose' : 'compact';

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

      setAnswers(withResetPushupTrialState(sanitizeOnboardingAnswers(draft.answers)));
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
    if (currentStepId === 'pushUpTrial') {
      return;
    }

    pushupFallbackCounter.current = initialPushupFallbackCounterState();
    poseFrameCounter.current = 0;
    setAnswers((previous) => withResetPushupTrialState(previous));
  }, [currentStepId]);

  const canContinue = getCanContinue(currentStepId, answers);

  const updateName = (name: string) => {
    setAnswers((previous) => ({ ...previous, name }));
  };

  const selectGoal = (goalId: GoalId) => {
    setAnswers((previous) => ({ ...previous, goalId }));
  };

  const updateScrollMinutes = (dailyScrollMinutes: number) => {
    setAnswers((previous) => ({ ...previous, dailyScrollMinutes }));
  };

  const updateTargetMinutes = (targetScrollMinutes: number) => {
    setAnswers((previous) => ({ ...previous, targetScrollMinutes }));
  };

  const selectAgeRange = (ageRange: AgeRangeId) => {
    setAnswers((previous) => ({ ...previous, ageRange }));
  };

  const selectReminderSlot = (reminderSlot: OnboardingAnswers['reminderSlot']) => {
    setAnswers((previous) => ({ ...previous, reminderSlot }));
  };

  const selectExerciseType = (exerciseType: ExerciseTypeId) => {
    setAnswers((previous) => ({ ...previous, exerciseType }));
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
    const debug = frame.pushupDebug;

    if (ENABLE_TRIAL_DEBUG_LOGGING && currentStepId === 'pushUpTrial' && debug?.repStateTransitionEvent) {
      console.log('[pushup-trial-transition]', {
        event: debug.repStateTransitionEvent,
        frameIndex: debug.frameIndex,
        timestampSeconds: debug.timestampSeconds,
        state: debug.repStateMachineState ?? debug.state
      });
    }

    if (ENABLE_TRIAL_DEBUG_LOGGING && currentStepId === 'pushUpTrial' && poseFrameCounter.current % 10 === 0) {
      const compact = {
        state: debug?.state ?? frame.state,
        repStateMachineState: debug?.repStateMachineState,
        repStateTransitionEvent: debug?.repStateTransitionEvent,
        repCount: debug?.repCount ?? resolvedRepCount,
        frameIndex: debug?.frameIndex,
        timestampSeconds: debug?.timestampSeconds,
        requestedBackend: debug?.requestedBackend ?? frame.requestedBackend ?? frame.poseBackend,
        activeBackend: debug?.activeBackend ?? frame.activeBackend ?? frame.poseBackend,
        compiledWithMediaPipe: debug?.compiledWithMediaPipe ?? frame.compiledWithMediaPipe,
        mediapipeAvailable: debug?.mediapipeAvailable ?? frame.mediapipeAvailable,
        mediapipeInitReason: debug?.mediapipeInitReason ?? frame.mediapipeInitReason,
        fallbackReason: debug?.fallbackReason ?? frame.fallbackReason,
        repBlockedReasons: debug?.repBlockedReasons ?? frame.diagnostics?.repBlockedReasons ?? frame.repDebug?.blockedReasons ?? [],
        whyRepDidNotCount: debug?.whyRepDidNotCount,
        firstFinalBlocker: debug?.firstFinalBlocker,
        lastFailedGate: debug?.lastFailedGate,
        lastSuccessfulGate: debug?.lastSuccessfulGate,
        bodyFound: debug?.bodyFound,
        trackingQualityPass: debug?.trackingQualityPass,
        logicQualityPass: debug?.logicQualityPass,
        bottomGate: debug?.bottomGate,
        ascentGate: debug?.ascentGate,
        topRecoveryGate: debug?.topRecoveryGate,
        rearmGate: debug?.rearmGate,
        strictCycleReady: debug?.strictCycleReady,
        cycleCoreReady: debug?.cycleCoreReady,
        topReady: debug?.topReady,
        descendingStarted: debug?.descendingStarted,
        bottomLatched: debug?.bottomLatched,
        ascendingStarted: debug?.ascendingStarted,
        topRecovered: debug?.topRecovered,
        repCommitted: debug?.repCommitted,
        rearmReady: debug?.rearmReady,
        resetReason: debug?.resetReason,
        timeoutOrAbortReason: debug?.timeoutOrAbortReason,
        countCommitReady: debug?.countCommitReady,
        countGatePassed: debug?.countGatePassed,
        countGateBlocked: debug?.countGateBlocked,
        countGateBlockReason: debug?.countGateBlockReason,
        descendingSignal: debug?.descendingSignal,
        ascendingSignal: debug?.ascendingSignal,
        torsoDownTravel: debug?.torsoDownTravel,
        torsoRecoveryToTop: debug?.torsoRecoveryToTop,
        shoulderDownTravel: debug?.shoulderDownTravel,
        shoulderRecoveryToTop: debug?.shoulderRecoveryToTop
      };
      if (PUSHUP_TRIAL_LOG_MODE === 'verbose') {
        console.log('[pushup-trial]', {
          ...compact,
          rawTorsoY: debug?.rawTorsoY,
          rawShoulderY: debug?.rawShoulderY,
          smoothedTorsoY: debug?.smoothedTorsoY,
          smoothedShoulderY: debug?.smoothedShoulderY,
          rawTorsoVelocity: debug?.rawTorsoVelocity,
          rawShoulderVelocity: debug?.rawShoulderVelocity,
          smoothedTorsoVelocity: debug?.smoothedTorsoVelocity,
          smoothedShoulderVelocity: debug?.smoothedShoulderVelocity,
          bottomCandidateFrames: debug?.bottomCandidateFrames,
          bottomConfirmedFrames: debug?.bottomConfirmedFrames,
          bottomNearMiss: debug?.bottomNearMiss,
          minDescendingFramesRequired: debug?.minDescendingFramesRequired,
          minBottomFramesRequired: debug?.minBottomFramesRequired,
          minAscendingFramesRequired: debug?.minAscendingFramesRequired,
          minTopRecoveryFramesRequired: debug?.minTopRecoveryFramesRequired,
          rearmBlockedReason: debug?.rearmBlockedReason,
          framesUntilRearm: debug?.framesUntilRearm,
          rearmMissingCondition: debug?.rearmMissingCondition,
          weakestLandmark: debug?.weakestLandmark,
          landmarkQuality: debug?.landmarkQuality,
          repsAttemptedEstimate: debug?.repsAttemptedEstimate,
          repsCommitted: debug?.repsCommitted,
          repsBlockedByBottom: debug?.repsBlockedByBottom,
          repsBlockedByTopRecovery: debug?.repsBlockedByTopRecovery,
          repsBlockedByRearm: debug?.repsBlockedByRearm,
          repsBlockedByTrackingLoss: debug?.repsBlockedByTrackingLoss,
          repsBlockedByTravel: debug?.repsBlockedByTravel,
          repsBlockedByQuality: debug?.repsBlockedByQuality
        });
      } else {
        console.log('[pushup-trial]', compact);
      }
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
      distractingApps: toggleSelection(previous.distractingApps, appId)
    }));
  };

  const toggleProtectedApp = (appId: AppOptionId) => {
    setAnswers((previous) => ({
      ...previous,
      protectedApps: toggleSelection(previous.protectedApps, appId)
    }));
  };

  const toggleFeeling = (feelingId: FeelingOptionId) => {
    setAnswers((previous) => ({
      ...previous,
      feelings: toggleSelection(previous.feelings, feelingId)
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
    selectGoal,
    updateScrollMinutes,
    updateTargetMinutes,
    selectAgeRange,
    selectReminderSlot,
    selectExerciseType,
    selectPlan,
    selectAuthMethod,
    setPoseFrame,
    setScreenTimeSelection,
    setScreenTimeStatus,
    setShieldStatus
  };
}

function sanitizeOnboardingAnswers(answers: OnboardingAnswers): OnboardingAnswers {
  const toNumber = (value: unknown, fallback: number) =>
    typeof value === 'number' && Number.isFinite(value) ? value : fallback;
  const toString = (value: unknown, fallback = '') =>
    typeof value === 'string' ? value : fallback;
  const toArray = <T extends string>(value: unknown): T[] =>
    Array.isArray(value) ? (value.filter((item): item is T => typeof item === 'string') as T[]) : [];

  return {
    ...answers,
    name: toString(answers.name),
    goalId: toString(answers.goalId) as OnboardingAnswers['goalId'],
    distractingApps: toArray(answers.distractingApps),
    dailyScrollMinutes: Math.max(60, Math.min(960, Math.round(toNumber(answers.dailyScrollMinutes, 96)))),
    targetScrollMinutes: Math.max(60, Math.min(960, Math.round(toNumber(answers.targetScrollMinutes, 60)))),
    feelings: toArray(answers.feelings),
    ageRange: toString(answers.ageRange) as OnboardingAnswers['ageRange'],
    attempts: toArray(answers.attempts),
    reminderSlot: toString(answers.reminderSlot) as OnboardingAnswers['reminderSlot'],
    exerciseType: toString(answers.exerciseType) as OnboardingAnswers['exerciseType'],
    protectedApps: toArray(answers.protectedApps),
    planId: toString(answers.planId, 'yearly') as OnboardingAnswers['planId'],
    authMethod: toString(answers.authMethod) as OnboardingAnswers['authMethod']
  };
}

function withResetPushupTrialState(answers: OnboardingAnswers): OnboardingAnswers {
  const defaultInstruction = DEFAULT_ONBOARDING_ANSWERS.pushUpInstruction;
  const alreadyReset =
    answers.pushUpRepCount === 0 &&
    answers.pushUpState === 'idle' &&
    answers.pushUpFormEvidenceScore === 0 &&
    answers.pushUpInstruction === defaultInstruction &&
    answers.pushUpTestPassed === false;

  if (alreadyReset) {
    return answers;
  }

  return {
    ...answers,
    pushUpRepCount: 0,
    pushUpState: 'idle',
    pushUpInstruction: defaultInstruction,
    pushUpFormEvidenceScore: 0,
    pushUpTestPassed: false
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
    case 'goals':
      return answers.goalId.length > 0;
    case 'distractingApps':
      return answers.distractingApps.length >= 1;
    case 'scrollMinutes':
      return answers.dailyScrollMinutes >= 15;
    case 'targetMinutes':
      return answers.targetScrollMinutes >= 10;
    case 'feelings':
      return answers.feelings.length >= 1;
    case 'ageRange':
      return answers.ageRange.length > 0;
    case 'attempts':
      return answers.attempts.length >= 1;
    case 'reminderTime':
      return answers.reminderSlot.length > 0;
    case 'exerciseChoice':
      return answers.exerciseType.length > 0;
    case 'screenTimePermission':
      return answers.screenTimeStatus === 'unsupported' || (answers.screenTimeStatus === 'approved' && answers.screenTimeSelection.hasSelection);
    case 'pushUpTrial':
      return true;
    case 'auth':
      return AUTH_METHOD_OPTIONS.some((option) => option.id === answers.authMethod);
    default:
      return true;
  }
}
