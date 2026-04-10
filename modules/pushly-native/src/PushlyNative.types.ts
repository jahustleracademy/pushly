import type { StyleProp, ViewStyle } from 'react-native';

export type ScreenTimeAuthorizationStatus =
  | 'not_determined'
  | 'denied'
  | 'approved'
  | 'restricted'
  | 'unsupported';

export type ShieldStatus = 'inactive' | 'active' | 'unsupported';
export type CameraAuthorizationStatus = 'not_determined' | 'denied' | 'authorized' | 'restricted' | 'unsupported';
export type DeviceActivityMonitoringStatus = 'active' | 'inactive' | 'unsupported';
export type PoseDebugExportResult = {
  path: string;
};

export type SharedCreditsSnapshotPayload = {
  payload: string | null;
};

export type ProtectedSelectionSummary = {
  appCount: number;
  categoryCount: number;
  webDomainCount: number;
  hasSelection: boolean;
  lastUpdatedAt?: string | null;
};

export type PushUpDetectionState =
  | 'idle'
  | 'body_found'
  | 'plank_locked'
  | 'descending'
  | 'bottom_reached'
  | 'ascending'
  | 'rep_counted'
  | 'tracking_assisted'
  | 'lost_tracking';

export type JointSourceType = 'measured' | 'lowConfidenceMeasured' | 'inferred' | 'predicted' | 'missing';
export type BodyVisibilityState = 'body_not_found' | 'body_partial' | 'body_assisted' | 'body_good';
export type MediaPipeInitReason =
  | 'pose_model_missing'
  | 'mediapipe_tasks_vision_not_compiled'
  | 'gpu_init_failed'
  | 'cpu_init_failed'
  | 'pose_landmarker_nil_unknown'
  | string;

// Legacy continuity state.
export type TrackingContinuityState = 'tracking' | 'reacquire' | 'lost';

// Detailed pose-state lifecycle.
export type PoseTrackingState = 'trackingFullBody' | 'trackingUpperBody' | 'reacquiring' | 'lost';

export type PoseBackendKind = 'mediapipe' | 'visionFallback' | 'vision' | 'mlkit';
export type BodyMode = 'fullBody' | 'upperBody' | 'unknown';
export type ReacquireSource = 'none' | 'face' | 'upperBody' | 'fullFrame' | 'previousTrack' | 'upperBodyRect' | 'fullFrameRefresh';

export type SkeletonJointName =
  | 'nose'
  | 'head'
  | 'leftShoulder'
  | 'rightShoulder'
  | 'leftElbow'
  | 'rightElbow'
  | 'leftWrist'
  | 'rightWrist'
  | 'leftHand'
  | 'rightHand'
  | 'leftHip'
  | 'rightHip'
  | 'leftKnee'
  | 'rightKnee'
  | 'leftAnkle'
  | 'rightAnkle'
  | 'leftFoot'
  | 'rightFoot';

export type SkeletonJoint = {
  name: SkeletonJointName;
  jointName?: SkeletonJointName;
  x: number;
  y: number;
  confidence: number;
  sourceType?: JointSourceType;
  isRenderable?: boolean;
  isLogicUsable?: boolean;
  visibility?: number;
  presence?: number;
  inFrame?: boolean;
};

export type PushupRepDebug = {
  frameIndex?: number;
  timestampSeconds?: number;
  currentRepState?: string;
  repStateMachineState?: string;
  repStateTransitionEvent?: string;
  smoothedElbowAngle?: number;
  repMinElbowAngle?: number;
  rawTorsoY?: number;
  rawShoulderY?: number;
  smoothedTorsoY?: number;
  smoothedShoulderY?: number;
  rawTorsoVelocity?: number;
  rawShoulderVelocity?: number;
  smoothedTorsoVelocity?: number;
  smoothedShoulderVelocity?: number;
  topReferenceTorsoY?: number;
  topReferenceShoulderY?: number;
  shoulderVelocity?: number;
  torsoVelocity?: number;
  descendingSignal?: boolean;
  ascendingSignal?: boolean;
  shoulderDownTravel?: number;
  shoulderRecoveryToTop?: number;
  torsoDownTravel?: number;
  torsoRecoveryToTop?: number;
  descendingFrames?: number;
  bottomCandidateFrames?: number;
  bottomConfirmedFrames?: number;
  bottomFrames?: number;
  ascendingFrames?: number;
  ascentFrames?: number;
  bottomReached?: boolean;
  bottomConfirmedLatched?: boolean;
  bottomNearMiss?: boolean;
  minDescendingFramesRequired?: number;
  minBottomFramesRequired?: number;
  minAscendingFramesRequired?: number;
  minTopRecoveryFramesRequired?: number;
  dominantEvidence?: number;
  measuredEvidence?: number;
  structuralEvidence?: number;
  upperBodyEvidence?: number;
  weakestLandmark?: string;
  weakestLandmarkConfidence?: number;
  missingLandmarks?: string[];
  landmarkQuality?: Record<string, { confidence: number; presence: number; usable: boolean }>;
  blockedReasons?: string[];
  canProgress?: boolean;
  logicBlockedFrames?: number;
  startupReady?: boolean;
  startupTopEvidence?: number;
  startupDescendBridgeUsed?: boolean;
  startBlockedReason?: string;
  repRearmPending?: boolean;
  topRecoveryFrames?: number;
  commitPathActive?: boolean;
  commitCancelledReason?: string;
  idleResetReason?: string;
  pendingCommitReason?: string;
  commitBlockedBy?: string;
  topReady?: boolean;
  descendingStarted?: boolean;
  bottomLatched?: boolean;
  ascendingStarted?: boolean;
  topRecovered?: boolean;
  repCommitted?: boolean;
  rearmReady?: boolean;
  resetReason?: string;
  timeoutOrAbortReason?: string;
  firstBlockingConditionAfterBottom?: string;
  lostTrackingAtBottom?: boolean;
  trackingLossDuringCommitPath?: number;
  trackingLossGraceFramesRemaining?: number;
  bottomHoldActive?: boolean;
  bottomReacquireState?: string;
  bottomSupportAnchors?: string[];
  bottomBlockedReason?: string;
  didEnterAscending?: boolean;
  didEnterTopRecovery?: boolean;
  rearmBlockedReason?: string;
  framesUntilRearm?: number;
  rearmConfirmProgress?: number;
  rearmMissingCondition?: string;
  whyRepDidNotCount?: string;
  firstFinalBlocker?: string;
  lastFailedGate?: string;
  lastSuccessfulGate?: string;
  bodyFound?: boolean;
  trackingQualityPass?: boolean;
  logicQualityPass?: boolean;
  bottomGate?: boolean;
  ascentGate?: boolean;
  rearmGate?: boolean;
  cycleCoreReady?: boolean;
  strictCycleReady?: boolean;
  floorFallbackCycleReady?: boolean;
  motionTravelGate?: boolean;
  topRecoveryGate?: boolean;
  countCommitReady?: boolean;
  torsoSupportReady?: boolean;
  shoulderSupportReady?: boolean;
  countGatePassed?: boolean;
  countGateBlocked?: boolean;
  countGateBlockReason?: string;
  stateTransitionEvent?: string;
  repsAttemptedEstimate?: number;
  repsCommitted?: number;
  repsBlockedByBottom?: number;
  repsBlockedByTopRecovery?: number;
  repsBlockedByRearm?: number;
  repsBlockedByTrackingLoss?: number;
  repsBlockedByTravel?: number;
  repsBlockedByQuality?: number;
  bottomConfirmedCount?: number;
  ascendingEnteredCount?: number;
  topRecoveryEnteredCount?: number;
  repCommitAttemptCount?: number;
  repCommitSuccessCount?: number;
  repCommitBlockedCount?: number;
};

export type PushupTrialDebug = {
  requestedBackend?: PoseBackendKind;
  activeBackend?: PoseBackendKind;
  fallbackAllowed?: boolean;
  fallbackUsed?: boolean;
  fallbackReason?: string;
  mediapipeAvailable?: boolean;
  compiledWithMediaPipe?: boolean;
  poseModelFound?: boolean;
  poseModelName?: string;
  poseModelPath?: string;
  poseLandmarkerInitStatus?: string;
  mediapipeInitReason?: MediaPipeInitReason;
  state?: PushUpDetectionState;
  repCount?: number;
  frameIndex?: number;
  timestampSeconds?: number;
  currentRepState?: string;
  repStateMachineState?: string;
  repStateTransitionEvent?: string;
  repBlockedReasons?: string[];
  trackingQuality?: number;
  logicQuality?: number;
  upperBodyCoverage?: number;
  wristRetention?: number;
  // Vision fallback stability diagnostics (tracker/anchor side).
  fallbackCoverage?: {
    upperBody?: number;
    fullBody?: number;
    hand?: number;
    requiredAnchors?: number;
  };
  fallbackAnchorStrength?: number;
  weakestRequiredLandmark?: string;
  weakestRequiredLandmarkConfidence?: number;
  sourceTypeTransitions?: Record<string, number>;
  visibilityHysteresisState?: {
    requiredVisibleCount?: number;
    requiredTotal?: number;
  };
  smoothedElbowAngle?: number;
  repMinElbowAngle?: number;
  rawTorsoY?: number;
  rawShoulderY?: number;
  smoothedTorsoY?: number;
  smoothedShoulderY?: number;
  rawTorsoVelocity?: number;
  rawShoulderVelocity?: number;
  smoothedTorsoVelocity?: number;
  smoothedShoulderVelocity?: number;
  topReferenceTorsoY?: number;
  topReferenceShoulderY?: number;
  descendingSignal?: boolean;
  ascendingSignal?: boolean;
  torsoDownTravel?: number;
  torsoRecoveryToTop?: number;
  shoulderDownTravel?: number;
  shoulderRecoveryToTop?: number;
  bottomReached?: boolean;
  descendingFrames?: number;
  bottomCandidateFrames?: number;
  bottomConfirmedFrames?: number;
  bottomFrames?: number;
  ascendingFrames?: number;
  ascentFrames?: number;
  bottomNearMiss?: boolean;
  bottomConfirmedLatched?: boolean;
  minDescendingFramesRequired?: number;
  minBottomFramesRequired?: number;
  minAscendingFramesRequired?: number;
  minTopRecoveryFramesRequired?: number;
  weakestLandmark?: string;
  weakestLandmarkConfidence?: number;
  missingLandmarks?: string[];
  landmarkQuality?: Record<string, { confidence: number; presence: number; usable: boolean }>;
  canProgress?: boolean;
  logicBlockedFrames?: number;
  startupReady?: boolean;
  startupTopEvidence?: number;
  startupDescendBridgeUsed?: boolean;
  startBlockedReason?: string;
  repRearmPending?: boolean;
  topRecoveryFrames?: number;
  commitPathActive?: boolean;
  commitCancelledReason?: string;
  idleResetReason?: string;
  pendingCommitReason?: string;
  commitBlockedBy?: string;
  topReady?: boolean;
  descendingStarted?: boolean;
  bottomLatched?: boolean;
  ascendingStarted?: boolean;
  topRecovered?: boolean;
  repCommitted?: boolean;
  rearmReady?: boolean;
  resetReason?: string;
  timeoutOrAbortReason?: string;
  firstBlockingConditionAfterBottom?: string;
  lostTrackingAtBottom?: boolean;
  trackingLossDuringCommitPath?: number;
  trackingLossGraceFramesRemaining?: number;
  bottomHoldActive?: boolean;
  bottomReacquireState?: string;
  bottomSupportAnchors?: string[];
  bottomBlockedReason?: string;
  didEnterAscending?: boolean;
  didEnterTopRecovery?: boolean;
  rearmBlockedReason?: string;
  framesUntilRearm?: number;
  rearmConfirmProgress?: number;
  rearmMissingCondition?: string;
  whyRepDidNotCount?: string;
  firstFinalBlocker?: string;
  lastFailedGate?: string;
  lastSuccessfulGate?: string;
  bodyFound?: boolean;
  trackingQualityPass?: boolean;
  logicQualityPass?: boolean;
  bottomGate?: boolean;
  ascentGate?: boolean;
  rearmGate?: boolean;
  cycleCoreReady?: boolean;
  strictCycleReady?: boolean;
  floorFallbackCycleReady?: boolean;
  motionTravelGate?: boolean;
  topRecoveryGate?: boolean;
  countCommitReady?: boolean;
  torsoSupportReady?: boolean;
  shoulderSupportReady?: boolean;
  countGatePassed?: boolean;
  countGateBlocked?: boolean;
  countGateBlockReason?: string;
  stateTransitionEvent?: string;
  repsAttemptedEstimate?: number;
  repsCommitted?: number;
  repsBlockedByBottom?: number;
  repsBlockedByTopRecovery?: number;
  repsBlockedByRearm?: number;
  repsBlockedByTrackingLoss?: number;
  repsBlockedByTravel?: number;
  repsBlockedByQuality?: number;
  bottomConfirmedCount?: number;
  ascendingEnteredCount?: number;
  topRecoveryEnteredCount?: number;
  repCommitAttemptCount?: number;
  repCommitSuccessCount?: number;
  repCommitBlockedCount?: number;
};

export type PoseFrame = {
  bodyDetected: boolean;
  confidence: number;
  formEvidenceScore: number;
  instruction: string;
  joints: SkeletonJoint[];
  repCount: number;
  state: PushUpDetectionState;
  repDebug?: PushupRepDebug;
  pushupDebug?: PushupTrialDebug;

  // Legacy continuity state (preserved).
  trackingState?: TrackingContinuityState;
  trackingContinuityState?: TrackingContinuityState;

  // New detailed lifecycle state.
  poseTrackingState?: PoseTrackingState;

  trackingQuality?: number;
  renderQuality?: number;
  logicQuality?: number;
  reliability?: number;
  modeConfidence?: number;
  roiCoverage?: number;
  bodyVisibilityState?: BodyVisibilityState;
  lowLightDetected?: boolean;
  poseBackend?: PoseBackendKind;
  requestedBackend?: PoseBackendKind;
  activeBackend?: PoseBackendKind;
  fallbackAllowed?: boolean;
  fallbackUsed?: boolean;
  fallbackReason?: string;
  mediapipeAvailable?: boolean;
  compiledWithMediaPipe?: boolean;
  poseModelFound?: boolean;
  poseModelName?: string;
  poseModelPath?: string;
  poseLandmarkerInitStatus?: string;
  mediapipeInitReason?: MediaPipeInitReason;

  // New mode field; bodyMode kept for compatibility.
  poseMode?: BodyMode;
  bodyMode?: BodyMode;

  reacquireSource?: ReacquireSource;
  lowLightActive?: boolean;
  cameraFPS?: number;
  cameraProcessingBacklog?: number;
  cameraAverageProcessingMs?: number;
  poseFPS?: number;
  processingFPS?: number;
  dropRate?: number;
  visibleJointCount?: number;
  mirrored?: boolean;
  orientation?: number;
  debugSessionID?: string;
  fullBodyCoverage?: number;
  upperBodyCoverage?: number;
  handCoverage?: number;
  wristRetention?: number;
  inferredJointRatio?: number;
  diagnostics?: {
    reasonCodes?: string[];
    repBlockedReasons?: string[];
    jointCount?: number;
    viewWidth?: number;
    viewHeight?: number;
    dropCount?: number;
    dropLateCount?: number;
    dropOutOfBuffersCount?: number;
    cameraProcessingBacklog?: number;
    cameraAverageProcessingMs?: number;
    cameraLowLightBoostSupported?: boolean;
    cameraExposureDurationSeconds?: number;
    poseMode?: BodyMode;
    poseTrackingState?: PoseTrackingState;
    modeConfidence?: number;
    visibleJointCount?: number;
    mirrored?: boolean;
    orientation?: number;
    debugSessionID?: string;
  };
};

export type PushlyNativeModuleEvents = Record<string, never>;

export type PushlyCameraViewProps = {
  cameraPosition?: 'front' | 'back';
  isActive?: boolean;
  onPoseFrame?: (event: { nativeEvent: PoseFrame }) => void;
  repTarget?: number;
  showSkeleton?: boolean;
  debugMode?: boolean;
  forceFullFrameProcessing?: boolean;
  forceROIProcessing?: boolean;
  poseBackendMode?: 'vision' | 'mediapipe' | 'mlkit' | 'auto';
  style?: StyleProp<ViewStyle>;
};
