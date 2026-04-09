import Foundation

#if os(iOS)
struct PushlyPoseConfig {
  enum PoseBackendPreference: String {
    case mediapipe
    case vision
    case auto
    // Legacy alias kept for compatibility with older JS/debug controls.
    case mlkit
  }

  enum ROIDebugMode: String {
    case adaptive
    case fullFrameOnly
    case roiOnly
  }

  struct MediaPipe {
    let poseModelFileName = "pose_landmarker_lite"
    let preferredPoseModelFileNames = ["pose_landmarker_full", "pose_landmarker_lite"]
    let poseModelFileExtension = "task"
    let handModelFileName = "hand_landmarker"
    let handModelFileExtension = "task"

    let minPoseDetectionConfidence: Float = 0.42
    let minPosePresenceConfidence: Float = 0.35
    let minPoseTrackingConfidence: Float = 0.35
    let minHandDetectionConfidence: Float = 0.45
    let minHandPresenceConfidence: Float = 0.45
    let minHandTrackingConfidence: Float = 0.45

    let numPoses = 1
    let numHands = 2
    let enableHandRefinement = true
    let handRefinementBlendAlpha: CGFloat = 0.7
    let handRefinementMinConfidence: Float = 0.28
    let enablePoseSegmentationPresenceAssist = true
    let poseSegmentationForegroundThreshold: Float = 0.22
    let poseSegmentationAssistCoverageThreshold: Double = 0.018
    let poseSegmentationBottomAssistCoverageThreshold: Double = 0.04
    let poseSegmentationBottomAssistUpperCoverageFloor: Double = 0.27
    let poseSegmentationSmoothingAlpha: Double = 0.34
    let poseSegmentationSampleStride: Int = 5
    let poseSegmentationRelaxedMeasuredMinJoints: Int = 1
  }

  struct Mode {
    let upperBodyMinJointCount = 5
    let fullBodyMinJointCount = 11
    let upperBodyEnterFrames = 2
    let fullBodyEnterFrames = 4
    let fullBodyExitFrames = 5
    let lostEnterFrames = 6

    let upperBodyCoverageEnter: Double = 0.45
    let fullBodyCoverageEnter: Double = 0.64
    let upperBodyCoverageLost: Double = 0.22
    let fullBodyCoverageLost: Double = 0.44
    let pushupFloorLostGraceFrames: Int = 6
    let segmentationBottomAssistLostGraceFrames: Int = 4
  }

  struct Tracker {
    let measuredConfidenceMin: Float = 0.03
    let highConfidenceMin: Float = 0.44
    let lowConfidenceMin: Float = 0.2
    let confidenceHysteresisExit: Float = 0.15
    let confidenceHysteresisEnter: Float = 0.6
    let emaBaseAlpha: CGFloat = 0.24
    let emaHighConfidenceBoost: CGFloat = 0.24
    let velocityDamping: CGFloat = 0.84
    let measuredFreshness: TimeInterval = 0.12
    let renderInferenceMaxAge: TimeInterval = 0.5
    let logicInferenceMaxAge: TimeInterval = 0.22
    let hardExpiration: TimeInterval = 0.95
    let inferenceConfidenceFloor: Float = 0.12
    let kinematicArmExtensionRatio: CGFloat = 0.92
    let kinematicLowerBodyMaxAge: TimeInterval = 0.9
    let kinematicParentConfidenceMin: Float = 0.16
    let missingJointPredictionMaxAge: TimeInterval = 0.42
    let missingJointPredictionMaxExtrapolation: CGFloat = 0.11
    let missingJointPredictionVelocityDampingPerSecond: Double = 9.5
    let missingJointPredictionConfidenceDecayPerSecond: Double = 7.5
    let missingJointPredictionVisibilityDecayPerSecond: Double = 8.4
    // Push-up floor mode: hold occluded joints a bit longer but with tighter spatial drift.
    let pushupMissingJointPredictionMaxAgeScale: Double = 1.35
    let pushupMissingJointPredictionMaxExtrapolationScale: CGFloat = 0.72
    let pushupMissingJointPredictionDecayRateScale: Double = 0.74
    let pushupMissingJointPredictionVelocityDampingRateScale: Double = 1.2
    let missingJointRelockMeasurementAlpha: CGFloat = 0.38
    let torsoFrameSmoothingAlpha: CGFloat = 0.28
    let torsoOffsetMaxAge: TimeInterval = 0.55
    let pushupTorsoOffsetMaxAgeScale: Double = 1.35
    let torsoInferenceConfidenceScale: Float = 0.72
    let pushupTorsoInferencePreserveConfidenceMin: Float = 0.16
    let pushupKinematicLowerBodyMaxAgeScale: Double = 0.72
    let torsoSideEvidenceWeight: Double = 0.55
    let torsoSideLateralMargin: CGFloat = 0.012
    let sideSwapTooCloseBlockSeconds: TimeInterval = 0.65
    let sideSwapReacquireBlockSeconds: TimeInterval = 0.42
    let sideSwapOcclusionBlockSeconds: TimeInterval = 0.28
    let sideSwapOcclusionMinMeasuredJoints: Int = 6
    let sideSwapTorsoSupportMinScore: Double = 0.58
    let sideChainEvidenceWeight: Double = 1.15
    let sideSwapConsistencyFrames: Int = 5
  }

  struct Quality {
    let notFoundThreshold: Double = 0.2
    let assistedThreshold: Double = 0.4
    let goodThreshold: Double = 0.7
    let pushupLogicMin: Double = 0.46
    let renderMin: Double = 0.26
    // Scene brightness gates used by backends/evaluator. veryLowLight is a stricter subset of lowLight.
    let lowLightLumaThreshold: Double = 0.2
    let veryLowLightLumaThreshold: Double = 0.13
    let minUpperBodyRenderableJoints: Int = 4
    let pushupFloorModeEnterFrames: Int = 3
    let pushupFloorModeExitFrames: Int = 6
    let pushupFloorLogicMin: Double = 0.34
  }

  struct Reacquire {
    let detectorCadenceFrames: Int = 3
    let fullFrameRefreshCadenceFrames: Int = 16
    let facePaddingX: CGFloat = 0.45
    let facePaddingY: CGFloat = 1.15
    let upperBodyPaddingX: CGFloat = 0.32
    let upperBodyPaddingY: CGFloat = 0.48
    let maxDetectorInterval: TimeInterval = 0.35
    let enableFaceDetector: Bool = true
    let enableUpperBodyDetector: Bool = true
    let roiPadding: CGFloat = 0.18
    let roiMinSize: CGFloat = 0.08
    let roiTrackingSmoothingAlpha: CGFloat = 0.22
    let roiReacquireSmoothingAlpha: CGFloat = 0.3
    let roiSourceSwitchConsistencyFrames: Int = 3
    let roiSourceLockFrames: Int = 4
    let roiReacquireGraceFrames: Int = 8
  }

  struct Camera {
    let minCaptureFPS: Int32 = 20
    let maxCaptureFPS: Int32 = 30
    let lowLightCaptureFPS: Int32 = 24
    let frameDropRateForThrottle: Double = 0.2
    let thermalThrottleFPS: Int32 = 22
    let recoverFrameDropRate: Double = 0.06
  }

  struct Rep {
    let minLogicQualityToCount: Double = 0.32
    let minLogicQualityToProgress: Double = 0.24
    let minTrackingQualityToCount: Double = 0.34
    let floorMinTrackingQualityToCount: Double = 0.28
    let plankLockFrames: Int = 4
    let plankAngleMin: CGFloat = 146
    let descendAngleMax: CGFloat = 126
    let bottomAngleMax: CGFloat = 100
    let ascendAngleMin: CGFloat = 122
    let repCompleteAngleMin: CGFloat = 150
    let minTorsoStability: Double = 0.24
    let floorMinTorsoStability: Double = 0.22
    let minMeasuredEvidence: Double = 0.14
    let floorMinMeasuredEvidence: Double = 0.12
    let logicGateGraceFrames: Int = 5
    let descentConfirmFrames: Int = 2
    let bottomConfirmFrames: Int = 2
    let ascendingConfirmFrames: Int = 2
    let minRepAngleTravel: CGFloat = 34
    let torsoSmoothAlpha: CGFloat = 0.28
    // Detector coordinates use normalized Y where larger means visually higher in frame.
    // Therefore descent (toward floor) appears as negative Y velocity and ascent as positive.
    let torsoVelocityMinForDescent: CGFloat = 0.00062
    let torsoVelocityMinForAscent: CGFloat = 0.00048
    let minShoulderHipLineQuality: Double = 0.24
    let floorMinShoulderHipLineQuality: Double = 0.2
    let minTorsoDownTravelForBottom: CGFloat = 0.01
    let minTorsoCycleTravel: CGFloat = 0.016
    let minTorsoRecoveryTravel: CGFloat = 0.012
    let maxTorsoTopRecoveryOffset: CGFloat = 0.024
    let shoulderVelocityMinForDescent: CGFloat = 0.0008
    let shoulderVelocityMinForAscent: CGFloat = 0.00055
    let elbowVelocityMinForDescent: CGFloat = 0.42
    let elbowVelocityMinForAscent: CGFloat = 0.42
    let floorElbowVelocityMinForDescent: CGFloat = 0.3
    let floorElbowVelocityMinForAscent: CGFloat = 0.3
    let minShoulderDownTravelForBottom: CGFloat = 0.009
    let minShoulderCycleTravel: CGFloat = 0.013
    let minShoulderRecoveryTravel: CGFloat = 0.01
    let bilateralElbowMaxAngleDelta: CGFloat = 42
    let bottomOcclusionGraceFrames: Int = 8
    let repRearmConfirmFrames: Int = 2
    // Startup bridge for the very first rep: allow descent before full plank lock
    // once a minimal amount of stable top evidence was observed.
    let startupDescendBridgeMinTopFrames: Int = 2
    let floorStateNoseShoulderDeltaMax: Double = 0.12
    let floorStateShoulderHipDeltaMax: Double = 0.2
    let elbowSmoothAlpha: CGFloat = 0.34
    let shoulderSmoothAlpha: CGFloat = 0.3
  }

  struct Pipeline {
    let minEmitInterval: TimeInterval = 0.08
    let maxPoseFps: Double = 30
    let logicMinJointCount: Int = 3
    let renderPersistenceMinJointCount: Int = 3
    let pushupBottomRenderMinJointCount: Int = 4
    let pushupBottomRenderCoreMinJointCount: Int = 5
    let enablePreprocessingHint: Bool = false
    let debugEnabledByDefault: Bool = false
    let backendPreference: PoseBackendPreference = .auto
    let roiDebugMode: ROIDebugMode = .adaptive
    let enableAutoBackendFallback: Bool = true
    let backendFailureWindow: Int = 10
    let backendSwitchThreshold: Int = 6
    let diagnosticsVerbose: Bool = false

    let structuredLoggingEnabled: Bool = true
    let verboseFrameLoggingEnabled: Bool = false
    let verboseFrameSampleInterval: Int = 12
    let debugOverlayEnabled: Bool = false
    let sessionExportEnabled: Bool = true
    let signpostsEnabled: Bool = true
    let cameraTelemetryEnabled: Bool = true
    let backendTelemetryEnabled: Bool = true
    let maxDiagnosticEventBuffer: Int = 320
    let maxDiagnosticFrameBuffer: Int = 180
  }

  struct Instructions {
    // Some sessions may require full body framing; default stays upper-body safe.
    let requiresFullBodyForCurrentSession = false
  }

  struct Smoothing {
    struct OneEuroBand {
      let minCutoff: CGFloat
      let beta: CGFloat
    }

    // Logic smoothing (TemporalJointTracker)
    let logicCore = OneEuroBand(minCutoff: 0.008, beta: 4.2)
    let logicMid = OneEuroBand(minCutoff: 0.011, beta: 4.0)
    let logicExtremity = OneEuroBand(minCutoff: 0.013, beta: 3.7)
    let logicDCutoff: CGFloat = 1.0
    // Slight look-ahead to compensate perceived latency without increasing persistence.
    let logicPredictionLeadSeconds: TimeInterval = 0.016
    let logicLowLightMinCutoffMultiplier: CGFloat = 1.04
    let logicLowConfidenceMinCutoffMultiplier: CGFloat = 1.06
    let logicInferredMinCutoffMultiplier: CGFloat = 1.08

    // Render smoothing/persistence (SkeletonRenderer + camera render gate)
    // Main visible-lag knobs (renderer responsiveness vs persistence).
    let renderLineEndpointAlpha: CGFloat = 0.82
    let renderPersistenceGraceSeconds: TimeInterval = 0.18
    let pushupBottomRenderGraceSeconds: TimeInterval = 0.46
    let segmentationBottomAssistRenderGraceSeconds: TimeInterval = 0.16
    let pushupBottomTemporalResetGraceSeconds: TimeInterval = 0.55
  }

  let mediaPipe = MediaPipe()
  let mode = Mode()
  let tracker = Tracker()
  let quality = Quality()
  let reacquire = Reacquire()
  let camera = Camera()
  let rep = Rep()
  let pipeline = Pipeline()
  let instructions = Instructions()
  let smoothing = Smoothing()
}
#endif
