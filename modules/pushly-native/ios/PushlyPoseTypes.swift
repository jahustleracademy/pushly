import Foundation

#if os(iOS)
import CoreGraphics
import Vision

enum PushlyJointName: String, CaseIterable {
  case nose
  case head
  case leftShoulder
  case rightShoulder
  case leftElbow
  case rightElbow
  case leftWrist
  case rightWrist
  case leftHand
  case rightHand
  case leftHip
  case rightHip
  case leftKnee
  case rightKnee
  case leftAnkle
  case rightAnkle
  case leftFoot
  case rightFoot

  var visionJoint: VNHumanBodyPoseObservation.JointName? {
    switch self {
    case .nose, .head: return .nose
    case .leftShoulder: return .leftShoulder
    case .rightShoulder: return .rightShoulder
    case .leftElbow: return .leftElbow
    case .rightElbow: return .rightElbow
    case .leftWrist, .leftHand: return .leftWrist
    case .rightWrist, .rightHand: return .rightWrist
    case .leftHip: return .leftHip
    case .rightHip: return .rightHip
    case .leftKnee: return .leftKnee
    case .rightKnee: return .rightKnee
    case .leftAnkle, .leftFoot: return .leftAnkle
    case .rightAnkle, .rightFoot: return .rightAnkle
    }
  }

  var isUpperBody: Bool {
    switch self {
    case .nose, .head,
         .leftShoulder, .rightShoulder,
         .leftElbow, .rightElbow,
         .leftWrist, .rightWrist,
         .leftHand, .rightHand,
         .leftHip, .rightHip:
      return true
    case .leftKnee, .rightKnee,
         .leftAnkle, .rightAnkle,
         .leftFoot, .rightFoot:
      return false
    }
  }

  var isHandAnchor: Bool {
    self == .leftHand || self == .rightHand
  }
}

enum PoseBackendKind: String {
  case mediapipe
  case visionFallback
  // Backward-compatible legacy labels.
  case vision
  case mlkit
}

enum ReacquireSource: String {
  case none
  case face
  case upperBody
  case fullFrame
  case previousTrack

  // Legacy values kept for bridge compatibility.
  case upperBodyRect
  case fullFrameRefresh
}

enum BodyTrackingMode: String {
  case upperBody
  case fullBody
  case unknown
}

enum PushlyJointSourceType: String {
  case measured
  case lowConfidenceMeasured
  case inferred
  case predicted
  case missing
}

enum BodyVisibilityState: String {
  case notFound = "body_not_found"
  case partial = "body_partial"
  case assisted = "body_assisted"
  case good = "body_good"
}

enum BodyState: String {
  case trackingFullBody = "trackingFullBody"
  case trackingUpperBody = "trackingUpperBody"
  case reacquiring
  case lost

  var allowsRendering: Bool {
    self != .lost
  }

  var toContinuityState: TrackingContinuityState {
    switch self {
    case .trackingUpperBody, .trackingFullBody:
      return .tracking
    case .reacquiring:
      return .reacquire
    case .lost:
      return .lost
    }
  }
}

enum TrackingContinuityState: String {
  case tracking
  case reacquire
  case lost
}

struct PoseWorldPoint {
  let x: Double
  let y: Double
  let z: Double
}

struct PoseJointMeasurement {
  let name: PushlyJointName
  let point: CGPoint
  let worldPoint: PoseWorldPoint?
  let confidence: Float
  let visibility: Float
  let presence: Float
  let sourceType: PushlyJointSourceType
  let inFrame: Bool
  let backend: PoseBackendKind
  let measuredAt: TimeInterval

  init(
    name: PushlyJointName,
    point: CGPoint,
    worldPoint: PoseWorldPoint? = nil,
    confidence: Float,
    visibility: Float = 1,
    presence: Float = 1,
    sourceType: PushlyJointSourceType = .measured,
    inFrame: Bool = true,
    backend: PoseBackendKind,
    measuredAt: TimeInterval = CACurrentMediaTime()
  ) {
    self.name = name
    self.point = point
    self.worldPoint = worldPoint
    self.confidence = confidence
    self.visibility = visibility
    self.presence = presence
    self.sourceType = sourceType
    self.inFrame = inFrame
    self.backend = backend
    self.measuredAt = measuredAt
  }
}

struct PoseVisibilityCoverage {
  let upperBodyCoverage: Double
  let fullBodyCoverage: Double
  let handCoverage: Double

  static let empty = PoseVisibilityCoverage(upperBodyCoverage: 0, fullBodyCoverage: 0, handCoverage: 0)
}

struct PoseBackendDiagnostics {
  let rawObservationCount: Int
  let trackedJointCount: Int
  let averageJointConfidence: Double
  let roiUsed: CGRect?
  let durationMs: Double
  let modeConfidence: Double
  let reliability: Double
  let handRefinedJointCount: Int
  let segmentationAssistActive: Bool = false
  let segmentationBottomAssistActive: Bool = false
  let segmentationPresenceCoverage: Double = 0
  let tooCloseFallbackActive: Bool = false
  let tooCloseInferredHipCount: Int = 0
}

struct ReacquireDiagnostics {
  let source: ReacquireSource
  let roi: CGRect?
  let relockSuccessCount: Int
  let relockFailureCount: Int
}

struct PoseProcessingResult {
  let measured: [PushlyJointName: PoseJointMeasurement]
  let avgConfidence: Double
  let brightnessLuma: Double
  let lowLightDetected: Bool
  let observationExists: Bool
  let detectedJointCount: Int
  let backend: PoseBackendKind
  let mode: BodyTrackingMode
  let modeConfidence: Double
  let coverage: PoseVisibilityCoverage
  let backendDiagnostics: PoseBackendDiagnostics
  let reacquireDiagnostics: ReacquireDiagnostics
}

struct PoseBackendDebugState {
  let requestedBackend: PoseBackendKind
  let activeBackend: PoseBackendKind
  let fallbackAllowed: Bool
  let fallbackUsed: Bool
  let fallbackReason: String?
  let mediapipeAvailable: Bool
  let mediaPipeDiagnostics: MediaPipeAvailabilityDiagnostics
}

struct MediaPipeAvailabilityDiagnostics {
  let compiledWithMediaPipe: Bool
  let poseModelFound: Bool
  let poseModelName: String?
  let poseModelPath: String?
  let poseLandmarkerInitStatus: String
  let mediapipeInitReason: String?
}

struct TrackedJoint {
  let name: PushlyJointName
  var rawPosition: CGPoint
  var smoothedPosition: CGPoint
  var velocity: CGVector
  var rawConfidence: Float
  var renderConfidence: Float
  var logicConfidence: Float
  var visibility: Float
  var presence: Float
  var inFrame: Bool
  var sourceType: PushlyJointSourceType
  var timestamp: TimeInterval

  var isRenderable: Bool {
    sourceType != .missing && renderConfidence > 0.01
  }

  var isLogicUsable: Bool {
    logicConfidence > 0.18 && (sourceType == .measured || sourceType == .lowConfidenceMeasured || sourceType == .inferred)
  }
}

struct TrackingQuality {
  let trackingQuality: Double
  let renderQuality: Double
  let logicQuality: Double
  let pushupFloorModeActive: Bool
  let bodyVisibilityState: BodyVisibilityState
  let trackingState: TrackingContinuityState
  let poseTrackingState: BodyState
  let poseMode: BodyTrackingMode
  let reasonCodes: [String]
  let spreadScore: Double
  let smoothedSpread: Double
  let visibleJointCount: Int
  let upperBodyRenderableCount: Int
  let reliability: Double
  let roiCoverage: Double
  let fullBodyCoverage: Double
  let upperBodyCoverage: Double
  let handCoverage: Double
  let wristRetention: Double
  let inferredJointRatio: Double
  let modeConfidence: Double
}

struct RepDetectionOutput {
  let state: PushupState
  let repCount: Int
  let formEvidenceScore: Double
  let blockedReasons: [String]
  let repDebug: PushupRepDebug?

  init(
    state: PushupState,
    repCount: Int,
    formEvidenceScore: Double,
    blockedReasons: [String],
    repDebug: PushupRepDebug? = nil
  ) {
    self.state = state
    self.repCount = repCount
    self.formEvidenceScore = formEvidenceScore
    self.blockedReasons = blockedReasons
    self.repDebug = repDebug
  }
}

struct PushupRepDebug {
  let frameIndex: Int
  let timestampSeconds: Double
  let currentRepState: String
  let repStateMachineState: String
  let repStateTransitionEvent: String?
  let smoothedElbowAngle: Double
  let repMinElbowAngle: Double
  let rawTorsoY: Double
  let rawShoulderY: Double
  let smoothedTorsoY: Double
  let smoothedShoulderY: Double
  let rawTorsoVelocity: Double
  let rawShoulderVelocity: Double
  let smoothedTorsoVelocity: Double
  let smoothedShoulderVelocity: Double
  let topReferenceTorsoY: Double
  let topReferenceShoulderY: Double
  let shoulderVelocity: Double
  let torsoVelocity: Double
  let descendingSignal: Bool
  let ascendingSignal: Bool
  let shoulderDownTravel: Double
  let shoulderRecoveryToTop: Double
  let torsoDownTravel: Double
  let torsoRecoveryToTop: Double
  let descendingFrames: Int
  let bottomCandidateFrames: Int
  let bottomConfirmedFrames: Int
  let bottomFrames: Int
  let ascendingFrames: Int
  let ascentFrames: Int
  let bottomReached: Bool
  let bottomConfirmedLatched: Bool
  let bottomNearMiss: Bool
  let minDescendingFramesRequired: Int
  let minBottomFramesRequired: Int
  let minAscendingFramesRequired: Int
  let minTopRecoveryFramesRequired: Int
  let dominantEvidence: Double
  let measuredEvidence: Double
  let structuralEvidence: Double
  let upperBodyEvidence: Double
  let weakestLandmark: String?
  let weakestLandmarkConfidence: Double
  let missingLandmarks: [String]
  let landmarkQuality: [String: [String: Any]]
  let blockedReasons: [String]
  let canProgress: Bool
  let logicBlockedFrames: Int
  let startupReady: Bool
  let startupTopEvidence: Int
  let startupDescendBridgeUsed: Bool
  let startBlockedReason: String?
  let repRearmPending: Bool
  let topRecoveryFrames: Int
  let commitPathActive: Bool
  let commitCancelledReason: String?
  let idleResetReason: String?
  let pendingCommitReason: String?
  let commitBlockedBy: String?
  let topReady: Bool
  let descendingStarted: Bool
  let bottomLatched: Bool
  let ascendingStarted: Bool
  let topRecovered: Bool
  let repCommitted: Bool
  let rearmReady: Bool
  let resetReason: String?
  let timeoutOrAbortReason: String?
  let firstBlockingConditionAfterBottom: String?
  // Core stabilization/debug group for post-bottom recovery.
  // bodyFound + (tracking/logic) indicate logic visibility readiness.
  // rearm* describes readiness to start next rep after a counted rep.
  // bottom* and trackingLoss* explain tolerated bottom occlusion windows.
  let lostTrackingAtBottom: Bool
  let trackingLossDuringCommitPath: Int
  let trackingLossGraceFramesRemaining: Int
  let bottomHoldActive: Bool
  let bottomReacquireState: String?
  let bottomSupportAnchors: [String]
  let bottomBlockedReason: String?
  let didEnterAscending: Bool
  let didEnterTopRecovery: Bool
  let rearmBlockedReason: String?
  let framesUntilRearm: Int
  let rearmConfirmProgress: Double
  let rearmMissingCondition: String?
  let whyRepDidNotCount: String?
  let firstFinalBlocker: String?
  let lastFailedGate: String?
  let lastSuccessfulGate: String?
  let bodyFound: Bool
  let trackingQualityPass: Bool
  let logicQualityPass: Bool
  let bottomGate: Bool
  let ascentGate: Bool
  let rearmGate: Bool
  let cycleCoreReady: Bool
  let strictCycleReady: Bool
  let floorFallbackCycleReady: Bool
  let motionTravelGate: Bool
  let topRecoveryGate: Bool
  let countCommitReady: Bool
  let torsoSupportReady: Bool
  let shoulderSupportReady: Bool
  let countGatePassed: Bool
  let countGateBlocked: Bool
  let countGateBlockReason: String?
  let stateTransitionEvent: String?
  let repsAttemptedEstimate: Int
  let repsCommitted: Int
  let repsBlockedByBottom: Int
  let repsBlockedByTopRecovery: Int
  let repsBlockedByRearm: Int
  let repsBlockedByTrackingLoss: Int
  let repsBlockedByTravel: Int
  let repsBlockedByQuality: Int
  let bottomConfirmedCount: Int
  let ascendingEnteredCount: Int
  let topRecoveryEnteredCount: Int
  let repCommitAttemptCount: Int
  let repCommitSuccessCount: Int
  let repCommitBlockedCount: Int

  func toDictionary() -> [String: Any] {
    [
      "frameIndex": frameIndex,
      "timestampSeconds": timestampSeconds,
      "currentRepState": currentRepState,
      "repStateMachineState": repStateMachineState,
      "repStateTransitionEvent": repStateTransitionEvent as Any,
      "smoothedElbowAngle": smoothedElbowAngle,
      "repMinElbowAngle": repMinElbowAngle,
      "rawTorsoY": rawTorsoY,
      "rawShoulderY": rawShoulderY,
      "smoothedTorsoY": smoothedTorsoY,
      "smoothedShoulderY": smoothedShoulderY,
      "rawTorsoVelocity": rawTorsoVelocity,
      "rawShoulderVelocity": rawShoulderVelocity,
      "smoothedTorsoVelocity": smoothedTorsoVelocity,
      "smoothedShoulderVelocity": smoothedShoulderVelocity,
      "topReferenceTorsoY": topReferenceTorsoY,
      "topReferenceShoulderY": topReferenceShoulderY,
      "shoulderVelocity": shoulderVelocity,
      "torsoVelocity": torsoVelocity,
      "descendingSignal": descendingSignal,
      "ascendingSignal": ascendingSignal,
      "shoulderDownTravel": shoulderDownTravel,
      "shoulderRecoveryToTop": shoulderRecoveryToTop,
      "torsoDownTravel": torsoDownTravel,
      "torsoRecoveryToTop": torsoRecoveryToTop,
      "descendingFrames": descendingFrames,
      "bottomCandidateFrames": bottomCandidateFrames,
      "bottomConfirmedFrames": bottomConfirmedFrames,
      "bottomFrames": bottomFrames,
      "ascendingFrames": ascendingFrames,
      "ascentFrames": ascentFrames,
      "bottomReached": bottomReached,
      "bottomConfirmedLatched": bottomConfirmedLatched,
      "bottomNearMiss": bottomNearMiss,
      "minDescendingFramesRequired": minDescendingFramesRequired,
      "minBottomFramesRequired": minBottomFramesRequired,
      "minAscendingFramesRequired": minAscendingFramesRequired,
      "minTopRecoveryFramesRequired": minTopRecoveryFramesRequired,
      "dominantEvidence": dominantEvidence,
      "measuredEvidence": measuredEvidence,
      "structuralEvidence": structuralEvidence,
      "upperBodyEvidence": upperBodyEvidence,
      "weakestLandmark": weakestLandmark as Any,
      "weakestLandmarkConfidence": weakestLandmarkConfidence,
      "missingLandmarks": missingLandmarks,
      "landmarkQuality": landmarkQuality,
      "blockedReasons": blockedReasons,
      "canProgress": canProgress,
      "logicBlockedFrames": logicBlockedFrames,
      "startupReady": startupReady,
      "startupTopEvidence": startupTopEvidence,
      "startupDescendBridgeUsed": startupDescendBridgeUsed,
      "startBlockedReason": startBlockedReason as Any,
      "repRearmPending": repRearmPending,
      "topRecoveryFrames": topRecoveryFrames,
      "commitPathActive": commitPathActive,
      "commitCancelledReason": commitCancelledReason as Any,
      "idleResetReason": idleResetReason as Any,
      "pendingCommitReason": pendingCommitReason as Any,
      "commitBlockedBy": commitBlockedBy as Any,
      "topReady": topReady,
      "descendingStarted": descendingStarted,
      "bottomLatched": bottomLatched,
      "ascendingStarted": ascendingStarted,
      "topRecovered": topRecovered,
      "repCommitted": repCommitted,
      "rearmReady": rearmReady,
      "resetReason": resetReason as Any,
      "timeoutOrAbortReason": timeoutOrAbortReason as Any,
      "firstBlockingConditionAfterBottom": firstBlockingConditionAfterBottom as Any,
      "lostTrackingAtBottom": lostTrackingAtBottom,
      "trackingLossDuringCommitPath": trackingLossDuringCommitPath,
      "trackingLossGraceFramesRemaining": trackingLossGraceFramesRemaining,
      "bottomHoldActive": bottomHoldActive,
      "bottomReacquireState": bottomReacquireState as Any,
      "bottomSupportAnchors": bottomSupportAnchors,
      "bottomBlockedReason": bottomBlockedReason as Any,
      "didEnterAscending": didEnterAscending,
      "didEnterTopRecovery": didEnterTopRecovery,
      "rearmBlockedReason": rearmBlockedReason as Any,
      "framesUntilRearm": framesUntilRearm,
      "rearmConfirmProgress": rearmConfirmProgress,
      "rearmMissingCondition": rearmMissingCondition as Any,
      "whyRepDidNotCount": whyRepDidNotCount as Any,
      "firstFinalBlocker": firstFinalBlocker as Any,
      "lastFailedGate": lastFailedGate as Any,
      "lastSuccessfulGate": lastSuccessfulGate as Any,
      "bodyFound": bodyFound,
      "trackingQualityPass": trackingQualityPass,
      "logicQualityPass": logicQualityPass,
      "bottomGate": bottomGate,
      "ascentGate": ascentGate,
      "rearmGate": rearmGate,
      "cycleCoreReady": cycleCoreReady,
      "strictCycleReady": strictCycleReady,
      "floorFallbackCycleReady": floorFallbackCycleReady,
      "motionTravelGate": motionTravelGate,
      "topRecoveryGate": topRecoveryGate,
      "countCommitReady": countCommitReady,
      "torsoSupportReady": torsoSupportReady,
      "shoulderSupportReady": shoulderSupportReady,
      "countGatePassed": countGatePassed,
      "countGateBlocked": countGateBlocked,
      "countGateBlockReason": countGateBlockReason as Any,
      "stateTransitionEvent": stateTransitionEvent as Any,
      "repsAttemptedEstimate": repsAttemptedEstimate,
      "repsCommitted": repsCommitted,
      "repsBlockedByBottom": repsBlockedByBottom,
      "repsBlockedByTopRecovery": repsBlockedByTopRecovery,
      "repsBlockedByRearm": repsBlockedByRearm,
      "repsBlockedByTrackingLoss": repsBlockedByTrackingLoss,
      "repsBlockedByTravel": repsBlockedByTravel,
      "repsBlockedByQuality": repsBlockedByQuality,
      "bottomConfirmedCount": bottomConfirmedCount,
      "ascendingEnteredCount": ascendingEnteredCount,
      "topRecoveryEnteredCount": topRecoveryEnteredCount,
      "repCommitAttemptCount": repCommitAttemptCount,
      "repCommitSuccessCount": repCommitSuccessCount,
      "repCommitBlockedCount": repCommitBlockedCount
    ]
  }
}

enum PushupState: String {
  case idle
  case bodyFound = "body_found"
  case plankLocked = "plank_locked"
  case descending
  case bottomReached = "bottom_reached"
  case ascending
  case repCounted = "rep_counted"
  case trackingAssisted = "tracking_assisted"
  case lostTracking = "lost_tracking"
}

struct ReacquireObservation {
  let source: ReacquireSource
  let roi: CGRect
}

struct ROIHintPayload {
  let roi: CGRect?
  let source: ReacquireSource
}

enum PoseCoverageCalculator {
  private static let upperBodyJoints: [PushlyJointName] = [
    .nose,
    .leftShoulder, .rightShoulder,
    .leftElbow, .rightElbow,
    .leftWrist, .rightWrist,
    .leftHip, .rightHip
  ]

  private static let fullBodyJoints: [PushlyJointName] = [
    .nose,
    .leftShoulder, .rightShoulder,
    .leftElbow, .rightElbow,
    .leftWrist, .rightWrist,
    .leftHip, .rightHip,
    .leftKnee, .rightKnee,
    .leftAnkle, .rightAnkle,
    .leftFoot, .rightFoot
  ]

  private static let handJoints: [PushlyJointName] = [.leftWrist, .rightWrist, .leftHand, .rightHand]

  static func coverage(measured: [PushlyJointName: PoseJointMeasurement], minConfidence: Float = 0.12) -> PoseVisibilityCoverage {
    let upperVisible = upperBodyJoints.filter { joint in
      guard let item = measured[joint], item.inFrame else { return false }
      return item.confidence >= minConfidence
    }.count
    let fullVisible = fullBodyJoints.filter { joint in
      guard let item = measured[joint], item.inFrame else { return false }
      return item.confidence >= minConfidence
    }.count
    let handVisible = handJoints.filter { joint in
      guard let item = measured[joint], item.inFrame else { return false }
      return item.confidence >= minConfidence
    }.count

    return PoseVisibilityCoverage(
      upperBodyCoverage: Double(upperVisible) / Double(upperBodyJoints.count),
      fullBodyCoverage: Double(fullVisible) / Double(fullBodyJoints.count),
      handCoverage: Double(handVisible) / Double(handJoints.count)
    )
  }

  static func coverage(tracked: [PushlyJointName: TrackedJoint]) -> PoseVisibilityCoverage {
    let upperVisible = upperBodyJoints.filter { tracked[$0]?.isRenderable == true }.count
    let fullVisible = fullBodyJoints.filter { tracked[$0]?.isRenderable == true }.count
    let handVisible = handJoints.filter { tracked[$0]?.isRenderable == true }.count

    return PoseVisibilityCoverage(
      upperBodyCoverage: Double(upperVisible) / Double(upperBodyJoints.count),
      fullBodyCoverage: Double(fullVisible) / Double(fullBodyJoints.count),
      handCoverage: Double(handVisible) / Double(handJoints.count)
    )
  }
}

final class TrackContinuityManager {
  private let config: PushlyPoseConfig

  private(set) var state: TrackingContinuityState = .lost
  private(set) var poseState: BodyState = .lost
  private(set) var lastStableROI: CGRect?
  private(set) var roiCoverage: Double = 0
  private(set) var bodyMode: BodyTrackingMode = .unknown
  private(set) var modeConfidence: Double = 0
  private(set) var coverage: PoseVisibilityCoverage = .empty
  private(set) var pushupFloorModeActive = false

  private(set) var lastReacquireSource: ReacquireSource = .none
  private(set) var relockSuccessCount = 0
  private(set) var relockFailureCount = 0

  private var upperStableFrames = 0
  private var fullStableFrames = 0
  private var fullMissingFrames = 0
  private var missingFrames = 0
  private var floorModeStableFrames = 0
  private var floorModeMissingFrames = 0

  private var relockStartedAt: TimeInterval?
  private(set) var lastRelockDuration: TimeInterval = 0
  private var smoothedHintROI: CGRect?
  private var lockedHintSource: ReacquireSource = .none
  private var lockedHintSourceFramesLeft = 0
  private var pendingHintSource: ReacquireSource = .none
  private var pendingHintSourceFrames = 0
  private var reacquireWithoutObservationFrames = 0

  init(config: PushlyPoseConfig) {
    self.config = config
  }

  func update(
    measured: [PushlyJointName: PoseJointMeasurement],
    modeHint: BodyTrackingMode?,
    modeHintConfidence: Double?,
    coverage candidateCoverage: PoseVisibilityCoverage?,
    segmentationBottomAssistActive: Bool,
    now: TimeInterval,
    reacquire: ReacquireObservation?
  ) {
    coverage = candidateCoverage ?? PoseCoverageCalculator.coverage(measured: measured)
    updatePushupFloorMode(measured: measured)

    let upperCount = measured.keys.filter(\.isUpperBody).count
    let fullCount = measured.count

    let hasBothKnees = measured[.leftKnee] != nil && measured[.rightKnee] != nil
    let hasBothAnkles = measured[.leftAnkle] != nil && measured[.rightAnkle] != nil

    let upperBodyCoreVisible = hasUpperBodyCore(measured: measured)
    let upperCandidate = (
      upperCount >= config.mode.upperBodyMinJointCount
      && coverage.upperBodyCoverage >= config.mode.upperBodyCoverageEnter
    ) || (
      upperBodyCoreVisible
      && coverage.upperBodyCoverage >= config.mode.upperBodyCoverageLost
    )

    let fullCandidate = upperCandidate
      && fullCount >= config.mode.fullBodyMinJointCount
      && hasBothKnees
      && hasBothAnkles
      && coverage.fullBodyCoverage >= config.mode.fullBodyCoverageEnter

    if upperCandidate {
      missingFrames = 0
      upperStableFrames += 1

      if fullCandidate {
        fullStableFrames += 1
        fullMissingFrames = 0
      } else {
        fullStableFrames = 0
        if bodyMode == .fullBody {
          fullMissingFrames += 1
        }
      }

      let resolvedMode: BodyTrackingMode
      if fullCandidate, fullStableFrames >= config.mode.fullBodyEnterFrames {
        resolvedMode = .fullBody
      } else if bodyMode == .fullBody, fullMissingFrames < config.mode.fullBodyExitFrames {
        resolvedMode = .fullBody
      } else if upperStableFrames >= config.mode.upperBodyEnterFrames {
        resolvedMode = .upperBody
      } else {
        resolvedMode = .unknown
      }

      bodyMode = modeHint ?? resolvedMode

      switch bodyMode {
      case .fullBody:
        poseState = resolvedMode == .unknown ? .reacquiring : .trackingFullBody
      case .upperBody:
        poseState = resolvedMode == .unknown ? .reacquiring : .trackingUpperBody
      case .unknown:
        poseState = .reacquiring
      }

      updateRelockState(now: now)

      if let roi = computeROI(measured: measured) {
        let clamped = PoseCoordinateConverter.clampNormalizedROI(
          paddedROI(roi),
          minSize: config.reacquire.roiMinSize
        )
        let smoothedStableROI = smoothROI(
          current: lastStableROI,
          target: clamped,
          alpha: config.reacquire.roiTrackingSmoothingAlpha
        )
        lastStableROI = smoothedStableROI
        smoothedHintROI = smoothROI(
          current: smoothedHintROI,
          target: smoothedStableROI,
          alpha: config.reacquire.roiTrackingSmoothingAlpha
        )
        roiCoverage = Double(smoothedStableROI.width * smoothedStableROI.height)
      }

      state = poseState.toContinuityState
    } else {
      upperStableFrames = 0
      fullStableFrames = 0
      fullMissingFrames = 0
      missingFrames += 1

      let lostThreshold = config.mode.lostEnterFrames
        + (pushupFloorModeActive ? config.mode.pushupFloorLostGraceFrames : 0)
        + (segmentationBottomAssistActive ? config.mode.segmentationBottomAssistLostGraceFrames : 0)
      if missingFrames >= lostThreshold {
        poseState = .lost
        state = .lost
        updateRelockState(now: now)
      } else {
        poseState = .reacquiring
        state = .reacquire
        updateRelockState(now: now)
      }

      if coverage.upperBodyCoverage <= config.mode.upperBodyCoverageLost && !segmentationBottomAssistActive {
        bodyMode = .unknown
      }
    }

    if let modeHintConfidence {
      modeConfidence = max(0, min(1, modeHintConfidence))
    } else {
      let heuristic = bodyMode == .fullBody ? coverage.fullBodyCoverage : coverage.upperBodyCoverage
      modeConfidence = max(0, min(1, heuristic))
    }

    if let reacquire {
      lastReacquireSource = normalizedReacquireSource(reacquire.source)
    }
  }

  func nextROIHint(frameIndex: Int, roiDebugMode: PushlyPoseConfig.ROIDebugMode, latestReacquire: ReacquireObservation?) -> ROIHintPayload {
    if roiDebugMode == .fullFrameOnly {
      lastReacquireSource = .fullFrame
      return ROIHintPayload(roi: nil, source: .fullFrame)
    }

    if poseState == .reacquiring || poseState == .lost {
      if let reacquire = latestReacquire {
        reacquireWithoutObservationFrames = 0
        let roi = PoseCoordinateConverter.clampNormalizedROI(
          reacquire.roi,
          minSize: config.reacquire.roiMinSize
        )
        let source = resolveHintSource(proposed: normalizedReacquireSource(reacquire.source))
        lastReacquireSource = source
        let smoothedROI = smoothROI(
          current: smoothedHintROI,
          target: roi,
          alpha: config.reacquire.roiReacquireSmoothingAlpha
        )
        smoothedHintROI = smoothedROI
        let roiToUse = roiDebugMode == .roiOnly || roiDebugMode == .adaptive ? smoothedROI : nil
        return ROIHintPayload(roi: roiToUse, source: source)
      }

      reacquireWithoutObservationFrames += 1
      if reacquireWithoutObservationFrames <= config.reacquire.roiReacquireGraceFrames,
         let stickyROI = smoothedHintROI ?? lastStableROI {
        let paddedStickyROI = PoseCoordinateConverter.clampNormalizedROI(
          paddedROI(stickyROI),
          minSize: config.reacquire.roiMinSize
        )
        let smoothedStickyROI = smoothROI(
          current: smoothedHintROI,
          target: paddedStickyROI,
          alpha: config.reacquire.roiTrackingSmoothingAlpha
        )
        smoothedHintROI = smoothedStickyROI
        lastReacquireSource = .previousTrack
        return ROIHintPayload(roi: smoothedStickyROI, source: .previousTrack)
      }

      lastReacquireSource = .fullFrame
      return ROIHintPayload(roi: nil, source: .fullFrame)
    }

    reacquireWithoutObservationFrames = 0
    if let lastStableROI {
      let roi = PoseCoordinateConverter.clampNormalizedROI(
        paddedROI(lastStableROI),
        minSize: config.reacquire.roiMinSize
      )
      let smoothedROI = smoothROI(
        current: smoothedHintROI,
        target: roi,
        alpha: config.reacquire.roiTrackingSmoothingAlpha
      )
      smoothedHintROI = smoothedROI
      return ROIHintPayload(roi: roiDebugMode == .fullFrameOnly ? nil : smoothedROI, source: .previousTrack)
    }

    return ROIHintPayload(roi: nil, source: .none)
  }

  func reset() {
    state = .lost
    poseState = .lost
    upperStableFrames = 0
    fullStableFrames = 0
    fullMissingFrames = 0
    missingFrames = 0
    roiCoverage = 0
    lastStableROI = nil
    relockStartedAt = nil
    lastRelockDuration = 0
    lastReacquireSource = .none
    smoothedHintROI = nil
    lockedHintSource = .none
    lockedHintSourceFramesLeft = 0
    pendingHintSource = .none
    pendingHintSourceFrames = 0
    reacquireWithoutObservationFrames = 0
    bodyMode = .unknown
    coverage = .empty
    pushupFloorModeActive = false
    floorModeStableFrames = 0
    floorModeMissingFrames = 0
    modeConfidence = 0
    relockSuccessCount = 0
    relockFailureCount = 0
  }

  private func updateRelockState(now: TimeInterval) {
    if poseState == .reacquiring {
      if relockStartedAt == nil {
        relockStartedAt = now
      }
      return
    }

    if poseState == .lost {
      if relockStartedAt != nil {
        relockFailureCount += 1
      }
      relockStartedAt = nil
      return
    }

    if let relockStartedAt {
      lastRelockDuration = now - relockStartedAt
      relockSuccessCount += 1
      self.relockStartedAt = nil
    }
  }

  private func normalizedReacquireSource(_ source: ReacquireSource) -> ReacquireSource {
    switch source {
    case .upperBodyRect:
      return .upperBody
    case .fullFrameRefresh:
      return .fullFrame
    default:
      return source
    }
  }

  private func computeROI(measured: [PushlyJointName: PoseJointMeasurement]) -> CGRect? {
    let points = measured.values.filter { $0.inFrame && $0.confidence > 0.05 }.map(\.point)
    guard points.count >= 3 else { return nil }

    let minX = points.map(\.x).min() ?? 0
    let maxX = points.map(\.x).max() ?? 0
    let minY = points.map(\.y).min() ?? 0
    let maxY = points.map(\.y).max() ?? 0

    let width = max(config.reacquire.roiMinSize, maxX - minX)
    let height = max(config.reacquire.roiMinSize, maxY - minY)
    return CGRect(x: minX, y: minY, width: width, height: height)
  }

  private func paddedROI(_ roi: CGRect) -> CGRect {
    let padX = roi.width * config.reacquire.roiPadding
    let padY = roi.height * config.reacquire.roiPadding
    return CGRect(
      x: roi.minX - padX,
      y: roi.minY - padY,
      width: roi.width + padX * 2,
      height: roi.height + padY * 2
    )
  }

  private func resolveHintSource(proposed: ReacquireSource) -> ReacquireSource {
    let normalized = normalizedReacquireSource(proposed)
    let consistencyFrames = max(1, config.reacquire.roiSourceSwitchConsistencyFrames)
    let lockFrames = max(0, config.reacquire.roiSourceLockFrames - 1)

    if normalized == lockedHintSource {
      lockedHintSourceFramesLeft = max(0, lockedHintSourceFramesLeft - 1)
      pendingHintSource = .none
      pendingHintSourceFrames = 0
      return normalized
    }

    if lockedHintSource != .none, lockedHintSourceFramesLeft > 0 {
      lockedHintSourceFramesLeft -= 1
      return lockedHintSource
    }

    if lockedHintSource == .none {
      lockedHintSource = normalized
      lockedHintSourceFramesLeft = lockFrames
      pendingHintSource = .none
      pendingHintSourceFrames = 0
      return normalized
    }

    if pendingHintSource == normalized {
      pendingHintSourceFrames += 1
    } else {
      pendingHintSource = normalized
      pendingHintSourceFrames = 1
    }

    if pendingHintSourceFrames >= consistencyFrames {
      lockedHintSource = normalized
      lockedHintSourceFramesLeft = lockFrames
      pendingHintSource = .none
      pendingHintSourceFrames = 0
      return normalized
    }

    return lockedHintSource
  }

  private func smoothROI(current: CGRect?, target: CGRect, alpha: CGFloat) -> CGRect {
    guard let current else { return target }
    let blend = max(0.05, min(1, alpha))
    let x = current.minX + (target.minX - current.minX) * blend
    let y = current.minY + (target.minY - current.minY) * blend
    let width = current.width + (target.width - current.width) * blend
    let height = current.height + (target.height - current.height) * blend
    return PoseCoordinateConverter.clampNormalizedROI(
      CGRect(x: x, y: y, width: width, height: height),
      minSize: config.reacquire.roiMinSize
    )
  }

  private func updatePushupFloorMode(measured: [PushlyJointName: PoseJointMeasurement]) {
    let candidate = isLikelyPushupFloorState(measured: measured)
    if candidate {
      floorModeStableFrames += 1
      floorModeMissingFrames = 0
    } else {
      floorModeStableFrames = 0
      floorModeMissingFrames += 1
    }

    if pushupFloorModeActive {
      if floorModeMissingFrames >= max(1, config.quality.pushupFloorModeExitFrames) {
        pushupFloorModeActive = false
      }
    } else if floorModeStableFrames >= max(1, config.quality.pushupFloorModeEnterFrames) {
      pushupFloorModeActive = true
    }
  }

  private func isLikelyPushupFloorState(measured: [PushlyJointName: PoseJointMeasurement]) -> Bool {
    guard let nose = measured[.nose], nose.inFrame, nose.confidence >= 0.1 else {
      return false
    }
    let shoulderMid = midpoint(measured[.leftShoulder]?.point, measured[.rightShoulder]?.point)
    guard let shoulderMid else {
      return false
    }
    let shoulderSpan = hypot(
      (measured[.rightShoulder]?.point.x ?? shoulderMid.x) - (measured[.leftShoulder]?.point.x ?? shoulderMid.x),
      (measured[.rightShoulder]?.point.y ?? shoulderMid.y) - (measured[.leftShoulder]?.point.y ?? shoulderMid.y)
    )
    return abs(Double(nose.point.y - shoulderMid.y)) < 0.16 && Double(shoulderSpan) > 0.08
  }

  private func midpoint(_ a: CGPoint?, _ b: CGPoint?) -> CGPoint? {
    switch (a, b) {
    case let (.some(pa), .some(pb)):
      return CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)
    case let (.some(pa), .none):
      return pa
    case let (.none, .some(pb)):
      return pb
    default:
      return nil
    }
  }

  private func hasUpperBodyCore(measured: [PushlyJointName: PoseJointMeasurement]) -> Bool {
    let hasHeadAnchor = measured[.nose] != nil || measured[.head] != nil
    let hasShoulders = measured[.leftShoulder] != nil && measured[.rightShoulder] != nil

    let leftArmCount = [measured[.leftShoulder], measured[.leftElbow], measured[.leftWrist]]
      .compactMap { $0 }
      .count
    let rightArmCount = [measured[.rightShoulder], measured[.rightElbow], measured[.rightWrist]]
      .compactMap { $0 }
      .count
    let hasAnyArmChain = leftArmCount >= 2 || rightArmCount >= 2

    return hasHeadAnchor && hasShoulders && hasAnyArmChain
  }
}

final class PoseHeuristicsSolver {
  private struct TooCloseState {
    var torsoToShoulderRatioEMA: CGFloat = 0.92
    var torsoDirection: CGVector = CGVector(dx: 0, dy: -1)
    var lastHipCenter: CGPoint?
    var engagedUntil: TimeInterval = 0
  }

  private var state = TooCloseState()

  private let shoulderMinConfidence: Float = 0.55
  private let hipLowConfidenceThreshold: Float = 0.24
  private let headAnchorMinConfidence: Float = 0.3
  private let tooCloseHoldDuration: TimeInterval = 0.14

  func applyTooCloseHeuristics(
    joints input: [PushlyJointName: PoseJointMeasurement],
    backend: PoseBackendKind,
    timestamp: TimeInterval
  ) -> [PushlyJointName: PoseJointMeasurement] {
    guard let leftShoulder = strongJoint(input[.leftShoulder]),
          let rightShoulder = strongJoint(input[.rightShoulder]) else {
      return input
    }

    var joints = input

    let shoulders = CGVector(
      dx: rightShoulder.point.x - leftShoulder.point.x,
      dy: rightShoulder.point.y - leftShoulder.point.y
    )
    guard leftShoulder.point.x.isFinite,
          leftShoulder.point.y.isFinite,
          rightShoulder.point.x.isFinite,
          rightShoulder.point.y.isFinite,
          shoulders.dx.isFinite,
          shoulders.dy.isFinite else {
      return input
    }
    let shoulderWidth = max(0.0001, hypot(shoulders.dx, shoulders.dy))
    guard shoulderWidth.isFinite else {
      return input
    }
    let shoulderMid = CGPoint(
      x: (leftShoulder.point.x + rightShoulder.point.x) * 0.5,
      y: (leftShoulder.point.y + rightShoulder.point.y) * 0.5
    )
    guard shoulderMid.x.isFinite, shoulderMid.y.isFinite else {
      return input
    }

    if shoulderWidth < 0.08 {
      return joints
    }

    let leftHipQuality = jointQuality(input[.leftHip])
    let rightHipQuality = jointQuality(input[.rightHip])
    let bothHipsWeak = leftHipQuality <= hipLowConfidenceThreshold && rightHipQuality <= hipLowConfidenceThreshold

    let lowerBodyMissing = isWeak(input[.leftKnee]) && isWeak(input[.rightKnee]) && isWeak(input[.leftAnkle]) && isWeak(input[.rightAnkle])
    let closeFramingHint = shoulderWidth > 0.16 || lowerBodyMissing

    var torsoDirection = resolveTorsoDirection(
      head: bestHeadAnchor(from: joints),
      shoulderMid: shoulderMid,
      currentShoulders: shoulders,
      fallback: state.torsoDirection
    )

    if let measuredHipCenter = measuredHipCenter(from: joints) {
      let measuredLen = distance(measuredHipCenter, shoulderMid)
      guard measuredLen.isFinite else {
        return input
      }
      let ratio = measuredLen / shoulderWidth
      if ratio.isFinite, ratio > 0.35, ratio < 1.9 {
        state.torsoToShoulderRatioEMA = state.torsoToShoulderRatioEMA * 0.88 + ratio * 0.12
      }
      let measuredDir = normalizedVector(from: shoulderMid, to: measuredHipCenter)
      torsoDirection = blendDirections(a: torsoDirection, b: measuredDir, alpha: 0.35)
      state.lastHipCenter = measuredHipCenter
    }

    state.torsoDirection = torsoDirection

    let engaged = bothHipsWeak && closeFramingHint
    if engaged {
      state.engagedUntil = timestamp + tooCloseHoldDuration
    }

    guard engaged || timestamp <= state.engagedUntil else {
      return joints
    }

    let torsoRatio = min(1.35, max(0.62, state.torsoToShoulderRatioEMA))
    let hipDistance = shoulderWidth * torsoRatio
    let hipCenter = PoseCoordinateConverter.clampNormalizedPoint(
      CGPoint(
        x: shoulderMid.x + torsoDirection.dx * hipDistance,
        y: shoulderMid.y + torsoDirection.dy * hipDistance
      )
    )
    guard hipCenter.x.isFinite, hipCenter.y.isFinite else {
      return joints
    }

    let shoulderAxis = normalize(shoulders)
    let hipHalfSpan = shoulderWidth * 0.42
    let inferredLeftHip = PoseCoordinateConverter.clampNormalizedPoint(
      CGPoint(
        x: hipCenter.x - shoulderAxis.dx * hipHalfSpan,
        y: hipCenter.y - shoulderAxis.dy * hipHalfSpan
      )
    )
    let inferredRightHip = PoseCoordinateConverter.clampNormalizedPoint(
      CGPoint(
        x: hipCenter.x + shoulderAxis.dx * hipHalfSpan,
        y: hipCenter.y + shoulderAxis.dy * hipHalfSpan
      )
    )
    guard inferredLeftHip.x.isFinite,
          inferredLeftHip.y.isFinite,
          inferredRightHip.x.isFinite,
          inferredRightHip.y.isFinite else {
      return joints
    }

    let shoulderConfidence = min(leftShoulder.confidence, rightShoulder.confidence)
    let inferredConfidence = min(0.72, max(0.28, shoulderConfidence * 0.88))
    let inferredVisibility = min(leftShoulder.visibility, rightShoulder.visibility) * 0.86
    let inferredPresence = min(leftShoulder.presence, rightShoulder.presence) * 0.86

    if leftHipQuality <= hipLowConfidenceThreshold {
      joints[.leftHip] = PoseJointMeasurement(
        name: .leftHip,
        point: inferredLeftHip,
        confidence: inferredConfidence,
        visibility: inferredVisibility,
        presence: inferredPresence,
        sourceType: .inferred,
        inFrame: inferredLeftHip.x >= 0 && inferredLeftHip.x <= 1 && inferredLeftHip.y >= 0 && inferredLeftHip.y <= 1,
        backend: backend,
        measuredAt: timestamp
      )
    }

    if rightHipQuality <= hipLowConfidenceThreshold {
      joints[.rightHip] = PoseJointMeasurement(
        name: .rightHip,
        point: inferredRightHip,
        confidence: inferredConfidence,
        visibility: inferredVisibility,
        presence: inferredPresence,
        sourceType: .inferred,
        inFrame: inferredRightHip.x >= 0 && inferredRightHip.x <= 1 && inferredRightHip.y >= 0 && inferredRightHip.y <= 1,
        backend: backend,
        measuredAt: timestamp
      )
    }

    state.lastHipCenter = hipCenter
    return joints
  }

  private func bestHeadAnchor(from joints: [PushlyJointName: PoseJointMeasurement]) -> PoseJointMeasurement? {
    if let head = joints[.head], head.confidence >= headAnchorMinConfidence {
      return head
    }
    if let nose = joints[.nose], nose.confidence >= headAnchorMinConfidence {
      return nose
    }
    return nil
  }

  private func strongJoint(_ joint: PoseJointMeasurement?) -> PoseJointMeasurement? {
    guard let joint, joint.confidence >= shoulderMinConfidence else { return nil }
    return joint
  }

  private func jointQuality(_ joint: PoseJointMeasurement?) -> Float {
    guard let joint else { return 0 }
    return min(1, max(0, joint.confidence * 0.75 + joint.visibility * 0.15 + joint.presence * 0.1))
  }

  private func isWeak(_ joint: PoseJointMeasurement?) -> Bool {
    jointQuality(joint) < 0.2
  }

  private func measuredHipCenter(from joints: [PushlyJointName: PoseJointMeasurement]) -> CGPoint? {
    guard let left = joints[.leftHip], left.confidence > 0.35,
          let right = joints[.rightHip], right.confidence > 0.35 else {
      return nil
    }
    return CGPoint(x: (left.point.x + right.point.x) * 0.5, y: (left.point.y + right.point.y) * 0.5)
  }

  private func resolveTorsoDirection(
    head: PoseJointMeasurement?,
    shoulderMid: CGPoint,
    currentShoulders: CGVector,
    fallback: CGVector
  ) -> CGVector {
    if let head {
      let fromHead = normalizedVector(from: head.point, to: shoulderMid)
      return ensureDownward(fromHead)
    }

    var perpendicular = CGVector(dx: -currentShoulders.dy, dy: currentShoulders.dx)
    perpendicular = normalize(perpendicular)
    if perpendicular.dy > 0 {
      perpendicular = perpendicular * -1
    }
    let blended = blendDirections(a: fallback, b: perpendicular, alpha: 0.2)
    return ensureDownward(blended)
  }

  private func blendDirections(a: CGVector, b: CGVector, alpha: CGFloat) -> CGVector {
    let mixed = CGVector(
      dx: a.dx + (b.dx - a.dx) * alpha,
      dy: a.dy + (b.dy - a.dy) * alpha
    )
    return normalize(mixed)
  }

  private func normalizedVector(from a: CGPoint, to b: CGPoint) -> CGVector {
    normalize(CGVector(dx: b.x - a.x, dy: b.y - a.y))
  }

  private func ensureDownward(_ vector: CGVector) -> CGVector {
    var v = normalize(vector)
    if v.dy > 0 {
      v = v * -1
    }
    return v
  }

  private func normalize(_ vector: CGVector) -> CGVector {
    let m = hypot(vector.dx, vector.dy)
    guard m > 0.0001 else { return CGVector(dx: 0, dy: -1) }
    return CGVector(dx: vector.dx / m, dy: vector.dy / m)
  }

  private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
  }
}

extension CGPoint {
  static func +(lhs: CGPoint, rhs: CGVector) -> CGPoint {
    CGPoint(x: lhs.x + rhs.dx, y: lhs.y + rhs.dy)
  }
}

extension CGVector {
  static var zero: CGVector {
    CGVector(dx: 0, dy: 0)
  }

  static func +(lhs: CGVector, rhs: CGVector) -> CGVector {
    CGVector(dx: lhs.dx + rhs.dx, dy: lhs.dy + rhs.dy)
  }

  static func *(lhs: CGVector, rhs: CGFloat) -> CGVector {
    CGVector(dx: lhs.dx * rhs, dy: lhs.dy * rhs)
  }
}
#endif
