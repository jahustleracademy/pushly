import Foundation

#if os(iOS)
import CoreGraphics

final class PushupRepDetector {
  private let config: PushlyPoseConfig
  private(set) var repCount = 0
  private(set) var state: PushupState = .idle

  private var plankFrames = 0
  private var bottomReached = false
  private var smoothedElbowAngle: CGFloat = 170
  private var previousSmoothedElbowAngle: CGFloat = 170
  private var smoothedShoulderY: CGFloat = 0
  private var previousShoulderY: CGFloat = 0
  private var smoothedTorsoY: CGFloat = 0
  private var previousTorsoY: CGFloat = 0
  private var descendingFrames = 0
  private var bottomFrames = 0
  private var ascendingFrames = 0
  private var logicBlockedFrames = 0
  private var repStartElbowAngle: CGFloat = 170
  private var repMinElbowAngle: CGFloat = 170
  private var repStartShoulderY: CGFloat = 0
  private var repMaxShoulderY: CGFloat = 0
  private var repStartTorsoY: CGFloat = 0
  private var repMaxTorsoY: CGFloat = 0
  private var floorBaselineTorsoY: CGFloat = 0
  private var hasFloorBaselineTorsoY = false
  private var bottomOcclusionFrames = 0
  private var repRearmPending = false
  private var topRecoveryFrames = 0
  private var ascendingSignalGapFrames = 0
  private var topRecoveryGateGapFrames = 0
  private var commitPathActive = false
  private var commitPathGraceFramesRemaining = 0
  private var commitTopRecoveryFrames = 0
  private var bottomConfirmedLatched = false
  private var bottomLatchFramesRemaining = 0
  private var trackingLossGraceFramesRemaining = 0
  private var trackingLossDuringCommitPath = 0
  private var lostTrackingAtBottom = false
  private var didEnterAscending = false
  private var didEnterTopRecovery = false
  private var commitCancelledReason: String?
  private var firstBlockingConditionAfterBottom: String?
  private var bottomConfirmedCount = 0
  private var ascendingEnteredCount = 0
  private var topRecoveryEnteredCount = 0
  private var repCommitAttemptCount = 0
  private var repCommitSuccessCount = 0
  private var repCommitBlockedCount = 0
  private var smoothedTorsoStability: Double = 0.4
  private var torsoUnstableFrames = 0
  private var previousStateForDebugEvent: PushupState = .idle
  private var previousRepStateMachineStateForDebugEvent = "idle"
  private var previousRawShoulderY: CGFloat = 0
  private var previousRawTorsoY: CGFloat = 0
  private var currentRawShoulderY: CGFloat = 0
  private var currentRawTorsoY: CGFloat = 0
  private var currentRawShoulderVelocity: CGFloat = 0
  private var currentRawTorsoVelocity: CGFloat = 0
  private var currentFrameIndex: Int = 0
  private var currentTimestampSeconds: Double = 0
  private var currentRepStateMachineState = "idle"
  private var currentRepStateTransitionEvent: String?
  private var currentWeakestLandmark: String?
  private var currentWeakestLandmarkConfidence = 0.0
  private var currentMissingLandmarks: [String] = []
  private var currentLandmarkQuality: [String: [String: Any]] = [:]
  private var currentBottomNearMiss = false
  private var currentBodyFound = false
  private var currentTrackingQualityPass = false
  private var currentLogicQualityPass = false
  private var currentBottomGate = false
  private var currentAscentGate = false
  private var currentRearmGate = false
  private var currentCountCommitReady = false
  private var currentCommitPathActive = false
  private var currentIdleResetReason: String?
  private var currentPendingCommitReason: String?
  private var currentCommitBlockedBy: String?
  private var currentCommitCancelledReason: String?
  private var currentFirstBlockingConditionAfterBottom: String?
  private var lastFailedGate: String?
  private var lastSuccessfulGate: String?
  private var whyRepDidNotCount: String?
  private var firstFinalBlocker: String?
  private var currentRearmBlockedReason: String?
  private var currentRearmMissingCondition: String?
  private var repsAttemptedEstimate = 0
  private var repsBlockedByBottom = 0
  private var repsBlockedByTopRecovery = 0
  private var repsBlockedByRearm = 0
  private var repsBlockedByTrackingLoss = 0
  private var repsBlockedByTravel = 0
  private var repsBlockedByQuality = 0
  private var attemptActive = false
  private var topReadyLatched = false
  private var cycleFramesSinceDescendingStart = 0
  private var cycleFramesSinceBottomLatch = 0
  private var currentTopReady = false
  private var currentDescendingStarted = false
  private var currentBottomLatched = false
  private var currentAscendingStarted = false
  private var currentTopRecovered = false
  private var currentRepCommitted = false
  private var currentRearmReady = false
  private var currentResetReason: String?
  private var currentTimeoutOrAbortReason: String?
  private var establishedPushupBodyFrames = 0
  private var bodyFoundDropGraceFramesRemaining = 0
  private var rearmTopRecoveryDipGraceFramesRemaining = 0
  private var rearmDescendingSignalGraceFramesRemaining = 0
  private var currentRearmConfirmProgress = 0.0
  private let bottomReacquireHoldMinFrames = 2
  private let bottomReacquireHoldMaxFrames = 6
  private var bottomReacquireHoldFramesRemaining = 0
  private var currentBottomReacquireState: String?
  private var currentBottomSupportAnchors: [String] = []
  private var currentBottomBlockedReason: String?

  init(config: PushlyPoseConfig) {
    self.config = config
  }

  func reset(repCount: Int = 0) {
    self.repCount = repCount
    state = .idle
    plankFrames = 0
    bottomReached = false
    smoothedElbowAngle = 170
    previousSmoothedElbowAngle = 170
    smoothedShoulderY = 0
    previousShoulderY = 0
    smoothedTorsoY = 0
    previousTorsoY = 0
    descendingFrames = 0
    bottomFrames = 0
    ascendingFrames = 0
    logicBlockedFrames = 0
    repStartElbowAngle = 170
    repMinElbowAngle = 170
    repStartShoulderY = 0
    repMaxShoulderY = 0
    repStartTorsoY = 0
    repMaxTorsoY = 0
    floorBaselineTorsoY = 0
    hasFloorBaselineTorsoY = false
    bottomOcclusionFrames = 0
    repRearmPending = false
    topRecoveryFrames = 0
    ascendingSignalGapFrames = 0
    topRecoveryGateGapFrames = 0
    commitPathActive = false
    commitPathGraceFramesRemaining = 0
    commitTopRecoveryFrames = 0
    bottomConfirmedLatched = false
    bottomLatchFramesRemaining = 0
    trackingLossGraceFramesRemaining = 0
    trackingLossDuringCommitPath = 0
    lostTrackingAtBottom = false
    didEnterAscending = false
    didEnterTopRecovery = false
    commitCancelledReason = nil
    firstBlockingConditionAfterBottom = nil
    bottomConfirmedCount = 0
    ascendingEnteredCount = 0
    topRecoveryEnteredCount = 0
    repCommitAttemptCount = 0
    repCommitSuccessCount = 0
    repCommitBlockedCount = 0
    smoothedTorsoStability = 0.4
    torsoUnstableFrames = 0
    previousStateForDebugEvent = .idle
    previousRepStateMachineStateForDebugEvent = "idle"
    previousRawShoulderY = 0
    previousRawTorsoY = 0
    currentRawShoulderY = 0
    currentRawTorsoY = 0
    currentRawShoulderVelocity = 0
    currentRawTorsoVelocity = 0
    currentFrameIndex = 0
    currentTimestampSeconds = 0
    currentRepStateMachineState = "idle"
    currentRepStateTransitionEvent = nil
    currentWeakestLandmark = nil
    currentWeakestLandmarkConfidence = 0
    currentMissingLandmarks = []
    currentLandmarkQuality = [:]
    currentBottomNearMiss = false
    currentBodyFound = false
    currentTrackingQualityPass = false
    currentLogicQualityPass = false
    currentBottomGate = false
    currentAscentGate = false
    currentRearmGate = false
    currentCountCommitReady = false
    currentCommitPathActive = false
    currentIdleResetReason = nil
    currentPendingCommitReason = nil
    currentCommitBlockedBy = nil
    currentCommitCancelledReason = nil
    currentFirstBlockingConditionAfterBottom = nil
    lastFailedGate = nil
    lastSuccessfulGate = nil
    whyRepDidNotCount = nil
    firstFinalBlocker = nil
    currentRearmBlockedReason = nil
    currentRearmMissingCondition = nil
    repsAttemptedEstimate = 0
    repsBlockedByBottom = 0
    repsBlockedByTopRecovery = 0
    repsBlockedByRearm = 0
    repsBlockedByTrackingLoss = 0
    repsBlockedByTravel = 0
    repsBlockedByQuality = 0
    attemptActive = false
    topReadyLatched = false
    cycleFramesSinceDescendingStart = 0
    cycleFramesSinceBottomLatch = 0
    currentTopReady = false
    currentDescendingStarted = false
    currentBottomLatched = false
    currentAscendingStarted = false
    currentTopRecovered = false
    currentRepCommitted = false
    currentRearmReady = false
    currentResetReason = nil
    currentTimeoutOrAbortReason = nil
    establishedPushupBodyFrames = 0
    bodyFoundDropGraceFramesRemaining = 0
    rearmTopRecoveryDipGraceFramesRemaining = 0
    rearmDescendingSignalGraceFramesRemaining = 0
    currentRearmConfirmProgress = 0
    bottomReacquireHoldFramesRemaining = 0
    currentBottomReacquireState = nil
    currentBottomSupportAnchors = []
    currentBottomBlockedReason = nil
  }

  func update(
    joints: [PushlyJointName: TrackedJoint],
    quality: TrackingQuality,
    repTarget: Int,
    frameIndex: Int = 0,
    timestamp: TimeInterval = 0
  ) -> RepDetectionOutput {
    _ = repTarget
    currentFrameIndex = frameIndex
    currentTimestampSeconds = timestamp
    currentRepStateTransitionEvent = nil
    currentBottomNearMiss = false
    currentRearmBlockedReason = nil
    currentRearmMissingCondition = nil
    currentIdleResetReason = nil
    currentPendingCommitReason = nil
    currentCommitBlockedBy = nil
    currentCommitCancelledReason = nil
    currentFirstBlockingConditionAfterBottom = nil
    lostTrackingAtBottom = false
    currentTopReady = false
    currentDescendingStarted = false
    currentBottomLatched = false
    currentAscendingStarted = false
    currentTopRecovered = false
    currentRepCommitted = false
    currentRearmReady = !repRearmPending
    currentResetReason = nil
    currentTimeoutOrAbortReason = nil
    currentBottomReacquireState = nil
    currentBottomSupportAnchors = []
    currentBottomBlockedReason = nil
    let landmarkDiagnostics = buildLandmarkDiagnostics(joints: joints)
    currentLandmarkQuality = landmarkDiagnostics.landmarkQuality
    currentWeakestLandmark = landmarkDiagnostics.weakestLandmark
    currentWeakestLandmarkConfidence = landmarkDiagnostics.weakestConfidence
    currentMissingLandmarks = landmarkDiagnostics.missingLandmarks
    let signal = computeSignal(joints: joints)
    let floorState = quality.pushupFloorModeActive || signal.pushupFloorState
    let minMeasuredEvidence = floorState ? config.rep.floorMinMeasuredEvidence : config.rep.minMeasuredEvidence
    let minTorsoStability = floorState ? config.rep.floorMinTorsoStability : config.rep.minTorsoStability
    let minShoulderHipLineQuality = floorState ? config.rep.floorMinShoulderHipLineQuality : config.rep.minShoulderHipLineQuality
    let dominantEvidence = max(signal.measuredEvidence, signal.structuralEvidence, signal.upperBodyEvidence)
    let inActivePushupPhase =
      repRearmPending ||
      commitPathActive ||
      bottomReached ||
      bottomConfirmedLatched ||
      descendingFrames > 0 ||
      bottomFrames > 0 ||
      ascendingFrames > 0 ||
      state == .descending ||
      state == .ascending ||
      state == .plankLocked ||
      topReadyLatched
    let hasPlausibleFloorAnchors = hasPlausibleFloorBodyAnchors(joints: joints)
    let bottomSupport = bottomSupportAnchors(joints: joints)
    currentBottomSupportAnchors = bottomSupport.names
    let qualityNotCollapsed =
      quality.renderQuality >= max(0.16, config.quality.renderMin * 0.62) &&
      quality.upperBodyCoverage >= config.quality.notFoundThreshold * 0.8
    let inBottomCommitWindow = commitPathActive && (bottomReached || bottomConfirmedLatched)
    let bottomTrackingNotCollapsed =
      quality.renderQuality >= max(0.13, config.quality.renderMin * 0.52) &&
      quality.upperBodyCoverage >= max(0.22, config.quality.notFoundThreshold * 0.65)
    let bottomEvidenceNotCollapsed =
      dominantEvidence >= max(0.24, minMeasuredEvidence * 0.68) ||
      quality.logicQuality >= max(0.14, config.rep.minLogicQualityToProgress * 0.72)
    let bottomReacquireHoldEligible =
      inBottomCommitWindow &&
      bottomSupport.hasAny &&
      bottomTrackingNotCollapsed &&
      (bottomEvidenceNotCollapsed || qualityNotCollapsed || repRearmPending || ascendingFrames > 0)
    if inBottomCommitWindow {
      currentBottomReacquireState = bottomReacquireHoldEligible ? "eligible" : "blocked"
      if !bottomReacquireHoldEligible {
        currentBottomBlockedReason = "bottom_support_or_quality_insufficient"
      }
    } else {
      currentBottomReacquireState = "inactive"
    }
    if signal.hasRenderableBody {
      if inActivePushupPhase || floorState {
        establishedPushupBodyFrames = min(12, establishedPushupBodyFrames + 2)
      } else {
        establishedPushupBodyFrames = min(12, establishedPushupBodyFrames + 1)
      }
    } else {
      establishedPushupBodyFrames = max(0, establishedPushupBodyFrames - 1)
    }
    let bodyPreviouslyEstablished = establishedPushupBodyFrames >= 2 || repCount > 0 || repRearmPending
    let floorFallbackBodyFound =
      bodyPreviouslyEstablished &&
      (inActivePushupPhase || floorState) &&
      hasPlausibleFloorAnchors &&
      qualityNotCollapsed
    var hasRenderableBodyForLogic = signal.hasRenderableBody || floorFallbackBodyFound
    if signal.hasRenderableBody, bodyPreviouslyEstablished || inActivePushupPhase {
      bodyFoundDropGraceFramesRemaining = max(bodyFoundDropGraceFramesRemaining, 3)
    }
    if !hasRenderableBodyForLogic {
      let allowDropGrace =
        bodyPreviouslyEstablished &&
        qualityNotCollapsed &&
        (inActivePushupPhase || hasPlausibleFloorAnchors || floorState)
      if allowDropGrace, bodyFoundDropGraceFramesRemaining > 0 {
        bodyFoundDropGraceFramesRemaining -= 1
        hasRenderableBodyForLogic = true
      } else if !allowDropGrace {
        bodyFoundDropGraceFramesRemaining = 0
      }
    } else if signal.hasRenderableBody {
      bodyFoundDropGraceFramesRemaining = max(bodyFoundDropGraceFramesRemaining, 2)
    }
    var topReady = false
    var descendingStarted = false
    var bottomLatched = false
    var ascendingStarted = false
    var topRecovered = false
    var repCommitted = false
    var rearmReady = !repRearmPending

    guard hasRenderableBodyForLogic else {
      if inBottomCommitWindow && trackingLossGraceFramesRemaining > 0 {
        trackingLossDuringCommitPath += 1
        lostTrackingAtBottom = true
        trackingLossGraceFramesRemaining -= 1
        commitPathGraceFramesRemaining = max(0, commitPathGraceFramesRemaining - 1)
        bottomLatchFramesRemaining = max(0, bottomLatchFramesRemaining - 1)
        bottomConfirmedLatched = bottomReached || bottomLatchFramesRemaining > 0
        state = quality.renderQuality >= config.quality.renderMin ? .trackingAssisted : .lostTracking
        currentBottomReacquireState = "tracking_loss_grace"
        currentBottomBlockedReason = "tracking_loss_grace_active"
        currentBodyFound = false
        currentTrackingQualityPass = false
        currentLogicQualityPass = false
        currentBottomGate = bottomReached
        currentAscentGate = ascendingFrames >= config.rep.ascendingConfirmFrames
        currentRearmGate = !repRearmPending
        currentCountCommitReady = false
        currentCommitPathActive = commitPathActive
        currentPendingCommitReason = "tracking_loss_tolerated"
        currentCommitBlockedBy = nil
        currentCommitCancelledReason = nil
        lastFailedGate = "bodyFound"
        let resolvedBlockedReasons = ["body_not_found", "tracking_loss_grace_active"]
        whyRepDidNotCount = firstFinalBlocker ?? "tracking_loss_tolerated"
        topReady = topReadyLatched || isStartupReady()
        descendingStarted = descendingFrames > 0 || state == .descending || commitPathActive
        bottomLatched = bottomReached || bottomConfirmedLatched
        ascendingStarted = ascendingFrames > 0 || didEnterAscending
        topRecovered = commitTopRecoveryFrames > 0
        rearmReady = !repRearmPending
        currentTopReady = topReady
        currentDescendingStarted = descendingStarted
        currentBottomLatched = bottomLatched
        currentAscendingStarted = ascendingStarted
        currentTopRecovered = topRecovered
        currentRepCommitted = false
        currentRearmReady = rearmReady
        currentRearmConfirmProgress = repRearmPending
          ? min(1, Double(topRecoveryFrames) / Double(max(1, config.rep.repRearmConfirmFrames)))
          : 1
        currentRepStateMachineState = resolveRepStateMachineState(repCounted: false)
        currentRepStateTransitionEvent = consumeRepStateMachineTransitionEvent(currentState: currentRepStateMachineState, frameIndex: frameIndex, timestamp: timestamp)
        return RepDetectionOutput(
          state: state,
          repCount: repCount,
          formEvidenceScore: signal.formEvidenceScore,
          blockedReasons: resolvedBlockedReasons,
          repDebug: makeRepDebug(
            blockedReasons: resolvedBlockedReasons,
            dominantEvidence: dominantEvidence,
            measuredEvidence: signal.measuredEvidence,
            structuralEvidence: signal.structuralEvidence,
            upperBodyEvidence: signal.upperBodyEvidence,
            shoulderVelocity: 0,
            torsoVelocity: 0,
            topReferenceTorsoY: hasFloorBaselineTorsoY ? floorBaselineTorsoY : repStartTorsoY,
            topReferenceShoulderY: repStartShoulderY,
            descendingSignal: false,
            ascendingSignal: false,
            shoulderDownTravel: 0,
            shoulderRecoveryToTop: 0,
            torsoDownTravel: 0,
            torsoRecoveryToTop: 0,
            canProgress: false,
            logicBlockedFrames: logicBlockedFrames,
            startupReady: false,
            startupTopEvidence: plankFrames,
            startupDescendBridgeUsed: false,
            startBlockedReason: repCount == 0 ? "body_not_found" : nil,
            repRearmPending: repRearmPending,
            topRecoveryFrames: topRecoveryFrames,
            commitPathActive: currentCommitPathActive,
            idleResetReason: currentIdleResetReason,
            pendingCommitReason: currentPendingCommitReason,
            commitBlockedBy: currentCommitBlockedBy,
            cycleCoreReady: false,
            strictCycleReady: false,
            floorFallbackCycleReady: false,
            motionTravelGate: false,
            topRecoveryGate: false,
            torsoSupportReady: false,
            shoulderSupportReady: false,
            countGatePassed: false,
            countGateBlocked: true,
            countGateBlockReason: "body_not_found"
          )
        )
      } else if inBottomCommitWindow && bottomReacquireHoldEligible && bottomReacquireHoldFramesRemaining > 0 {
        trackingLossDuringCommitPath += 1
        lostTrackingAtBottom = true
        bottomReacquireHoldFramesRemaining -= 1
        commitPathGraceFramesRemaining = max(0, commitPathGraceFramesRemaining - 1)
        bottomLatchFramesRemaining = max(0, bottomLatchFramesRemaining - 1)
        bottomConfirmedLatched = bottomReached || bottomLatchFramesRemaining > 0
        state = quality.renderQuality >= config.quality.renderMin ? .trackingAssisted : .lostTracking
        currentBottomReacquireState = "hold_active"
        currentBottomBlockedReason = "bottom_reacquire_hold"
        currentBodyFound = false
        currentTrackingQualityPass = false
        currentLogicQualityPass = false
        currentBottomGate = bottomReached
        currentAscentGate = ascendingFrames >= config.rep.ascendingConfirmFrames
        currentRearmGate = !repRearmPending
        currentCountCommitReady = false
        currentCommitPathActive = commitPathActive
        currentPendingCommitReason = "bottom_reacquire_hold"
        currentCommitBlockedBy = nil
        currentCommitCancelledReason = nil
        lastFailedGate = "bodyFound"
        let resolvedBlockedReasons = ["body_not_found", "bottom_reacquire_hold"]
        whyRepDidNotCount = firstFinalBlocker ?? "bottom_reacquire_hold"
        topReady = topReadyLatched || isStartupReady()
        descendingStarted = descendingFrames > 0 || state == .descending || commitPathActive
        bottomLatched = bottomReached || bottomConfirmedLatched
        ascendingStarted = ascendingFrames > 0 || didEnterAscending
        topRecovered = commitTopRecoveryFrames > 0
        rearmReady = !repRearmPending
        currentTopReady = topReady
        currentDescendingStarted = descendingStarted
        currentBottomLatched = bottomLatched
        currentAscendingStarted = ascendingStarted
        currentTopRecovered = topRecovered
        currentRepCommitted = false
        currentRearmReady = rearmReady
        currentRearmConfirmProgress = repRearmPending
          ? min(1, Double(topRecoveryFrames) / Double(max(1, config.rep.repRearmConfirmFrames)))
          : 1
        currentRepStateMachineState = resolveRepStateMachineState(repCounted: false)
        currentRepStateTransitionEvent = consumeRepStateMachineTransitionEvent(currentState: currentRepStateMachineState, frameIndex: frameIndex, timestamp: timestamp)
        return RepDetectionOutput(
          state: state,
          repCount: repCount,
          formEvidenceScore: signal.formEvidenceScore,
          blockedReasons: resolvedBlockedReasons,
          repDebug: makeRepDebug(
            blockedReasons: resolvedBlockedReasons,
            dominantEvidence: dominantEvidence,
            measuredEvidence: signal.measuredEvidence,
            structuralEvidence: signal.structuralEvidence,
            upperBodyEvidence: signal.upperBodyEvidence,
            shoulderVelocity: 0,
            torsoVelocity: 0,
            topReferenceTorsoY: hasFloorBaselineTorsoY ? floorBaselineTorsoY : repStartTorsoY,
            topReferenceShoulderY: repStartShoulderY,
            descendingSignal: false,
            ascendingSignal: false,
            shoulderDownTravel: 0,
            shoulderRecoveryToTop: 0,
            torsoDownTravel: 0,
            torsoRecoveryToTop: 0,
            canProgress: false,
            logicBlockedFrames: logicBlockedFrames,
            startupReady: false,
            startupTopEvidence: plankFrames,
            startupDescendBridgeUsed: false,
            startBlockedReason: repCount == 0 ? "body_not_found" : nil,
            repRearmPending: repRearmPending,
            topRecoveryFrames: topRecoveryFrames,
            commitPathActive: currentCommitPathActive,
            idleResetReason: currentIdleResetReason,
            pendingCommitReason: currentPendingCommitReason,
            commitBlockedBy: currentCommitBlockedBy,
            cycleCoreReady: false,
            strictCycleReady: false,
            floorFallbackCycleReady: false,
            motionTravelGate: false,
            topRecoveryGate: false,
            torsoSupportReady: false,
            shoulderSupportReady: false,
            countGatePassed: false,
            countGateBlocked: true,
            countGateBlockReason: "body_not_found"
          )
        )
      }

      state = .lostTracking
      plankFrames = 0
      bottomReached = false
      bottomConfirmedLatched = false
      bottomLatchFramesRemaining = 0
      bottomOcclusionFrames = 0
      repRearmPending = false
      topRecoveryFrames = 0
      ascendingSignalGapFrames = 0
      topRecoveryGateGapFrames = 0
      commitPathActive = false
      commitPathGraceFramesRemaining = 0
      trackingLossGraceFramesRemaining = 0
      bottomReacquireHoldFramesRemaining = 0
      commitTopRecoveryFrames = 0
      smoothedTorsoStability = 0.4
      torsoUnstableFrames = 0
      currentBodyFound = false
      currentTrackingQualityPass = false
      currentLogicQualityPass = false
      currentBottomGate = false
      currentAscentGate = false
      currentRearmGate = false
      currentCountCommitReady = false
      currentCommitPathActive = false
      currentIdleResetReason = "body_not_found"
      currentResetReason = "body_not_found"
      currentTimeoutOrAbortReason = "body_not_found"
      currentPendingCommitReason = "body_not_found"
      currentCommitBlockedBy = "trackingGate"
      currentBottomReacquireState = "inactive"
      currentBottomBlockedReason = "body_not_found"
      currentRearmReady = true
      currentRearmConfirmProgress = 0
      commitCancelledReason = "body_not_found"
      currentCommitCancelledReason = commitCancelledReason
      lastFailedGate = "bodyFound"
      if attemptActive {
        let finalReason = firstFinalBlocker ?? "body_not_found"
        whyRepDidNotCount = finalReason
        recordAttemptBlocked(reason: finalReason)
        repCommitBlockedCount += 1
        attemptActive = false
        firstFinalBlocker = nil
      } else {
        whyRepDidNotCount = "body_not_found"
      }
      topReadyLatched = false
      cycleFramesSinceDescendingStart = 0
      cycleFramesSinceBottomLatch = 0
      currentRepStateMachineState = resolveRepStateMachineState(repCounted: false)
      currentRepStateTransitionEvent = consumeRepStateMachineTransitionEvent(currentState: currentRepStateMachineState, frameIndex: frameIndex, timestamp: timestamp)
      let resolvedBlockedReasons = ["body_not_found"]
      return RepDetectionOutput(
        state: state,
        repCount: repCount,
        formEvidenceScore: signal.formEvidenceScore,
        blockedReasons: resolvedBlockedReasons,
        repDebug: makeRepDebug(
          blockedReasons: resolvedBlockedReasons,
          dominantEvidence: dominantEvidence,
          measuredEvidence: signal.measuredEvidence,
          structuralEvidence: signal.structuralEvidence,
          upperBodyEvidence: signal.upperBodyEvidence,
          shoulderVelocity: 0,
          torsoVelocity: 0,
          topReferenceTorsoY: hasFloorBaselineTorsoY ? floorBaselineTorsoY : repStartTorsoY,
          topReferenceShoulderY: repStartShoulderY,
          descendingSignal: false,
          ascendingSignal: false,
          shoulderDownTravel: 0,
          shoulderRecoveryToTop: 0,
          torsoDownTravel: 0,
          torsoRecoveryToTop: 0,
          canProgress: false,
          logicBlockedFrames: logicBlockedFrames,
          startupReady: false,
          startupTopEvidence: plankFrames,
          startupDescendBridgeUsed: false,
          startBlockedReason: repCount == 0 ? "body_not_found" : nil,
          repRearmPending: repRearmPending,
          topRecoveryFrames: topRecoveryFrames,
          commitPathActive: currentCommitPathActive,
          idleResetReason: currentIdleResetReason,
          pendingCommitReason: currentPendingCommitReason,
          commitBlockedBy: currentCommitBlockedBy,
          cycleCoreReady: false,
          strictCycleReady: false,
          floorFallbackCycleReady: false,
          motionTravelGate: false,
          topRecoveryGate: false,
          torsoSupportReady: false,
          shoulderSupportReady: false,
          countGatePassed: false,
          countGateBlocked: true,
          countGateBlockReason: "body_not_found"
        )
      )
    }

    previousSmoothedElbowAngle = smoothedElbowAngle
    if previousRawShoulderY == 0 {
      previousRawShoulderY = signal.shoulderY
    }
    if previousRawTorsoY == 0 {
      previousRawTorsoY = signal.torsoY
    }
    currentRawShoulderY = signal.shoulderY
    currentRawTorsoY = signal.torsoY
    currentRawShoulderVelocity = currentRawShoulderY - previousRawShoulderY
    currentRawTorsoVelocity = currentRawTorsoY - previousRawTorsoY
    previousRawShoulderY = currentRawShoulderY
    previousRawTorsoY = currentRawTorsoY
    if signal.hasElbowMeasurement {
      smoothedElbowAngle = smoothedElbowAngle * (1 - config.rep.elbowSmoothAlpha) + signal.elbowAngle * config.rep.elbowSmoothAlpha
    }
    if smoothedShoulderY == 0 {
      smoothedShoulderY = signal.shoulderY
      previousShoulderY = signal.shoulderY
    } else {
      previousShoulderY = smoothedShoulderY
      smoothedShoulderY = smoothedShoulderY * (1 - config.rep.shoulderSmoothAlpha) + signal.shoulderY * config.rep.shoulderSmoothAlpha
    }
    if smoothedTorsoY == 0 {
      smoothedTorsoY = signal.torsoY
      previousTorsoY = signal.torsoY
    } else {
      previousTorsoY = smoothedTorsoY
      smoothedTorsoY = smoothedTorsoY * (1 - config.rep.torsoSmoothAlpha) + signal.torsoY * config.rep.torsoSmoothAlpha
    }
    if signal.hasElbowMeasurement {
      bottomOcclusionFrames = 0
    } else if bottomReached {
      bottomOcclusionFrames += 1
    } else {
      bottomOcclusionFrames = 0
    }

    let shoulderVelocity = smoothedShoulderY - previousShoulderY
    let torsoVelocity = smoothedTorsoY - previousTorsoY
    // Coordinates are normalized in a Cartesian-like frame where larger Y is visually higher.
    // So a visible downward push-up descent moves shoulders/torso toward smaller Y values.
    let torsoTopReference = hasFloorBaselineTorsoY ? floorBaselineTorsoY : repStartTorsoY
    let shoulderTopReference = repStartShoulderY
    var descendingSignal = false
    var ascendingSignal = false
    var torsoDownTravel = max(0, torsoTopReference - repMaxTorsoY)
    var torsoRecoveryToTop = max(0, smoothedTorsoY - repMaxTorsoY)
    var shoulderDownTravel = max(0, shoulderTopReference - repMaxShoulderY)
    var shoulderRecoveryToTop = max(0, smoothedShoulderY - repMaxShoulderY)
    var cycleCoreReady = false
    var strictCycleReady = false
    var floorFallbackCycleReady = false
    var motionTravelGate = false
    var topRecoveryGate = false
    var torsoSupportReady = false
    var shoulderSupportReady = false
    var countGatePassed = false
    var countGateBlocked = false
    var countGateBlockReason: String?
    let rearmTopRecoveryOffset = config.rep.maxTorsoTopRecoveryOffset * config.rep.rearmTopRecoveryOffsetMultiplier
    let topRecoveryGateOffset = repRearmPending ? rearmTopRecoveryOffset : config.rep.maxTorsoTopRecoveryOffset
    let nearTopRecoveryGate = smoothedTorsoY >= torsoTopReference - (topRecoveryGateOffset + 0.011)

    let activeRepCycle =
      bottomReached ||
      descendingFrames > 0 ||
      bottomFrames > 0 ||
      ascendingFrames > 0 ||
      state == .descending ||
      state == .ascending
    var blockedReasons: [String] = []
    // Keep three distinct quality levels:
    // 1) renderable enough to maintain an active cycle,
    // 2) progression-quality for cycle continuity,
    // 3) strict count-quality (kept unchanged below in strictCycleReady/floorFallbackCycleReady).
    let isLowLightQualityDip = quality.reasonCodes.contains("low_light") || quality.reasonCodes.contains("very_low_light")
    let isTrackingQualityDip =
      quality.trackingState != .tracking
      || quality.bodyVisibilityState == .assisted
      || quality.bodyVisibilityState == .partial
    let isRenderableForProgression =
      quality.renderQuality >= config.quality.renderMin
      && quality.visibleJointCount >= config.pipeline.logicMinJointCount
    let progressionLogicQualityGate: Double = {
      guard activeRepCycle && isRenderableForProgression else { return config.rep.minLogicQualityToProgress }
      var gate = config.rep.minLogicQualityToProgress - 0.02
      if isLowLightQualityDip { gate -= 0.02 }
      if isTrackingQualityDip { gate -= 0.01 }
      return max(0.2, gate)
    }()
    if quality.logicQuality < progressionLogicQualityGate {
      blockedReasons.append("logic_quality_low")
    }
    if dominantEvidence < minMeasuredEvidence {
      blockedReasons.append("measured_evidence_low")
    }
    let torsoStabilityAlpha = floorState ? 0.24 : 0.2
    smoothedTorsoStability = smoothedTorsoStability * (1 - torsoStabilityAlpha) + signal.torsoStability * torsoStabilityAlpha
    let torsoStabilityForGate = max(signal.torsoStability, smoothedTorsoStability - 0.02)
    let torsoCycleGateRelief = (activeRepCycle && isRenderableForProgression && isLowLightQualityDip) ? 0.005 : 0
    let torsoStabilityGate = (floorState && activeRepCycle)
      ? max(0.2, minTorsoStability - 0.015 - torsoCycleGateRelief)
      : minTorsoStability
    let torsoStabilityGraceFrames = activeRepCycle
      ? max(2, config.rep.ascendingConfirmFrames + 1) + (((isLowLightQualityDip || isTrackingQualityDip) && isRenderableForProgression) ? 1 : 0)
      : 1
    if torsoStabilityForGate < torsoStabilityGate {
      torsoUnstableFrames += 1
    } else {
      torsoUnstableFrames = 0
    }
    let allowFloorCycleTorsoStabilityGrace =
      floorState &&
      activeRepCycle &&
      isRenderableForProgression &&
      quality.logicQuality >= progressionLogicQualityGate
    if torsoUnstableFrames > torsoStabilityGraceFrames && !allowFloorCycleTorsoStabilityGrace {
      blockedReasons.append("torso_unstable")
    }
    if signal.shoulderHipLineQuality < minShoulderHipLineQuality {
      blockedReasons.append("shoulder_hip_line_weak")
    }
    if signal.renderableArmCount >= 2 && signal.bilateralElbowAngleDelta > config.rep.bilateralElbowMaxAngleDelta {
      blockedReasons.append("arm_asymmetry")
    }
    if floorState && blockedReasons.contains("measured_evidence_low") {
      blockedReasons.removeAll { $0 == "measured_evidence_low" }
    }
    if floorState && blockedReasons.contains("shoulder_hip_line_weak") && signal.shoulderHipLineQuality >= 0.32 {
      blockedReasons.removeAll { $0 == "shoulder_hip_line_weak" }
    }
    let logicReady = blockedReasons.isEmpty
    if logicReady {
      logicBlockedFrames = 0
    } else {
      logicBlockedFrames += 1
    }
    let progressionGraceBoostFrames = (activeRepCycle && isRenderableForProgression && (isLowLightQualityDip || isTrackingQualityDip)) ? 2 : 0
    let progressionLogicGraceFrames = config.rep.logicGateGraceFrames + progressionGraceBoostFrames
    let canProgress = logicReady || logicBlockedFrames <= progressionLogicGraceFrames
    let ascendingSignalGraceFrames = max(1, config.rep.ascendingConfirmFrames - 1)
    let topRecoveryGateGraceFrames = max(1, config.rep.rearmDecayGraceFrames)
    var startupDescendBridgeUsed = false

    if !canProgress {
      if quality.renderQuality >= config.quality.renderMin {
        state = .trackingAssisted
      } else {
        state = .lostTracking
      }

      // Avoid destroying an already valid cycle on short logic dips.
      // Keep only a tiny hold window, then decay aggressively to prevent stale/noise-driven counts.
      let blockedOverrun = max(0, logicBlockedFrames - progressionLogicGraceFrames)
      let shortHoldWindow = max(1, config.rep.ascendingConfirmFrames)
      let severeDecayStep = state == .lostTracking ? 3 : 2
      let mildDecayStep = 1
      let decayStep = blockedOverrun <= shortHoldWindow ? mildDecayStep : severeDecayStep
      let commitGraceActive =
        commitPathActive &&
        (commitPathGraceFramesRemaining > 0 || trackingLossGraceFramesRemaining > 0 || bottomConfirmedLatched)

      if commitGraceActive {
        commitPathGraceFramesRemaining -= 1
        trackingLossGraceFramesRemaining = max(0, trackingLossGraceFramesRemaining - 1)
        bottomLatchFramesRemaining = max(0, bottomLatchFramesRemaining - 1)
        bottomConfirmedLatched = bottomReached || bottomLatchFramesRemaining > 0
        if !signal.hasElbowMeasurement {
          trackingLossDuringCommitPath += 1
          lostTrackingAtBottom = true
        }
        ascendingSignalGapFrames = min(ascendingSignalGapFrames + 1, ascendingSignalGraceFrames)
      } else {
        descendingFrames = max(0, descendingFrames - decayStep)
        bottomFrames = max(0, bottomFrames - decayStep)
        if bottomReached && ascendingFrames > 0 && blockedOverrun <= shortHoldWindow {
          ascendingSignalGapFrames = min(ascendingSignalGapFrames + 1, ascendingSignalGraceFrames)
        } else {
          ascendingFrames = max(0, ascendingFrames - decayStep)
          if ascendingFrames == 0 {
            ascendingSignalGapFrames = 0
          }
        }
      }

      if repRearmPending {
        let rearmHoldEligible =
          hasRenderableBodyForLogic &&
          qualityNotCollapsed &&
          (inActivePushupPhase || nearTopRecoveryGate || floorState)
        if rearmHoldEligible && rearmTopRecoveryDipGraceFramesRemaining > 0 {
          rearmTopRecoveryDipGraceFramesRemaining -= 1
        } else {
          topRecoveryGateGapFrames += 1
          if topRecoveryGateGapFrames > topRecoveryGateGraceFrames {
            topRecoveryFrames = max(0, topRecoveryFrames - 1)
          }
        }
      } else {
        topRecoveryFrames = 0
        topRecoveryGateGapFrames = 0
        rearmTopRecoveryDipGraceFramesRemaining = 0
        rearmDescendingSignalGraceFramesRemaining = 0
      }

      if bottomReached {
        bottomOcclusionFrames += 1
        let noProgressFramesLeft = descendingFrames == 0 && bottomFrames == 0 && ascendingFrames == 0
        let occlusionExpired = bottomOcclusionFrames > config.rep.bottomOcclusionGraceFrames
        if (noProgressFramesLeft || occlusionExpired) && !commitGraceActive {
          let bottomHoldBlockedReason = occlusionExpired ? "bottom_occlusion_timeout" : "cycle_drained_while_logic_blocked"
          if bottomReacquireHoldEligible && bottomReacquireHoldFramesRemaining > 0 {
            bottomReacquireHoldFramesRemaining -= 1
            bottomConfirmedLatched = true
            bottomLatchFramesRemaining = max(bottomLatchFramesRemaining, 1)
            commitPathActive = true
            commitPathGraceFramesRemaining = max(commitPathGraceFramesRemaining, 1)
            trackingLossGraceFramesRemaining = max(trackingLossGraceFramesRemaining, 1)
            currentBottomReacquireState = "hold_active"
            currentBottomBlockedReason = bottomHoldBlockedReason
          } else {
            bottomReached = false
            bottomConfirmedLatched = false
            bottomLatchFramesRemaining = 0
            bottomOcclusionFrames = 0
            commitPathActive = false
            commitPathGraceFramesRemaining = 0
            trackingLossGraceFramesRemaining = 0
            bottomReacquireHoldFramesRemaining = 0
            commitTopRecoveryFrames = 0
            currentBottomReacquireState = "expired"
            currentBottomBlockedReason = bottomHoldBlockedReason
            currentIdleResetReason = bottomHoldBlockedReason
            commitCancelledReason = currentIdleResetReason
            currentCommitCancelledReason = commitCancelledReason
            if repCommitAttemptCount > repCommitSuccessCount {
              repCommitBlockedCount += 1
            }
          }
        }
      } else {
        bottomOcclusionFrames = 0
      }

      currentBodyFound = hasRenderableBodyForLogic
      let trackingQualityGate = floorState ? config.rep.floorMinTrackingQualityToCount : config.rep.minTrackingQualityToCount
      currentTrackingQualityPass = quality.trackingQuality >= trackingQualityGate
      currentLogicQualityPass = quality.logicQuality >= config.rep.minLogicQualityToProgress
      currentBottomGate = bottomReached
      currentAscentGate = ascendingFrames >= config.rep.ascendingConfirmFrames
      currentRearmGate = !repRearmPending
      currentCountCommitReady = false
      currentCommitPathActive = commitPathActive
      lastFailedGate = "logicGate"
      currentCommitBlockedBy = commitPathActive ? nil : "logicGate"
      currentPendingCommitReason = commitPathActive ? "quality_dip_tolerated" : "logic_gate_blocked"
      whyRepDidNotCount = firstFinalBlocker ?? currentPendingCommitReason
      currentTopReady = topReadyLatched || isStartupReady()
      currentDescendingStarted = descendingFrames > 0 || state == .descending || commitPathActive
      currentBottomLatched = bottomReached || bottomConfirmedLatched
      currentAscendingStarted = ascendingFrames > 0 || didEnterAscending
      currentTopRecovered = commitTopRecoveryFrames > 0
      currentRepCommitted = false
      currentRearmReady = !repRearmPending
      currentRearmConfirmProgress = repRearmPending
        ? min(1, Double(topRecoveryFrames) / Double(max(1, config.rep.repRearmConfirmFrames)))
        : 1
      currentRepStateMachineState = resolveRepStateMachineState(repCounted: false)
      currentRepStateTransitionEvent = consumeRepStateMachineTransitionEvent(
        currentState: currentRepStateMachineState,
        frameIndex: frameIndex,
        timestamp: timestamp
      )

      return RepDetectionOutput(
        state: state,
        repCount: repCount,
        formEvidenceScore: signal.formEvidenceScore,
        blockedReasons: blockedReasons,
        repDebug: makeRepDebug(
          blockedReasons: blockedReasons,
          dominantEvidence: dominantEvidence,
          measuredEvidence: signal.measuredEvidence,
          structuralEvidence: signal.structuralEvidence,
          upperBodyEvidence: signal.upperBodyEvidence,
          shoulderVelocity: shoulderVelocity,
          torsoVelocity: torsoVelocity,
          topReferenceTorsoY: torsoTopReference,
          topReferenceShoulderY: shoulderTopReference,
          descendingSignal: descendingSignal,
          ascendingSignal: ascendingSignal,
          shoulderDownTravel: shoulderDownTravel,
          shoulderRecoveryToTop: shoulderRecoveryToTop,
          torsoDownTravel: torsoDownTravel,
          torsoRecoveryToTop: torsoRecoveryToTop,
          canProgress: canProgress,
          logicBlockedFrames: logicBlockedFrames,
          startupReady: isStartupReady(),
          startupTopEvidence: plankFrames,
          startupDescendBridgeUsed: startupDescendBridgeUsed,
          startBlockedReason: startupBlockedReason(),
          repRearmPending: repRearmPending,
          topRecoveryFrames: topRecoveryFrames,
          commitPathActive: currentCommitPathActive,
          idleResetReason: currentIdleResetReason,
          pendingCommitReason: currentPendingCommitReason,
          commitBlockedBy: currentCommitBlockedBy,
          cycleCoreReady: cycleCoreReady,
          strictCycleReady: strictCycleReady,
          floorFallbackCycleReady: floorFallbackCycleReady,
          motionTravelGate: motionTravelGate,
          topRecoveryGate: topRecoveryGate,
          torsoSupportReady: torsoSupportReady,
          shoulderSupportReady: shoulderSupportReady,
          countGatePassed: false,
          countGateBlocked: true,
          countGateBlockReason: "logic_gate_blocked"
        )
      )
    }

    if signal.hasElbowMeasurement, smoothedElbowAngle > config.rep.plankAngleMin, signal.torsoStability > minTorsoStability {
      plankFrames += 1
      topReadyLatched = true
      descendingFrames = max(0, descendingFrames - 1)
      bottomFrames = max(0, bottomFrames - 1)
      ascendingFrames = max(0, ascendingFrames - 1)
      if !bottomReached {
        repStartElbowAngle = smoothedElbowAngle
        repMinElbowAngle = smoothedElbowAngle
        repStartShoulderY = smoothedShoulderY
        repMaxShoulderY = smoothedShoulderY
        repStartTorsoY = smoothedTorsoY
        repMaxTorsoY = smoothedTorsoY
      }
      if floorState {
        if hasFloorBaselineTorsoY {
          floorBaselineTorsoY = floorBaselineTorsoY * 0.82 + smoothedTorsoY * 0.18
        } else {
          floorBaselineTorsoY = smoothedTorsoY
          hasFloorBaselineTorsoY = true
        }
      }
      if repRearmPending {
        topRecoveryFrames += 1
        rearmTopRecoveryDipGraceFramesRemaining = max(rearmTopRecoveryDipGraceFramesRemaining, 2)
        rearmDescendingSignalGraceFramesRemaining = max(rearmDescendingSignalGraceFramesRemaining, 1)
        if topRecoveryFrames >= config.rep.repRearmConfirmFrames {
          repRearmPending = false
          topRecoveryFrames = 0
          rearmTopRecoveryDipGraceFramesRemaining = 0
          rearmDescendingSignalGraceFramesRemaining = 0
        }
      } else {
        topRecoveryFrames = 0
        rearmTopRecoveryDipGraceFramesRemaining = 0
        rearmDescendingSignalGraceFramesRemaining = 0
      }
      if plankFrames >= config.rep.plankLockFrames {
        state = .plankLocked
      } else {
        state = .bodyFound
      }
    } else if state == .plankLocked
      || state == .descending
      || state == .ascending
      || bottomReached
      || (repCount == 0 && state == .bodyFound && plankFrames >= config.rep.startupDescendBridgeMinTopFrames)
    {
      if repCount == 0 && state == .bodyFound && plankFrames >= config.rep.startupDescendBridgeMinTopFrames {
        startupDescendBridgeUsed = true
      }
      let descendingByShoulder = shoulderVelocity < -config.rep.shoulderVelocityMinForDescent
      let ascendingByShoulder = shoulderVelocity > config.rep.shoulderVelocityMinForAscent
      let descendingByTorso = torsoVelocity < -config.rep.torsoVelocityMinForDescent
      let ascendingByTorso = torsoVelocity > config.rep.torsoVelocityMinForAscent
      // Primary progression depends on torso/shoulder motion for frontal stability.
      descendingSignal = descendingByTorso || descendingByShoulder
      ascendingSignal = ascendingByTorso || ascendingByShoulder
      let elbowAtBottom = signal.hasElbowMeasurement && smoothedElbowAngle < config.rep.bottomAngleMax
      let allowBottomOcclusion = bottomReached && bottomOcclusionFrames <= config.rep.bottomOcclusionGraceFrames

      if descendingSignal {
        if descendingFrames == 0 {
          if !topReadyLatched {
            topReadyLatched = isStartupReady()
          }
          cycleFramesSinceDescendingStart = 0
          if !attemptActive {
            attemptActive = true
            repsAttemptedEstimate += 1
            firstFinalBlocker = nil
          }
          repStartElbowAngle = max(previousSmoothedElbowAngle, smoothedElbowAngle)
          repMinElbowAngle = smoothedElbowAngle
          repStartShoulderY = smoothedShoulderY
          repMaxShoulderY = smoothedShoulderY
          repStartTorsoY = smoothedTorsoY
          repMaxTorsoY = smoothedTorsoY
        }
        descendingFrames += 1
        if signal.hasElbowMeasurement {
          repMinElbowAngle = min(repMinElbowAngle, smoothedElbowAngle)
        }
        // Historical names kept for compatibility: repMax* now track the deepest point,
        // which is the minimum Y reached during descent in this coordinate space.
        repMaxShoulderY = min(repMaxShoulderY, smoothedShoulderY)
        repMaxTorsoY = min(repMaxTorsoY, smoothedTorsoY)
        if descendingFrames >= config.rep.descentConfirmFrames {
          state = .descending
        }
      } else {
        descendingFrames = max(0, descendingFrames - 1)
      }

      torsoDownTravel = max(0, torsoTopReference - repMaxTorsoY)
      torsoRecoveryToTop = max(0, smoothedTorsoY - repMaxTorsoY)
      shoulderDownTravel = max(0, shoulderTopReference - repMaxShoulderY)
      shoulderRecoveryToTop = max(0, smoothedShoulderY - repMaxShoulderY)
      let bottomTravelReached =
        (
          torsoDownTravel >= config.rep.minTorsoDownTravelForBottom
            || shoulderDownTravel >= config.rep.minShoulderDownTravelForBottom
        )
      let fastBottomTravelReached =
        torsoDownTravel >= config.rep.minTorsoDownTravelForBottom * config.rep.fastBottomTravelMultiplier
        || shoulderDownTravel >= config.rep.minShoulderDownTravelForBottom * config.rep.fastBottomTravelMultiplier
      let descentConfirmed = state == .descending || descendingFrames >= config.rep.descentConfirmFrames
      let motionBottomCandidate = descentConfirmed && bottomTravelReached

      if elbowAtBottom || allowBottomOcclusion || motionBottomCandidate {
        if descendingSignal || state == .descending || bottomReached {
          bottomFrames += 1
        }
        if signal.hasElbowMeasurement {
          repMinElbowAngle = min(repMinElbowAngle, smoothedElbowAngle)
        }
        repMaxShoulderY = min(repMaxShoulderY, smoothedShoulderY)
        repMaxTorsoY = min(repMaxTorsoY, smoothedTorsoY)
        let fastBottomConfirm = motionBottomCandidate && fastBottomTravelReached
        if (bottomFrames >= config.rep.bottomConfirmFrames || fastBottomConfirm) && bottomTravelReached {
          let enteringBottomConfirmed = !bottomReached
          state = .bottomReached
          bottomReached = true
          if enteringBottomConfirmed && !bottomConfirmedLatched {
            bottomConfirmedCount += 1
          }
          bottomConfirmedLatched = true
          bottomLatchFramesRemaining = max(config.rep.bottomOcclusionGraceFrames, config.rep.ascendingConfirmFrames + 2)
          bottomReacquireHoldFramesRemaining = max(
            bottomReacquireHoldFramesRemaining,
            max(bottomReacquireHoldMinFrames, min(bottomReacquireHoldMaxFrames, config.rep.ascendingConfirmFrames + 1))
          )
          commitPathActive = true
          commitPathGraceFramesRemaining = max(config.rep.bottomOcclusionGraceFrames, config.rep.ascendingConfirmFrames + 1)
          trackingLossGraceFramesRemaining = max(config.rep.bottomOcclusionGraceFrames, config.rep.ascendingConfirmFrames + 2)
          currentBottomReacquireState = "primed"
          currentBottomBlockedReason = nil
          commitTopRecoveryFrames = 0
          if enteringBottomConfirmed {
            cycleFramesSinceBottomLatch = 0
            trackingLossDuringCommitPath = 0
            didEnterAscending = false
            didEnterTopRecovery = false
            commitCancelledReason = nil
            currentCommitCancelledReason = nil
            firstBlockingConditionAfterBottom = nil
            currentFirstBlockingConditionAfterBottom = nil
            repCommitAttemptCount += 1
          }
          currentPendingCommitReason = "awaiting_ascent"
        }
      } else if !bottomReached {
        if motionBottomCandidate && bottomFrames >= max(0, config.rep.bottomConfirmFrames - 1) {
          currentBottomNearMiss = true
        }
        bottomFrames = max(0, bottomFrames - 1)
      }

      if bottomReached && ascendingSignal {
        ascendingSignalGapFrames = 0
        ascendingFrames += 1
        commitPathActive = true
        if commitPathGraceFramesRemaining > 0 {
          commitPathGraceFramesRemaining -= 1
        }
        trackingLossGraceFramesRemaining = max(0, trackingLossGraceFramesRemaining - 1)
        bottomLatchFramesRemaining = max(0, bottomLatchFramesRemaining - 1)
        bottomConfirmedLatched = bottomReached || bottomLatchFramesRemaining > 0
        if ascendingFrames >= config.rep.ascendingConfirmFrames {
          if !didEnterAscending {
            didEnterAscending = true
            ascendingEnteredCount += 1
          }
          state = .ascending
        }
      } else if bottomReached {
        ascendingSignalGapFrames += 1
        if ascendingSignalGapFrames > ascendingSignalGraceFrames {
          if commitPathActive && commitPathGraceFramesRemaining > 0 {
            commitPathGraceFramesRemaining -= 1
          } else {
            ascendingFrames = max(0, ascendingFrames - 1)
          }
        }
      } else {
        ascendingSignalGapFrames = 0
      }

      let repTravel = max(0, repStartElbowAngle - repMinElbowAngle)
      let elbowComplete = signal.hasElbowMeasurement && smoothedElbowAngle > config.rep.repCompleteAngleMin
      let elbowSecondaryReady =
        !signal.hasElbowMeasurement ||
        elbowComplete ||
        repTravel >= config.rep.minRepAngleTravel * 0.55 ||
        repMinElbowAngle < config.rep.bottomAngleMax + 8
      cycleCoreReady =
        bottomReached &&
        ascendingFrames >= config.rep.ascendingConfirmFrames &&
        (
          torsoDownTravel >= config.rep.minTorsoDownTravelForBottom
            || shoulderDownTravel >= config.rep.minShoulderDownTravelForBottom
        )
      let trackingQualityGate = floorState ? config.rep.floorMinTrackingQualityToCount : config.rep.minTrackingQualityToCount
      let evidenceGate = floorState ? config.rep.floorMinMeasuredEvidence : config.rep.minMeasuredEvidence
      let torsoCycleReady =
        torsoDownTravel >= config.rep.minTorsoCycleTravel &&
        torsoRecoveryToTop >= config.rep.minTorsoRecoveryTravel
      let shoulderCycleReady =
        shoulderDownTravel >= config.rep.minShoulderCycleTravel &&
        shoulderRecoveryToTop >= config.rep.minShoulderRecoveryTravel
      torsoSupportReady =
        shoulderDownTravel >= config.rep.minShoulderCycleTravel * config.rep.crossAxisSupportFactor &&
        shoulderRecoveryToTop >= config.rep.minShoulderRecoveryTravel * config.rep.crossAxisSupportFactor
      shoulderSupportReady =
        torsoDownTravel >= config.rep.minTorsoCycleTravel * config.rep.crossAxisSupportFactor &&
        torsoRecoveryToTop >= config.rep.minTorsoRecoveryTravel * config.rep.crossAxisSupportFactor
      motionTravelGate =
        (torsoCycleReady && torsoSupportReady) ||
        (shoulderCycleReady && shoulderSupportReady)
      topRecoveryGate = smoothedTorsoY >= torsoTopReference - topRecoveryGateOffset
      if commitPathActive && bottomReached && ascendingFrames >= config.rep.ascendingConfirmFrames {
        if topRecoveryGate {
          commitTopRecoveryFrames += 1
          if !didEnterTopRecovery {
            didEnterTopRecovery = true
            topRecoveryEnteredCount += 1
          }
          currentPendingCommitReason = "top_recovery"
        } else {
          commitTopRecoveryFrames = 0
          currentPendingCommitReason = "awaiting_top_recovery"
        }
      } else if commitPathActive {
        commitTopRecoveryFrames = 0
        currentPendingCommitReason = "awaiting_ascent"
      } else {
        commitTopRecoveryFrames = 0
      }
      let commitTopRecoveryReady = commitTopRecoveryFrames > 0
      let qualityGate = quality.logicQuality >= config.rep.minLogicQualityToCount
      let trackingGate = quality.trackingQuality >= trackingQualityGate
      let evidenceReady = dominantEvidence >= evidenceGate && signal.measuredEvidence >= evidenceGate * 0.85
      let rearmSignalHealthy =
        quality.logicQuality >= max(0.2, config.rep.minLogicQualityToProgress * 0.78) &&
        quality.trackingQuality >= trackingQualityGate * 0.72 &&
        dominantEvidence >= evidenceGate * 0.64
      if repRearmPending {
        if (topRecoveryGate || nearTopRecoveryGate) && rearmSignalHealthy && hasRenderableBodyForLogic {
          rearmTopRecoveryDipGraceFramesRemaining = max(rearmTopRecoveryDipGraceFramesRemaining, 2)
          rearmDescendingSignalGraceFramesRemaining = max(rearmDescendingSignalGraceFramesRemaining, 1)
        }
      }
      strictCycleReady =
        cycleCoreReady &&
        motionTravelGate &&
        topRecoveryGate &&
        qualityGate &&
        trackingGate &&
        evidenceReady &&
        signal.torsoStability >= minTorsoStability &&
        signal.shoulderHipLineQuality >= minShoulderHipLineQuality
      floorFallbackCycleReady =
        floorState &&
        cycleCoreReady &&
        descendingFrames >= config.rep.descentConfirmFrames &&
        topRecoveryGate &&
        quality.logicQuality >= config.rep.minLogicQualityToProgress &&
        quality.trackingQuality >= trackingQualityGate * 0.9 &&
        dominantEvidence >= config.rep.floorMinMeasuredEvidence * 0.85 &&
        signal.measuredEvidence >= config.rep.floorMinMeasuredEvidence * 0.8 &&
        signal.torsoStability >= config.rep.floorMinTorsoStability * 0.9 &&
        signal.shoulderHipLineQuality >= config.rep.floorMinShoulderHipLineQuality * 0.85 &&
        (
          torsoCycleReady ||
          shoulderCycleReady ||
          (torsoSupportReady && shoulderSupportReady)
        )

      if repRearmPending {
        let descendingBlocksRearm: Bool = {
          guard descendingSignal else { return false }
          if rearmDescendingSignalGraceFramesRemaining > 0 && (topRecoveryGate || nearTopRecoveryGate) && rearmSignalHealthy {
            rearmDescendingSignalGraceFramesRemaining -= 1
            return false
          }
          return true
        }()
        let topRecoveryGateForRearm: Bool = {
          if topRecoveryGate { return true }
          if rearmTopRecoveryDipGraceFramesRemaining > 0 && nearTopRecoveryGate && rearmSignalHealthy && hasRenderableBodyForLogic {
            rearmTopRecoveryDipGraceFramesRemaining -= 1
            return true
          }
          return false
        }()
        if topRecoveryGateForRearm && !descendingBlocksRearm {
          topRecoveryGateGapFrames = 0
          topRecoveryFrames += 1
          if topRecoveryFrames >= config.rep.repRearmConfirmFrames {
            repRearmPending = false
            topRecoveryFrames = 0
            topRecoveryGateGapFrames = 0
            rearmTopRecoveryDipGraceFramesRemaining = 0
            rearmDescendingSignalGraceFramesRemaining = 0
          }
        } else {
          topRecoveryGateGapFrames += 1
          if topRecoveryGateGapFrames > topRecoveryGateGraceFrames {
            topRecoveryFrames = max(0, topRecoveryFrames - 1)
          }
          if descendingBlocksRearm {
            rearmDescendingSignalGraceFramesRemaining = 0
          }
        }
      } else {
        topRecoveryFrames = 0
        topRecoveryGateGapFrames = 0
        rearmTopRecoveryDipGraceFramesRemaining = 0
        rearmDescendingSignalGraceFramesRemaining = 0
      }

      topReady = topReadyLatched || isStartupReady()
      descendingStarted = descendingFrames >= config.rep.descentConfirmFrames || state == .descending || (commitPathActive && descendingFrames > 0)
      bottomLatched = bottomReached || bottomConfirmedLatched
      ascendingStarted = ascendingFrames > 0 || didEnterAscending
      topRecovered =
        bottomLatched &&
        ascendingStarted &&
        topRecoveryGate &&
        (
          commitTopRecoveryReady ||
          torsoRecoveryToTop >= config.rep.minTorsoRecoveryTravel * 0.7 ||
          shoulderRecoveryToTop >= config.rep.minShoulderRecoveryTravel * 0.7
        )
      rearmReady = !repRearmPending
      let commitSafetyGate =
        quality.logicQuality >= config.rep.minLogicQualityToProgress &&
        quality.trackingQuality >= trackingQualityGate * 0.82 &&
        dominantEvidence >= evidenceGate * 0.72
      countGatePassed = rearmReady && topReady && descendingStarted && bottomLatched && ascendingStarted && topRecovered && commitSafetyGate
      if countGatePassed {
        repCount += 1
        repCommitSuccessCount += 1
        repCommitted = true
        whyRepDidNotCount = nil
        lastSuccessfulGate = "countCommitReady"
        currentPendingCommitReason = nil
        currentCommitBlockedBy = nil
        currentIdleResetReason = nil
        commitCancelledReason = nil
        currentCommitCancelledReason = nil
        attemptActive = false
        firstFinalBlocker = nil
        firstBlockingConditionAfterBottom = nil
        currentFirstBlockingConditionAfterBottom = nil
        state = .repCounted
        bottomReached = false
        bottomConfirmedLatched = false
        bottomLatchFramesRemaining = 0
        plankFrames = config.rep.plankLockFrames
        descendingFrames = 0
        bottomFrames = 0
        ascendingFrames = 0
        repStartElbowAngle = smoothedElbowAngle
        repMinElbowAngle = smoothedElbowAngle
        repStartShoulderY = smoothedShoulderY
        repMaxShoulderY = smoothedShoulderY
        repStartTorsoY = smoothedTorsoY
        repMaxTorsoY = smoothedTorsoY
        bottomOcclusionFrames = 0
        repRearmPending = true
        topRecoveryFrames = 0
        rearmTopRecoveryDipGraceFramesRemaining = 2
        rearmDescendingSignalGraceFramesRemaining = 1
        ascendingSignalGapFrames = 0
        topRecoveryGateGapFrames = 0
        commitPathActive = false
        commitPathGraceFramesRemaining = 0
        trackingLossGraceFramesRemaining = 0
        bottomReacquireHoldFramesRemaining = 0
        commitTopRecoveryFrames = 0
        currentBottomReacquireState = "inactive"
        cycleFramesSinceDescendingStart = 0
        cycleFramesSinceBottomLatch = 0
        topReadyLatched = false
        if floorState {
          if hasFloorBaselineTorsoY {
            floorBaselineTorsoY = floorBaselineTorsoY * 0.8 + smoothedTorsoY * 0.2
          } else {
            floorBaselineTorsoY = smoothedTorsoY
            hasFloorBaselineTorsoY = true
          }
        }
      } else if strictCycleReady && !elbowSecondaryReady {
        blockedReasons.append("elbow_secondary_unconfirmed")
      }

      if !countGatePassed {
        if descendingStarted && !bottomLatched {
          cycleFramesSinceDescendingStart += 1
        } else if !descendingStarted {
          cycleFramesSinceDescendingStart = 0
        }
        if bottomLatched && commitPathActive {
          cycleFramesSinceBottomLatch += 1
        } else if !bottomLatched {
          cycleFramesSinceBottomLatch = 0
        }
        let gateReason = makeV1CommitBlockReason(
          topReady: topReady,
          descendingStarted: descendingStarted,
          bottomLatched: bottomLatched,
          ascendingStarted: ascendingStarted,
          topRecovered: topRecovered,
          rearmReady: rearmReady,
          commitSafetyGate: commitSafetyGate
        )
        if gateReason != "gate_not_applicable" {
          countGateBlocked = true
          countGateBlockReason = gateReason
          lastFailedGate = gateReason
          currentCommitBlockedBy = commitBlocker(gateReason: gateReason)
          if commitPathActive {
            currentPendingCommitReason = gateReason
          }
          if currentFirstBlockingConditionAfterBottom == nil && commitPathActive {
            currentFirstBlockingConditionAfterBottom = gateReason
            firstBlockingConditionAfterBottom = gateReason
          }
          if firstFinalBlocker == nil && attemptActive {
            firstFinalBlocker = gateReason
          }
          whyRepDidNotCount = firstFinalBlocker ?? gateReason
          if !blockedReasons.contains(gateReason) {
            blockedReasons.append(gateReason)
          }
        }
        let noRecoveryTimeoutFrames = max(14, config.rep.bottomOcclusionGraceFrames + config.rep.ascendingConfirmFrames + 6)
        if bottomLatched && !topRecovered && cycleFramesSinceBottomLatch > noRecoveryTimeoutFrames {
          abortCurrentCycle(reason: "no_recovery_within_timeout")
          countGateBlocked = true
          countGateBlockReason = "no_recovery_within_timeout"
          if !blockedReasons.contains("no_recovery_within_timeout") {
            blockedReasons.append("no_recovery_within_timeout")
          }
        } else if descendingStarted && !bottomLatched {
          let collapseTimeoutFrames = max(20, config.rep.descentConfirmFrames * 10)
          if cycleFramesSinceDescendingStart > collapseTimeoutFrames && !descendingSignal {
            abortCurrentCycle(reason: "movement_collapsed")
            countGateBlocked = true
            countGateBlockReason = "movement_collapsed"
            if !blockedReasons.contains("movement_collapsed") {
              blockedReasons.append("movement_collapsed")
            }
          }
        }
      }
    } else {
      plankFrames = max(0, plankFrames - 1)
      descendingFrames = max(0, descendingFrames - 1)
      bottomFrames = max(0, bottomFrames - 1)
      ascendingFrames = max(0, ascendingFrames - 1)
      if !bottomReached {
        bottomOcclusionFrames = 0
        bottomLatchFramesRemaining = max(0, bottomLatchFramesRemaining - 1)
        bottomConfirmedLatched = bottomLatchFramesRemaining > 0
      }
      if repRearmPending {
        let rearmHoldEligible =
          hasRenderableBodyForLogic &&
          qualityNotCollapsed &&
          (inActivePushupPhase || nearTopRecoveryGate || floorState)
        if rearmHoldEligible && rearmTopRecoveryDipGraceFramesRemaining > 0 {
          rearmTopRecoveryDipGraceFramesRemaining -= 1
        } else {
          topRecoveryGateGapFrames += 1
          if topRecoveryGateGapFrames > topRecoveryGateGraceFrames {
            topRecoveryFrames = max(0, topRecoveryFrames - 1)
          }
        }
      } else {
        topRecoveryFrames = 0
        topRecoveryGateGapFrames = 0
        rearmTopRecoveryDipGraceFramesRemaining = 0
        rearmDescendingSignalGraceFramesRemaining = 0
      }
      ascendingSignalGapFrames = 0
      state = .bodyFound
      let cycleInactive = descendingFrames == 0 && bottomFrames == 0 && ascendingFrames == 0 && !bottomReached
      if cycleInactive {
        commitPathActive = false
        commitPathGraceFramesRemaining = 0
        trackingLossGraceFramesRemaining = 0
        bottomReacquireHoldFramesRemaining = 0
        commitTopRecoveryFrames = 0
        currentBottomReacquireState = "inactive"
        bottomConfirmedLatched = false
        bottomLatchFramesRemaining = 0
        cycleFramesSinceDescendingStart = 0
        cycleFramesSinceBottomLatch = 0
      }
      if attemptActive && cycleInactive {
        abortCurrentCycle(reason: firstFinalBlocker ?? lastFailedGate ?? "motion_pattern_invalid")
      }
    }

    topReady = topReadyLatched || isStartupReady()
    descendingStarted = descendingFrames > 0 || state == .descending || commitPathActive
    bottomLatched = bottomReached || bottomConfirmedLatched
    ascendingStarted = ascendingFrames > 0 || didEnterAscending
    topRecovered = topRecoveryGate && bottomLatched && ascendingStarted && commitTopRecoveryFrames > 0
    rearmReady = !repRearmPending
    currentBodyFound = hasRenderableBodyForLogic
    let trackingQualityGate = floorState ? config.rep.floorMinTrackingQualityToCount : config.rep.minTrackingQualityToCount
    currentTrackingQualityPass = quality.trackingQuality >= trackingQualityGate
    currentLogicQualityPass = quality.logicQuality >= config.rep.minLogicQualityToProgress
    currentBottomGate = bottomReached
    currentAscentGate = ascendingFrames >= config.rep.ascendingConfirmFrames
    currentRearmGate = !repRearmPending
    currentCountCommitReady = countGatePassed
    currentCommitPathActive = commitPathActive
    currentCommitCancelledReason = commitCancelledReason
    currentFirstBlockingConditionAfterBottom = firstBlockingConditionAfterBottom
    if currentRearmGate {
      lastSuccessfulGate = "rearmGate"
    }
    if repRearmPending {
      let topRecoveryBlocked = !topRecoveryGate && rearmTopRecoveryDipGraceFramesRemaining == 0
      if topRecoveryBlocked {
        currentRearmBlockedReason = "top_recovery_gate_not_met"
        currentRearmMissingCondition = "top_recovery_gate"
      } else if descendingSignal && rearmDescendingSignalGraceFramesRemaining == 0 {
        currentRearmBlockedReason = "descending_not_cleared"
        currentRearmMissingCondition = "stop_descending"
      } else if !currentTrackingQualityPass || !currentLogicQualityPass {
        currentRearmBlockedReason = "rearm_quality_dip"
        currentRearmMissingCondition = "stabilize_quality"
      } else {
        currentRearmBlockedReason = "rearm_confirming"
        currentRearmMissingCondition = "confirm_top_recovery"
      }
    } else {
      currentRearmBlockedReason = nil
      currentRearmMissingCondition = nil
    }
    if currentCommitBlockedBy == nil && repRearmPending {
      currentCommitBlockedBy = "rearmGate"
    }
    if currentPendingCommitReason == nil && commitPathActive {
      if ascendingFrames < config.rep.ascendingConfirmFrames {
        currentPendingCommitReason = "awaiting_ascent"
      } else if commitTopRecoveryFrames == 0 {
        currentPendingCommitReason = "awaiting_top_recovery"
      } else {
        currentPendingCommitReason = "awaiting_rep_commit"
      }
    }
    currentTopReady = topReady
    currentDescendingStarted = descendingStarted
    currentBottomLatched = bottomLatched
    currentAscendingStarted = ascendingStarted
    currentTopRecovered = topRecovered
    currentRepCommitted = repCommitted
    currentRearmReady = rearmReady
    currentRearmConfirmProgress = repRearmPending
      ? min(1, Double(topRecoveryFrames) / Double(max(1, config.rep.repRearmConfirmFrames)))
      : 1
    if currentResetReason == nil {
      currentResetReason = currentIdleResetReason
    }
    currentRepStateMachineState = resolveRepStateMachineState(repCounted: state == .repCounted)
    if !commitPathActive {
      currentPendingCommitReason = nil
      if currentRepStateMachineState == "idle" && currentIdleResetReason == nil && previousRepStateMachineStateForDebugEvent != "idle" {
        currentIdleResetReason = "cycle_reset_to_idle"
      }
    }
    currentRepStateTransitionEvent = consumeRepStateMachineTransitionEvent(
      currentState: currentRepStateMachineState,
      frameIndex: frameIndex,
      timestamp: timestamp
    )

    return RepDetectionOutput(
      state: state,
      repCount: repCount,
      formEvidenceScore: signal.formEvidenceScore,
      blockedReasons: blockedReasons,
      repDebug: makeRepDebug(
        blockedReasons: blockedReasons,
        dominantEvidence: dominantEvidence,
        measuredEvidence: signal.measuredEvidence,
        structuralEvidence: signal.structuralEvidence,
        upperBodyEvidence: signal.upperBodyEvidence,
        shoulderVelocity: shoulderVelocity,
        torsoVelocity: torsoVelocity,
        topReferenceTorsoY: torsoTopReference,
        topReferenceShoulderY: shoulderTopReference,
        descendingSignal: descendingSignal,
        ascendingSignal: ascendingSignal,
        shoulderDownTravel: shoulderDownTravel,
        shoulderRecoveryToTop: shoulderRecoveryToTop,
        torsoDownTravel: torsoDownTravel,
        torsoRecoveryToTop: torsoRecoveryToTop,
        canProgress: canProgress,
        logicBlockedFrames: logicBlockedFrames,
        startupReady: isStartupReady(),
        startupTopEvidence: plankFrames,
        startupDescendBridgeUsed: startupDescendBridgeUsed,
        startBlockedReason: startupBlockedReason(),
        repRearmPending: repRearmPending,
        topRecoveryFrames: topRecoveryFrames,
        commitPathActive: currentCommitPathActive,
        idleResetReason: currentIdleResetReason,
        pendingCommitReason: currentPendingCommitReason,
        commitBlockedBy: currentCommitBlockedBy,
        cycleCoreReady: cycleCoreReady,
        strictCycleReady: strictCycleReady,
        floorFallbackCycleReady: floorFallbackCycleReady,
        motionTravelGate: motionTravelGate,
        topRecoveryGate: topRecoveryGate,
        torsoSupportReady: torsoSupportReady,
        shoulderSupportReady: shoulderSupportReady,
        countGatePassed: countGatePassed,
        countGateBlocked: countGateBlocked,
        countGateBlockReason: countGateBlockReason
      )
    )
  }

  private func makeRepDebug(
    blockedReasons: [String],
    dominantEvidence: Double,
    measuredEvidence: Double,
    structuralEvidence: Double,
    upperBodyEvidence: Double,
    shoulderVelocity: CGFloat,
    torsoVelocity: CGFloat,
    topReferenceTorsoY: CGFloat,
    topReferenceShoulderY: CGFloat,
    descendingSignal: Bool,
    ascendingSignal: Bool,
    shoulderDownTravel: CGFloat,
    shoulderRecoveryToTop: CGFloat,
    torsoDownTravel: CGFloat,
    torsoRecoveryToTop: CGFloat,
    canProgress: Bool,
    logicBlockedFrames: Int,
    startupReady: Bool,
    startupTopEvidence: Int,
    startupDescendBridgeUsed: Bool,
    startBlockedReason: String?,
    repRearmPending: Bool,
    topRecoveryFrames: Int,
    commitPathActive: Bool,
    idleResetReason: String?,
    pendingCommitReason: String?,
    commitBlockedBy: String?,
    cycleCoreReady: Bool,
    strictCycleReady: Bool,
    floorFallbackCycleReady: Bool,
    motionTravelGate: Bool,
    topRecoveryGate: Bool,
    torsoSupportReady: Bool,
    shoulderSupportReady: Bool,
    countGatePassed: Bool,
    countGateBlocked: Bool,
    countGateBlockReason: String?
  ) -> PushupRepDebug {
    let repStateTransition = currentRepStateTransitionEvent
    let topRecoveryGateForRearm = topRecoveryGate
    let framesUntilRearm = repRearmPending ? max(0, config.rep.repRearmConfirmFrames - topRecoveryFrames) : 0
    let bottomHoldActive = bottomConfirmedLatched &&
      (
        bottomReached ||
          trackingLossGraceFramesRemaining > 0 ||
          bottomLatchFramesRemaining > 0 ||
          bottomReacquireHoldFramesRemaining > 0 ||
          currentBottomReacquireState == "hold_active"
      )
    return PushupRepDebug(
      frameIndex: currentFrameIndex,
      timestampSeconds: currentTimestampSeconds,
      currentRepState: state.rawValue,
      repStateMachineState: currentRepStateMachineState,
      repStateTransitionEvent: repStateTransition,
      smoothedElbowAngle: Double(smoothedElbowAngle),
      repMinElbowAngle: Double(repMinElbowAngle),
      rawTorsoY: Double(currentRawTorsoY),
      rawShoulderY: Double(currentRawShoulderY),
      smoothedTorsoY: Double(smoothedTorsoY),
      smoothedShoulderY: Double(smoothedShoulderY),
      rawTorsoVelocity: Double(currentRawTorsoVelocity),
      rawShoulderVelocity: Double(currentRawShoulderVelocity),
      smoothedTorsoVelocity: Double(torsoVelocity),
      smoothedShoulderVelocity: Double(shoulderVelocity),
      topReferenceTorsoY: Double(topReferenceTorsoY),
      topReferenceShoulderY: Double(topReferenceShoulderY),
      shoulderVelocity: Double(shoulderVelocity),
      torsoVelocity: Double(torsoVelocity),
      descendingSignal: descendingSignal,
      ascendingSignal: ascendingSignal,
      shoulderDownTravel: Double(shoulderDownTravel),
      shoulderRecoveryToTop: Double(shoulderRecoveryToTop),
      torsoDownTravel: Double(torsoDownTravel),
      torsoRecoveryToTop: Double(torsoRecoveryToTop),
      descendingFrames: descendingFrames,
      bottomCandidateFrames: bottomFrames,
      bottomConfirmedFrames: bottomReached ? bottomFrames : 0,
      bottomFrames: bottomFrames,
      ascendingFrames: ascendingFrames,
      ascentFrames: ascendingFrames,
      bottomReached: bottomReached,
      bottomConfirmedLatched: bottomConfirmedLatched,
      bottomNearMiss: currentBottomNearMiss,
      minDescendingFramesRequired: config.rep.descentConfirmFrames,
      minBottomFramesRequired: config.rep.bottomConfirmFrames,
      minAscendingFramesRequired: config.rep.ascendingConfirmFrames,
      minTopRecoveryFramesRequired: config.rep.repRearmConfirmFrames,
      dominantEvidence: dominantEvidence,
      measuredEvidence: measuredEvidence,
      structuralEvidence: structuralEvidence,
      upperBodyEvidence: upperBodyEvidence,
      weakestLandmark: currentWeakestLandmark,
      weakestLandmarkConfidence: currentWeakestLandmarkConfidence,
      missingLandmarks: currentMissingLandmarks,
      landmarkQuality: currentLandmarkQuality,
      blockedReasons: blockedReasons,
      canProgress: canProgress,
      logicBlockedFrames: logicBlockedFrames,
      startupReady: startupReady,
      startupTopEvidence: startupTopEvidence,
      startupDescendBridgeUsed: startupDescendBridgeUsed,
      startBlockedReason: startBlockedReason,
      repRearmPending: repRearmPending,
      topRecoveryFrames: topRecoveryFrames,
      commitPathActive: commitPathActive,
      commitCancelledReason: currentCommitCancelledReason,
      idleResetReason: idleResetReason,
      pendingCommitReason: pendingCommitReason,
      commitBlockedBy: commitBlockedBy,
      topReady: currentTopReady,
      descendingStarted: currentDescendingStarted,
      bottomLatched: currentBottomLatched,
      ascendingStarted: currentAscendingStarted,
      topRecovered: currentTopRecovered,
      repCommitted: currentRepCommitted,
      rearmReady: currentRearmReady,
      resetReason: currentResetReason,
      timeoutOrAbortReason: currentTimeoutOrAbortReason,
      firstBlockingConditionAfterBottom: currentFirstBlockingConditionAfterBottom,
      lostTrackingAtBottom: lostTrackingAtBottom,
      trackingLossDuringCommitPath: trackingLossDuringCommitPath,
      trackingLossGraceFramesRemaining: trackingLossGraceFramesRemaining,
      bottomHoldActive: bottomHoldActive,
      bottomReacquireState: currentBottomReacquireState,
      bottomSupportAnchors: currentBottomSupportAnchors,
      bottomBlockedReason: currentBottomBlockedReason,
      didEnterAscending: didEnterAscending,
      didEnterTopRecovery: didEnterTopRecovery,
      rearmBlockedReason: currentRearmBlockedReason,
      framesUntilRearm: framesUntilRearm,
      rearmConfirmProgress: currentRearmConfirmProgress,
      rearmMissingCondition: currentRearmMissingCondition,
      whyRepDidNotCount: whyRepDidNotCount,
      firstFinalBlocker: firstFinalBlocker,
      lastFailedGate: lastFailedGate,
      lastSuccessfulGate: lastSuccessfulGate,
      bodyFound: currentBodyFound,
      trackingQualityPass: currentTrackingQualityPass,
      logicQualityPass: currentLogicQualityPass,
      bottomGate: currentBottomGate,
      ascentGate: currentAscentGate,
      rearmGate: currentRearmGate,
      cycleCoreReady: cycleCoreReady,
      strictCycleReady: strictCycleReady,
      floorFallbackCycleReady: floorFallbackCycleReady,
      motionTravelGate: motionTravelGate,
      topRecoveryGate: topRecoveryGateForRearm,
      countCommitReady: currentCountCommitReady,
      torsoSupportReady: torsoSupportReady,
      shoulderSupportReady: shoulderSupportReady,
      countGatePassed: countGatePassed,
      countGateBlocked: countGateBlocked,
      countGateBlockReason: countGateBlockReason,
      stateTransitionEvent: consumeStateTransitionEvent(currentState: state),
      repsAttemptedEstimate: repsAttemptedEstimate,
      repsCommitted: repCount,
      repsBlockedByBottom: repsBlockedByBottom,
      repsBlockedByTopRecovery: repsBlockedByTopRecovery,
      repsBlockedByRearm: repsBlockedByRearm,
      repsBlockedByTrackingLoss: repsBlockedByTrackingLoss,
      repsBlockedByTravel: repsBlockedByTravel,
      repsBlockedByQuality: repsBlockedByQuality,
      bottomConfirmedCount: bottomConfirmedCount,
      ascendingEnteredCount: ascendingEnteredCount,
      topRecoveryEnteredCount: topRecoveryEnteredCount,
      repCommitAttemptCount: repCommitAttemptCount,
      repCommitSuccessCount: repCommitSuccessCount,
      repCommitBlockedCount: repCommitBlockedCount
    )
  }

  private func resolveRepStateMachineState(repCounted: Bool) -> String {
    if repCounted {
      return "rep_committed"
    }
    if repRearmPending {
      return "rearm_pending"
    }
    if commitPathActive && (bottomReached || bottomConfirmedLatched) && ascendingFrames >= config.rep.ascendingConfirmFrames && commitTopRecoveryFrames > 0 {
      return "top_recovery"
    }
    if topRecoveryFrames > 0 {
      return "top_recovery"
    }
    if state == .ascending || ((bottomReached || bottomConfirmedLatched) && ascendingFrames > 0) {
      return "ascending"
    }
    if bottomReached || bottomConfirmedLatched {
      return "bottom_confirmed"
    }
    if bottomFrames > 0 {
      return "bottom_candidate"
    }
    if state == .descending || descendingFrames > 0 {
      return "descending"
    }
    return "idle"
  }

  private func consumeRepStateMachineTransitionEvent(
    currentState: String,
    frameIndex: Int,
    timestamp: TimeInterval
  ) -> String? {
    let previousState = previousRepStateMachineStateForDebugEvent
    previousRepStateMachineStateForDebugEvent = currentState
    guard previousState != currentState else { return nil }
    return "\(previousState)->\(currentState)@f\(frameIndex)@t\(String(format: "%.3f", timestamp))"
  }

  private func commitBlocker(gateReason: String) -> String {
    if gateReason == "rearm_pending" { return "rearmGate" }
    if gateReason.contains("tracking") { return "trackingGate" }
    if gateReason.contains("quality") || gateReason.contains("evidence") || gateReason.contains("safety") { return "qualityGate" }
    if gateReason.contains("timeout") || gateReason.contains("collapsed") || gateReason.contains("invalid") { return "abortGate" }
    return "phaseGate"
  }

  private func makeV1CommitBlockReason(
    topReady: Bool,
    descendingStarted: Bool,
    bottomLatched: Bool,
    ascendingStarted: Bool,
    topRecovered: Bool,
    rearmReady: Bool,
    commitSafetyGate: Bool
  ) -> String {
    if !rearmReady { return "rearm_pending" }
    if !topReady { return "top_not_ready" }
    if !descendingStarted { return "descending_not_started" }
    if !bottomLatched { return "bottom_not_latched" }
    if !ascendingStarted { return "ascending_not_started" }
    if !topRecovered { return "top_not_recovered" }
    if !commitSafetyGate { return "commit_safety_low" }
    return "gate_not_applicable"
  }

  private func abortCurrentCycle(reason: String) {
    currentIdleResetReason = reason
    currentResetReason = reason
    currentTimeoutOrAbortReason = reason
    commitCancelledReason = reason
    currentCommitCancelledReason = reason
    currentCommitBlockedBy = "abortGate"
    currentPendingCommitReason = nil
    lastFailedGate = reason
    if attemptActive {
      let finalReason = firstFinalBlocker ?? reason
      whyRepDidNotCount = finalReason
      recordAttemptBlocked(reason: finalReason)
      repCommitBlockedCount += 1
      attemptActive = false
      firstFinalBlocker = nil
    } else {
      whyRepDidNotCount = reason
    }
    firstBlockingConditionAfterBottom = nil
    currentFirstBlockingConditionAfterBottom = nil
    state = .bodyFound
    descendingFrames = 0
    bottomFrames = 0
    ascendingFrames = 0
    bottomReached = false
    bottomConfirmedLatched = false
    bottomLatchFramesRemaining = 0
    bottomOcclusionFrames = 0
    ascendingSignalGapFrames = 0
    commitPathActive = false
    commitPathGraceFramesRemaining = 0
    trackingLossGraceFramesRemaining = 0
    bottomReacquireHoldFramesRemaining = 0
    commitTopRecoveryFrames = 0
    currentBottomReacquireState = "inactive"
    didEnterAscending = false
    didEnterTopRecovery = false
    topReadyLatched = false
    cycleFramesSinceDescendingStart = 0
    cycleFramesSinceBottomLatch = 0
  }

  private func recordAttemptBlocked(reason: String) {
    if reason.contains("top_recovery") || reason.contains("recovery_insufficient") {
      repsBlockedByTopRecovery += 1
      return
    }
    if reason.contains("rearm") {
      repsBlockedByRearm += 1
      return
    }
    if reason.contains("travel") || reason.contains("_down_insufficient") {
      repsBlockedByTravel += 1
      return
    }
    if reason.contains("tracking") || reason == "body_not_found" {
      repsBlockedByTrackingLoss += 1
      return
    }
    if reason.contains("quality") || reason.contains("evidence") || reason.contains("unstable") || reason.contains("asymmetry") {
      repsBlockedByQuality += 1
      return
    }
    repsBlockedByBottom += 1
  }

  private func buildLandmarkDiagnostics(
    joints: [PushlyJointName: TrackedJoint]
  ) -> (landmarkQuality: [String: [String: Any]], weakestLandmark: String?, weakestConfidence: Double, missingLandmarks: [String]) {
    let points: [(String, TrackedJoint?)] = [
      ("leftShoulder", joints[.leftShoulder]),
      ("rightShoulder", joints[.rightShoulder]),
      ("leftElbow", joints[.leftElbow]),
      ("rightElbow", joints[.rightElbow]),
      ("leftWrist", joints[.leftWrist]),
      ("rightWrist", joints[.rightWrist])
    ]

    var output: [String: [String: Any]] = [:]
    var weakestName: String?
    var weakestScore = Double.greatestFiniteMagnitude
    var missingLandmarks: [String] = []

    for (name, joint) in points {
      let confidence = Double(joint?.renderConfidence ?? 0)
      let presence = Double(joint?.presence ?? 0)
      let usable = joint?.isLogicUsable ?? false
      output[name] = [
        "confidence": confidence,
        "presence": presence,
        "usable": usable
      ]
      if confidence < weakestScore {
        weakestScore = confidence
        weakestName = name
      }
      if joint == nil || !usable {
        missingLandmarks.append(name)
      }
    }

    let leftHip = joints[.leftHip]
    let rightHip = joints[.rightHip]
    let torsoConfidence = Double(((leftHip?.renderConfidence ?? 0) + (rightHip?.renderConfidence ?? 0)) / 2)
    let torsoPresence = Double(((leftHip?.presence ?? 0) + (rightHip?.presence ?? 0)) / 2)
    let torsoUsable = (leftHip?.isLogicUsable ?? false) || (rightHip?.isLogicUsable ?? false)
    output["torsoAnchor"] = [
      "confidence": torsoConfidence,
      "presence": torsoPresence,
      "usable": torsoUsable
    ]
    if torsoConfidence < weakestScore {
      weakestScore = torsoConfidence
      weakestName = "torsoAnchor"
    }
    if !torsoUsable {
      missingLandmarks.append("torsoAnchor")
    }

    let resolvedWeakestScore = weakestScore.isFinite ? weakestScore : 0
    return (output, weakestName, resolvedWeakestScore, missingLandmarks)
  }

  private func consumeStateTransitionEvent(currentState: PushupState) -> String? {
    let previousState = previousStateForDebugEvent
    previousStateForDebugEvent = currentState
    guard currentState != previousState else { return nil }

    switch currentState {
    case .bodyFound, .trackingAssisted, .bottomReached, .ascending, .repCounted:
      return currentState.rawValue
    default:
      return nil
    }
  }

  private func isStartupReady() -> Bool {
    state == .plankLocked
      || (repCount == 0 && state == .bodyFound && plankFrames >= config.rep.startupDescendBridgeMinTopFrames)
  }

  private func startupBlockedReason() -> String? {
    guard repCount == 0, !isStartupReady() else { return nil }
    return "startup_top_evidence_insufficient"
  }

  private func computeSignal(joints: [PushlyJointName: TrackedJoint]) -> (
    elbowAngle: CGFloat,
    hasElbowMeasurement: Bool,
    renderableArmCount: Int,
    bilateralElbowAngleDelta: CGFloat,
    shoulderY: CGFloat,
    torsoY: CGFloat,
    torsoStability: Double,
    shoulderHipLineQuality: Double,
    measuredEvidence: Double,
    structuralEvidence: Double,
    upperBodyEvidence: Double,
    formEvidenceScore: Double,
    hasRenderableBody: Bool,
    pushupFloorState: Bool
  ) {
    let shoulderPair = bestPair(joints[.leftShoulder], joints[.rightShoulder])
    let hipPair = bestPair(joints[.leftHip], joints[.rightHip])
    let anklePair = bestPair(joints[.leftAnkle], joints[.rightAnkle], fallback: bestPair(joints[.leftKnee], joints[.rightKnee]))
    let shoulderMid = midpoint(joints[.leftShoulder]?.smoothedPosition, joints[.rightShoulder]?.smoothedPosition)
    let pushupFloorState = isLikelyPushupFloorState(joints: joints, shoulderMid: shoulderMid)

    let leftArm = arm(shoulder: .leftShoulder, elbow: .leftElbow, wrist: .leftWrist, joints: joints)
    let rightArm = arm(shoulder: .rightShoulder, elbow: .rightElbow, wrist: .rightWrist, joints: joints)
    let bestRenderableArm = bestArm(joints: joints)
    let leftElbowAngle = leftArm.map { angle(a: $0.shoulder.smoothedPosition, b: $0.elbow.smoothedPosition, c: $0.wrist.smoothedPosition) }
    let rightElbowAngle = rightArm.map { angle(a: $0.shoulder.smoothedPosition, b: $0.elbow.smoothedPosition, c: $0.wrist.smoothedPosition) }
    let elbowAngles = [leftElbowAngle, rightElbowAngle].compactMap { $0 }
    let hasElbowMeasurement = !elbowAngles.isEmpty
    let elbowAngle = hasElbowMeasurement
      ? elbowAngles.reduce(CGFloat(0), +) / CGFloat(elbowAngles.count)
      : 180
    let renderableArmCount = elbowAngles.count
    let bilateralElbowAngleDelta: CGFloat
    if let leftElbowAngle, let rightElbowAngle {
      bilateralElbowAngleDelta = abs(leftElbowAngle - rightElbowAngle)
    } else {
      bilateralElbowAngleDelta = 0
    }

    let shoulderY = shoulderMid?.y ?? shoulderPair?.smoothedPosition.y ?? bestRenderableArm?.shoulder.smoothedPosition.y ?? 0.5
    let hipMid = midpoint(joints[.leftHip]?.smoothedPosition, joints[.rightHip]?.smoothedPosition)
    let torsoY = midpoint(shoulderMid, hipMid)?.y ?? shoulderY

    let shoulderHipLineQuality: Double = {
      guard let shoulderMid else { return 0.18 }
      guard let hipMid else {
        if bestRenderableArm != nil {
          return pushupFloorState ? 0.42 : 0.3
        }
        return pushupFloorState ? 0.44 : 0.26
      }
      let segmentLength = distance(shoulderMid, hipMid)
      let lengthScore = min(1, max(0, Double((segmentLength - 0.06) / 0.24)))
      let confidenceScore = max(
        Double(bestPair(joints[.leftShoulder], joints[.rightShoulder])?.renderConfidence ?? 0),
        Double(bestPair(joints[.leftHip], joints[.rightHip])?.renderConfidence ?? 0)
      )
      return min(1, max(0.2, lengthScore * 0.62 + confidenceScore * 0.38))
    }()

    let torsoStability: Double
    if let shoulder = shoulderPair, let hip = hipPair, let ankle = anklePair {
      let bodyAngle = angle(a: shoulder.smoothedPosition, b: hip.smoothedPosition, c: ankle.smoothedPosition)
      torsoStability = max(0, min(1, 1 - Double(abs(bodyAngle - 180)) / 44.0))
    } else if pushupFloorState, shoulderPair != nil, hipPair != nil {
      torsoStability = 0.76
    } else if shoulderPair != nil && hipPair != nil {
      torsoStability = 0.54
    } else {
      torsoStability = 0.32
    }

    let coreEvidenceJoints: [PushlyJointName] = [
      .leftShoulder, .rightShoulder,
      .leftElbow, .rightElbow,
      .leftWrist, .rightWrist,
      .leftHip, .rightHip
    ]
    let measuredEvidence = measuredEvidenceScore(joints: joints, candidates: coreEvidenceJoints, floorState: pushupFloorState)
    let structuralEvidence = structuralEvidenceScore(joints: joints, floorState: pushupFloorState)
    let upperBodyEvidence = measuredEvidenceScore(
      joints: joints,
      candidates: [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist],
      floorState: pushupFloorState
    )

    let evidence = max(measuredEvidence, structuralEvidence, upperBodyEvidence)
    let formEvidenceScore = max(
      0.16,
      min(
        0.99,
        torsoStability * 0.42
          + shoulderHipLineQuality * 0.28
          + evidence * 0.3
      )
    )
    let hasRenderableBody =
      joints.values.filter(\.isRenderable).count >= 4 ||
      (pushupFloorState && shoulderPair != nil && (bestRenderableArm != nil || hipPair != nil))

    return (
      elbowAngle,
      hasElbowMeasurement,
      renderableArmCount,
      bilateralElbowAngleDelta,
      shoulderY,
      torsoY,
      torsoStability,
      shoulderHipLineQuality,
      measuredEvidence,
      structuralEvidence,
      upperBodyEvidence,
      formEvidenceScore,
      hasRenderableBody,
      pushupFloorState
    )
  }

  private func bestPair(_ a: TrackedJoint?, _ b: TrackedJoint?, fallback: TrackedJoint? = nil) -> TrackedJoint? {
    switch (a, b) {
    case let (.some(x), .some(y)):
      return x.renderConfidence >= y.renderConfidence ? x : y
    case let (.some(x), .none):
      return x
    case let (.none, .some(y)):
      return y
    default:
      return fallback
    }
  }

  private func bestArm(joints: [PushlyJointName: TrackedJoint]) -> (shoulder: TrackedJoint, elbow: TrackedJoint, wrist: TrackedJoint)? {
    let left = arm(shoulder: .leftShoulder, elbow: .leftElbow, wrist: .leftWrist, joints: joints)
    let right = arm(shoulder: .rightShoulder, elbow: .rightElbow, wrist: .rightWrist, joints: joints)
    switch (left, right) {
    case let (.some(l), .some(r)):
      let lScore = l.shoulder.logicConfidence + l.elbow.logicConfidence + l.wrist.logicConfidence
      let rScore = r.shoulder.logicConfidence + r.elbow.logicConfidence + r.wrist.logicConfidence
      return lScore >= rScore ? l : r
    case let (.some(l), .none):
      return l
    case let (.none, .some(r)):
      return r
    default:
      return nil
    }
  }

  private func arm(
    shoulder: PushlyJointName,
    elbow: PushlyJointName,
    wrist: PushlyJointName,
    joints: [PushlyJointName: TrackedJoint]
  ) -> (shoulder: TrackedJoint, elbow: TrackedJoint, wrist: TrackedJoint)? {
    guard let s = joints[shoulder], let e = joints[elbow], let w = joints[wrist], s.isRenderable, e.isRenderable, w.isRenderable else {
      return nil
    }
    return (s, e, w)
  }

  private func angle(a: CGPoint, b: CGPoint, c: CGPoint) -> CGFloat {
    let ab = CGVector(dx: a.x - b.x, dy: a.y - b.y)
    let cb = CGVector(dx: c.x - b.x, dy: c.y - b.y)
    let dot = ab.dx * cb.dx + ab.dy * cb.dy
    let mag = max(sqrt(ab.dx * ab.dx + ab.dy * ab.dy) * sqrt(cb.dx * cb.dx + cb.dy * cb.dy), 0.0001)
    let cosine = min(1, max(-1, dot / mag))
    return acos(cosine) * 180 / .pi
  }

  private func structuralEvidenceScore(
    joints: [PushlyJointName: TrackedJoint],
    floorState: Bool
  ) -> Double {
    let core: [PushlyJointName] = [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist, .leftHip, .rightHip]
    let lowerSupport: [PushlyJointName] = [.leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
    let coreScore = core.reduce(0.0) { partial, name in
      guard let joint = joints[name], joint.isRenderable else { return partial }
      let sourceWeight: Double
      switch joint.sourceType {
      case .measured:
        sourceWeight = 1.0
      case .lowConfidenceMeasured:
        sourceWeight = 0.85
      case .inferred:
        sourceWeight = floorState ? 0.74 : 0.5
      case .predicted:
        sourceWeight = floorState ? 0.26 : 0.16
      case .missing:
        sourceWeight = 0
      }
      return partial + sourceWeight * Double(max(0.18, joint.renderConfidence))
    }
    let lowerSupportScore = lowerSupport.reduce(0.0) { partial, name in
      guard let joint = joints[name], joint.isRenderable else { return partial }
      let sourceWeight: Double = {
        switch joint.sourceType {
        case .measured: return 1.0
        case .lowConfidenceMeasured: return 0.82
        case .inferred: return floorState ? 0.48 : 0.36
        case .predicted: return 0.12
        case .missing: return 0
        }
      }()
      return partial + sourceWeight * Double(max(0.16, joint.renderConfidence))
    }
    let coreNormalized = min(1, coreScore / Double(core.count) * 1.32)
    let lowerNormalized = min(1, lowerSupportScore / Double(lowerSupport.count) * 1.1)
    return min(1, coreNormalized * 0.84 + lowerNormalized * (floorState ? 0.08 : 0.16))
  }

  private func measuredEvidenceScore(
    joints: [PushlyJointName: TrackedJoint],
    candidates: [PushlyJointName],
    floorState: Bool
  ) -> Double {
    let total = candidates.reduce(0.0) { partial, name in
      guard let joint = joints[name], joint.isRenderable else { return partial }
      let sourceWeight: Double = {
        switch joint.sourceType {
        case .measured: return 1.0
        case .lowConfidenceMeasured: return 0.82
        case .inferred: return floorState ? 0.58 : 0.42
        case .predicted: return floorState ? 0.26 : 0.16
        case .missing: return 0
        }
      }()
      return partial + sourceWeight * Double(max(0.18, joint.logicConfidence))
    }
    return min(1, total / Double(candidates.count) * 1.25)
  }

  private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
  }

  private func isLikelyPushupFloorState(
    joints: [PushlyJointName: TrackedJoint],
    shoulderMid: CGPoint?
  ) -> Bool {
    guard let shoulderMid else {
      return false
    }

    let hipMid = midpoint(joints[.leftHip]?.smoothedPosition, joints[.rightHip]?.smoothedPosition)
    let shoulderHipDelta: Double
    if let hipMid {
      shoulderHipDelta = abs(Double(hipMid.y - shoulderMid.y))
    } else {
      shoulderHipDelta = 0
    }

    if let nose = joints[.nose], nose.isRenderable {
      return abs(Double(nose.smoothedPosition.y - shoulderMid.y)) < config.rep.floorStateNoseShoulderDeltaMax &&
        shoulderHipDelta < config.rep.floorStateShoulderHipDeltaMax
    }

    let shoulderPairVisible = bestPair(joints[.leftShoulder], joints[.rightShoulder]) != nil
    let hipPairVisible = bestPair(joints[.leftHip], joints[.rightHip]) != nil
    let armVisible = arm(shoulder: .leftShoulder, elbow: .leftElbow, wrist: .leftWrist, joints: joints) != nil ||
      arm(shoulder: .rightShoulder, elbow: .rightElbow, wrist: .rightWrist, joints: joints) != nil
    let shoulderHipAligned =
      hipPairVisible
      ? shoulderHipDelta < config.rep.floorStateShoulderHipDeltaMax * 1.15
      : shoulderPairVisible

    return shoulderPairVisible && armVisible && shoulderHipAligned
  }

  private func hasPlausibleFloorBodyAnchors(joints: [PushlyJointName: TrackedJoint]) -> Bool {
    let leftShoulder = joints[.leftShoulder]?.isRenderable == true
    let rightShoulder = joints[.rightShoulder]?.isRenderable == true
    let hasShoulder = leftShoulder || rightShoulder
    guard hasShoulder else { return false }

    let hasHip = joints[.leftHip]?.isRenderable == true || joints[.rightHip]?.isRenderable == true
    let leftArmSegment =
      (joints[.leftShoulder]?.isRenderable == true && joints[.leftElbow]?.isRenderable == true) ||
      (joints[.leftElbow]?.isRenderable == true && joints[.leftWrist]?.isRenderable == true)
    let rightArmSegment =
      (joints[.rightShoulder]?.isRenderable == true && joints[.rightElbow]?.isRenderable == true) ||
      (joints[.rightElbow]?.isRenderable == true && joints[.rightWrist]?.isRenderable == true)
    let hasArmSegment = leftArmSegment || rightArmSegment

    return hasArmSegment || hasHip
  }

  private func bottomSupportAnchors(joints: [PushlyJointName: TrackedJoint]) -> (hasAny: Bool, names: [String]) {
    var names: [String] = []
    let leftShoulder = joints[.leftShoulder]?.isRenderable == true
    let rightShoulder = joints[.rightShoulder]?.isRenderable == true
    let hasShoulder = leftShoulder || rightShoulder
    if leftShoulder && rightShoulder {
      names.append("shoulderPair")
    } else if hasShoulder {
      names.append("singleShoulder")
    }

    let leftHip = joints[.leftHip]?.isRenderable == true
    let rightHip = joints[.rightHip]?.isRenderable == true
    let hasHip = leftHip || rightHip
    if leftHip && rightHip {
      names.append("hipPair")
    } else if hasHip {
      names.append("singleHip")
    }

    let leftArmSegment =
      (leftShoulder && joints[.leftElbow]?.isRenderable == true) ||
      (joints[.leftElbow]?.isRenderable == true && joints[.leftWrist]?.isRenderable == true)
    let rightArmSegment =
      (rightShoulder && joints[.rightElbow]?.isRenderable == true) ||
      (joints[.rightElbow]?.isRenderable == true && joints[.rightWrist]?.isRenderable == true)
    if leftArmSegment || rightArmSegment {
      names.append("armSegment")
    }

    let hasAny = hasShoulder && (hasHip || leftArmSegment || rightArmSegment)
    return (hasAny, names)
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
}
#endif
