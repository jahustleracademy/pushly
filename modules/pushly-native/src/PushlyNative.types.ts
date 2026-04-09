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
  smoothedElbowAngle?: number;
  repMinElbowAngle?: number;
  smoothedTorsoY?: number;
  smoothedShoulderY?: number;
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
  bottomFrames?: number;
  ascendingFrames?: number;
  bottomReached?: boolean;
  dominantEvidence?: number;
  measuredEvidence?: number;
  structuralEvidence?: number;
  upperBodyEvidence?: number;
  blockedReasons?: string[];
  canProgress?: boolean;
  logicBlockedFrames?: number;
  startupReady?: boolean;
  startupTopEvidence?: number;
  startupDescendBridgeUsed?: boolean;
  startBlockedReason?: string;
  repRearmPending?: boolean;
  topRecoveryFrames?: number;
  cycleCoreReady?: boolean;
  strictCycleReady?: boolean;
  floorFallbackCycleReady?: boolean;
  motionTravelGate?: boolean;
  topRecoveryGate?: boolean;
  torsoSupportReady?: boolean;
  shoulderSupportReady?: boolean;
  countGatePassed?: boolean;
  countGateBlocked?: boolean;
  countGateBlockReason?: string;
  stateTransitionEvent?: string;
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
  repBlockedReasons?: string[];
  trackingQuality?: number;
  logicQuality?: number;
  upperBodyCoverage?: number;
  wristRetention?: number;
  smoothedElbowAngle?: number;
  repMinElbowAngle?: number;
  smoothedTorsoY?: number;
  smoothedShoulderY?: number;
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
  bottomFrames?: number;
  ascendingFrames?: number;
  canProgress?: boolean;
  logicBlockedFrames?: number;
  startupReady?: boolean;
  startupTopEvidence?: number;
  startupDescendBridgeUsed?: boolean;
  startBlockedReason?: string;
  repRearmPending?: boolean;
  topRecoveryFrames?: number;
  cycleCoreReady?: boolean;
  strictCycleReady?: boolean;
  floorFallbackCycleReady?: boolean;
  motionTravelGate?: boolean;
  topRecoveryGate?: boolean;
  torsoSupportReady?: boolean;
  shoulderSupportReady?: boolean;
  countGatePassed?: boolean;
  countGateBlocked?: boolean;
  countGateBlockReason?: string;
  stateTransitionEvent?: string;
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
