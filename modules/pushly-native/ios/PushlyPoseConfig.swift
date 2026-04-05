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
    let poseModelFileExtension = "task"
    let handModelFileName = "hand_landmarker"
    let handModelFileExtension = "task"

    let minPoseDetectionConfidence: Float = 0.5
    let minPosePresenceConfidence: Float = 0.5
    let minPoseTrackingConfidence: Float = 0.5
    let minHandDetectionConfidence: Float = 0.45
    let minHandPresenceConfidence: Float = 0.45
    let minHandTrackingConfidence: Float = 0.45

    let numPoses = 1
    let numHands = 2
    let enableHandRefinement = true
    let handRefinementBlendAlpha: CGFloat = 0.7
    let handRefinementMinConfidence: Float = 0.28
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
  }

  struct Tracker {
    let measuredConfidenceMin: Float = 0.03
    let highConfidenceMin: Float = 0.44
    let lowConfidenceMin: Float = 0.2
    let emaBaseAlpha: CGFloat = 0.24
    let emaHighConfidenceBoost: CGFloat = 0.24
    let velocityDamping: CGFloat = 0.84
    let measuredFreshness: TimeInterval = 0.12
    let renderInferenceMaxAge: TimeInterval = 0.5
    let logicInferenceMaxAge: TimeInterval = 0.22
    let hardExpiration: TimeInterval = 0.95
    let inferenceConfidenceFloor: Float = 0.08
    let kinematicArmExtensionRatio: CGFloat = 0.92
  }

  struct Quality {
    let notFoundThreshold: Double = 0.2
    let assistedThreshold: Double = 0.44
    let goodThreshold: Double = 0.7
    let pushupLogicMin: Double = 0.52
    let renderMin: Double = 0.26
    let lowLightLumaThreshold: Double = 0.2
    let veryLowLightLumaThreshold: Double = 0.13
    let minUpperBodyRenderableJoints: Int = 4
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
    let minLogicQualityToCount: Double = 0.58
    let minLogicQualityToProgress: Double = 0.44
    let plankLockFrames: Int = 4
    let plankAngleMin: CGFloat = 154
    let descendAngleMax: CGFloat = 122
    let bottomAngleMax: CGFloat = 93
    let ascendAngleMin: CGFloat = 120
    let repCompleteAngleMin: CGFloat = 154
    let minTorsoStability: Double = 0.42
    let minMeasuredEvidence: Double = 0.4
    let shoulderVelocityMinForDescent: CGFloat = 0.0012
    let shoulderVelocityMinForAscent: CGFloat = 0.0008
    let elbowSmoothAlpha: CGFloat = 0.3
    let shoulderSmoothAlpha: CGFloat = 0.26
  }

  struct Pipeline {
    let minEmitInterval: TimeInterval = 0.08
    let maxPoseFps: Double = 30
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

  let mediaPipe = MediaPipe()
  let mode = Mode()
  let tracker = Tracker()
  let quality = Quality()
  let reacquire = Reacquire()
  let camera = Camera()
  let rep = Rep()
  let pipeline = Pipeline()
  let instructions = Instructions()
}
#endif
