import Foundation

#if os(iOS)
import CoreGraphics

final class JSBridgePayloadMapper {
  func makePayload(
    joints: [PushlyJointName: TrackedJoint],
    quality: TrackingQuality,
    rep: RepDetectionOutput,
    instruction: String,
    lowLightDetected: Bool,
    poseBackend: PoseBackendKind,
    poseFPS: Double,
    cameraTelemetry: CameraTelemetry?,
    bounds: CGRect,
    debugEnabled: Bool,
    reacquireSource: ReacquireSource,
    orientation: CGImagePropertyOrientation,
    mirrored: Bool,
    debugSessionID: String,
    visibleJointCount: Int,
    backendDebug: PoseBackendDebugState? = nil,
    fallbackDiagnostics: TemporalJointTracker.FallbackTrackingDiagnostics? = nil
  ) -> [String: Any] {
    let renderableJoints = joints.values.filter(\.isRenderable)
    let avgConfidence = renderableJoints.isEmpty
      ? 0
      : renderableJoints.map { Double($0.renderConfidence) }.reduce(0, +) / Double(renderableJoints.count)

    let payloadJoints = PushlyJointName.allCases.compactMap { name -> [String: Any]? in
      guard let joint = joints[name], joint.sourceType != .missing else {
        return nil
      }

      let x = joint.smoothedPosition.x
      let y = 1 - joint.smoothedPosition.y
      return [
        "name": name.rawValue,
        "jointName": name.rawValue,
        "x": min(1, max(0, x)),
        "y": min(1, max(0, y)),
        "confidence": joint.renderConfidence,
        "sourceType": joint.sourceType.rawValue,
        "isRenderable": joint.isRenderable,
        "isLogicUsable": joint.isLogicUsable,
        "visibility": joint.visibility,
        "presence": joint.presence,
        "inFrame": joint.inFrame
      ]
    }

    let requestedBackend = backendDebug?.requestedBackend ?? poseBackend
    let activeBackend = backendDebug?.activeBackend ?? poseBackend
    let fallbackAllowed = backendDebug?.fallbackAllowed ?? false
    let fallbackUsed = backendDebug?.fallbackUsed ?? false
    let fallbackReason = backendDebug?.fallbackReason
    let mediapipeAvailable = backendDebug?.mediapipeAvailable ?? (poseBackend == .mediapipe)
    let mediaPipeDiagnostics = backendDebug?.mediaPipeDiagnostics
    let compiledWithMediaPipe = mediaPipeDiagnostics?.compiledWithMediaPipe ?? (poseBackend == .mediapipe)
    let poseModelFound = mediaPipeDiagnostics?.poseModelFound ?? false
    let poseModelName = mediaPipeDiagnostics?.poseModelName
    let poseModelPath = mediaPipeDiagnostics?.poseModelPath
    let poseLandmarkerInitStatus = mediaPipeDiagnostics?.poseLandmarkerInitStatus ?? "unknown"
    let mediapipeInitReason = mediaPipeDiagnostics?.mediapipeInitReason
    let repDebug = rep.repDebug
    let fallbackCoverage: [String: Any] = [
      "upperBody": quality.upperBodyCoverage,
      "fullBody": quality.fullBodyCoverage,
      "hand": quality.handCoverage,
      "requiredAnchors": fallbackDiagnostics?.requiredAnchorCoverage as Any
    ]
    let fallbackAnchorStrength = fallbackDiagnostics?.fallbackAnchorStrength ?? 0
    let weakestRequiredLandmark = fallbackDiagnostics?.weakestRequiredLandmark
    let weakestRequiredLandmarkConfidence = fallbackDiagnostics?.weakestRequiredLandmarkConfidence ?? 0
    let sourceTypeTransitions = fallbackDiagnostics?.sourceTypeTransitions ?? [:]
    let visibilityHysteresisState: [String: Any] = [
      "requiredVisibleCount": fallbackDiagnostics?.visibilityHysteresisRequiredVisibleCount as Any,
      "requiredTotal": fallbackDiagnostics?.visibilityHysteresisRequiredTotal as Any
    ]
    let pushupDebug: [String: Any] = [
      "requestedBackend": requestedBackend.rawValue,
      "activeBackend": activeBackend.rawValue,
      "fallbackAllowed": fallbackAllowed,
      "fallbackUsed": fallbackUsed,
      "fallbackReason": fallbackReason as Any,
      "mediapipeAvailable": mediapipeAvailable,
      "compiledWithMediaPipe": compiledWithMediaPipe,
      "poseModelFound": poseModelFound,
      "poseModelName": poseModelName as Any,
      "poseModelPath": poseModelPath as Any,
      "poseLandmarkerInitStatus": poseLandmarkerInitStatus,
      "mediapipeInitReason": mediapipeInitReason as Any,
      "state": rep.state.rawValue,
      "repCount": rep.repCount,
      "frameIndex": repDebug?.frameIndex as Any,
      "timestampSeconds": repDebug?.timestampSeconds as Any,
      "currentRepState": repDebug?.currentRepState as Any,
      "repStateMachineState": repDebug?.repStateMachineState as Any,
      "repStateTransitionEvent": repDebug?.repStateTransitionEvent as Any,
      "repBlockedReasons": rep.blockedReasons,
      "trackingQuality": quality.trackingQuality,
      "logicQuality": quality.logicQuality,
      "upperBodyCoverage": quality.upperBodyCoverage,
      "wristRetention": quality.wristRetention,
      "fallbackCoverage": fallbackCoverage,
      "fallbackAnchorStrength": fallbackAnchorStrength,
      "weakestRequiredLandmark": weakestRequiredLandmark as Any,
      "weakestRequiredLandmarkConfidence": weakestRequiredLandmarkConfidence,
      "sourceTypeTransitions": sourceTypeTransitions,
      "visibilityHysteresisState": visibilityHysteresisState,
      "smoothedElbowAngle": repDebug?.smoothedElbowAngle as Any,
      "repMinElbowAngle": repDebug?.repMinElbowAngle as Any,
      "rawTorsoY": repDebug?.rawTorsoY as Any,
      "rawShoulderY": repDebug?.rawShoulderY as Any,
      "smoothedTorsoY": repDebug?.smoothedTorsoY as Any,
      "smoothedShoulderY": repDebug?.smoothedShoulderY as Any,
      "rawTorsoVelocity": repDebug?.rawTorsoVelocity as Any,
      "rawShoulderVelocity": repDebug?.rawShoulderVelocity as Any,
      "smoothedTorsoVelocity": repDebug?.smoothedTorsoVelocity as Any,
      "smoothedShoulderVelocity": repDebug?.smoothedShoulderVelocity as Any,
      "topReferenceTorsoY": repDebug?.topReferenceTorsoY as Any,
      "topReferenceShoulderY": repDebug?.topReferenceShoulderY as Any,
      "descendingSignal": repDebug?.descendingSignal as Any,
      "ascendingSignal": repDebug?.ascendingSignal as Any,
      "torsoDownTravel": repDebug?.torsoDownTravel as Any,
      "torsoRecoveryToTop": repDebug?.torsoRecoveryToTop as Any,
      "shoulderDownTravel": repDebug?.shoulderDownTravel as Any,
      "shoulderRecoveryToTop": repDebug?.shoulderRecoveryToTop as Any,
      "bottomReached": repDebug?.bottomReached as Any,
      "descendingFrames": repDebug?.descendingFrames as Any,
      "bottomCandidateFrames": repDebug?.bottomCandidateFrames as Any,
      "bottomConfirmedFrames": repDebug?.bottomConfirmedFrames as Any,
      "bottomFrames": repDebug?.bottomFrames as Any,
      "ascendingFrames": repDebug?.ascendingFrames as Any,
      "ascentFrames": repDebug?.ascentFrames as Any,
      "bottomNearMiss": repDebug?.bottomNearMiss as Any,
      "bottomConfirmedLatched": repDebug?.bottomConfirmedLatched as Any,
      "minDescendingFramesRequired": repDebug?.minDescendingFramesRequired as Any,
      "minBottomFramesRequired": repDebug?.minBottomFramesRequired as Any,
      "minAscendingFramesRequired": repDebug?.minAscendingFramesRequired as Any,
      "minTopRecoveryFramesRequired": repDebug?.minTopRecoveryFramesRequired as Any,
      "weakestLandmark": repDebug?.weakestLandmark as Any,
      "weakestLandmarkConfidence": repDebug?.weakestLandmarkConfidence as Any,
      "missingLandmarks": repDebug?.missingLandmarks as Any,
      "landmarkQuality": repDebug?.landmarkQuality as Any,
      "canProgress": repDebug?.canProgress as Any,
      "logicBlockedFrames": repDebug?.logicBlockedFrames as Any,
      "startupReady": repDebug?.startupReady as Any,
      "startupTopEvidence": repDebug?.startupTopEvidence as Any,
      "startupDescendBridgeUsed": repDebug?.startupDescendBridgeUsed as Any,
      "startBlockedReason": repDebug?.startBlockedReason as Any,
      "repRearmPending": repDebug?.repRearmPending as Any,
      "topRecoveryFrames": repDebug?.topRecoveryFrames as Any,
      "commitPathActive": repDebug?.commitPathActive as Any,
      "commitCancelledReason": repDebug?.commitCancelledReason as Any,
      "idleResetReason": repDebug?.idleResetReason as Any,
      "pendingCommitReason": repDebug?.pendingCommitReason as Any,
      "commitBlockedBy": repDebug?.commitBlockedBy as Any,
      "topReady": repDebug?.topReady as Any,
      "descendingStarted": repDebug?.descendingStarted as Any,
      "bottomLatched": repDebug?.bottomLatched as Any,
      "ascendingStarted": repDebug?.ascendingStarted as Any,
      "topRecovered": repDebug?.topRecovered as Any,
      "repCommitted": repDebug?.repCommitted as Any,
      "rearmReady": repDebug?.rearmReady as Any,
      "resetReason": repDebug?.resetReason as Any,
      "timeoutOrAbortReason": repDebug?.timeoutOrAbortReason as Any,
      "firstBlockingConditionAfterBottom": repDebug?.firstBlockingConditionAfterBottom as Any,
      "lostTrackingAtBottom": repDebug?.lostTrackingAtBottom as Any,
      "trackingLossDuringCommitPath": repDebug?.trackingLossDuringCommitPath as Any,
      "trackingLossGraceFramesRemaining": repDebug?.trackingLossGraceFramesRemaining as Any,
      "bottomHoldActive": repDebug?.bottomHoldActive as Any,
      "bottomReacquireState": repDebug?.bottomReacquireState as Any,
      "bottomSupportAnchors": repDebug?.bottomSupportAnchors as Any,
      "bottomBlockedReason": repDebug?.bottomBlockedReason as Any,
      "didEnterAscending": repDebug?.didEnterAscending as Any,
      "didEnterTopRecovery": repDebug?.didEnterTopRecovery as Any,
      "rearmBlockedReason": repDebug?.rearmBlockedReason as Any,
      "framesUntilRearm": repDebug?.framesUntilRearm as Any,
      "rearmConfirmProgress": repDebug?.rearmConfirmProgress as Any,
      "rearmMissingCondition": repDebug?.rearmMissingCondition as Any,
      "whyRepDidNotCount": repDebug?.whyRepDidNotCount as Any,
      "firstFinalBlocker": repDebug?.firstFinalBlocker as Any,
      "lastFailedGate": repDebug?.lastFailedGate as Any,
      "lastSuccessfulGate": repDebug?.lastSuccessfulGate as Any,
      "bodyFound": repDebug?.bodyFound as Any,
      "trackingQualityPass": repDebug?.trackingQualityPass as Any,
      "logicQualityPass": repDebug?.logicQualityPass as Any,
      "bottomGate": repDebug?.bottomGate as Any,
      "ascentGate": repDebug?.ascentGate as Any,
      "rearmGate": repDebug?.rearmGate as Any,
      "cycleCoreReady": repDebug?.cycleCoreReady as Any,
      "strictCycleReady": repDebug?.strictCycleReady as Any,
      "floorFallbackCycleReady": repDebug?.floorFallbackCycleReady as Any,
      "motionTravelGate": repDebug?.motionTravelGate as Any,
      "topRecoveryGate": repDebug?.topRecoveryGate as Any,
      "countCommitReady": repDebug?.countCommitReady as Any,
      "torsoSupportReady": repDebug?.torsoSupportReady as Any,
      "shoulderSupportReady": repDebug?.shoulderSupportReady as Any,
      "countGatePassed": repDebug?.countGatePassed as Any,
      "countGateBlocked": repDebug?.countGateBlocked as Any,
      "countGateBlockReason": repDebug?.countGateBlockReason as Any,
      "stateTransitionEvent": repDebug?.stateTransitionEvent as Any,
      "repsAttemptedEstimate": repDebug?.repsAttemptedEstimate as Any,
      "repsCommitted": repDebug?.repsCommitted as Any,
      "repsBlockedByBottom": repDebug?.repsBlockedByBottom as Any,
      "repsBlockedByTopRecovery": repDebug?.repsBlockedByTopRecovery as Any,
      "repsBlockedByRearm": repDebug?.repsBlockedByRearm as Any,
      "repsBlockedByTrackingLoss": repDebug?.repsBlockedByTrackingLoss as Any,
      "repsBlockedByTravel": repDebug?.repsBlockedByTravel as Any,
      "repsBlockedByQuality": repDebug?.repsBlockedByQuality as Any,
      "bottomConfirmedCount": repDebug?.bottomConfirmedCount as Any,
      "ascendingEnteredCount": repDebug?.ascendingEnteredCount as Any,
      "topRecoveryEnteredCount": repDebug?.topRecoveryEnteredCount as Any,
      "repCommitAttemptCount": repDebug?.repCommitAttemptCount as Any,
      "repCommitSuccessCount": repDebug?.repCommitSuccessCount as Any,
      "repCommitBlockedCount": repDebug?.repCommitBlockedCount as Any
    ]

    var payload: [String: Any] = [
      "bodyDetected": quality.bodyVisibilityState != .notFound,
      "confidence": avgConfidence,
      "formEvidenceScore": rep.formEvidenceScore,
      "instruction": instruction,
      "joints": payloadJoints,
      "repCount": rep.repCount,
      "state": rep.state.rawValue,
      "repDebug": repDebug?.toDictionary() as Any,
      "pushupDebug": pushupDebug,

      // Legacy continuity state kept for backward compatibility.
      "trackingState": quality.trackingState.rawValue,
      "trackingContinuityState": quality.trackingState.rawValue,

      // New mode/state diagnostics.
      "poseMode": quality.poseMode.rawValue,
      "bodyMode": quality.poseMode.rawValue,
      "poseTrackingState": quality.poseTrackingState.rawValue,

      "trackingQuality": quality.trackingQuality,
      "renderQuality": quality.renderQuality,
      "logicQuality": quality.logicQuality,
      "reliability": quality.reliability,
      "modeConfidence": quality.modeConfidence,
      "roiCoverage": quality.roiCoverage,
      "fullBodyCoverage": quality.fullBodyCoverage,
      "upperBodyCoverage": quality.upperBodyCoverage,
      "handCoverage": quality.handCoverage,
      "wristRetention": quality.wristRetention,
      "inferredJointRatio": quality.inferredJointRatio,
      "bodyVisibilityState": quality.bodyVisibilityState.rawValue,
      "lowLightDetected": lowLightDetected,
      "poseBackend": poseBackend.rawValue,
      "requestedBackend": requestedBackend.rawValue,
      "activeBackend": activeBackend.rawValue,
      "fallbackAllowed": fallbackAllowed,
      "fallbackUsed": fallbackUsed,
      "fallbackReason": fallbackReason as Any,
      "mediapipeAvailable": mediapipeAvailable,
      "compiledWithMediaPipe": compiledWithMediaPipe,
      "poseModelFound": poseModelFound,
      "poseModelName": poseModelName as Any,
      "poseModelPath": poseModelPath as Any,
      "poseLandmarkerInitStatus": poseLandmarkerInitStatus,
      "mediapipeInitReason": mediapipeInitReason as Any,
      "reacquireSource": reacquireSource.rawValue,
      "visibleJointCount": visibleJointCount,
      "mirrored": mirrored,
      "orientation": orientation.rawValue,
      "debugSessionID": debugSessionID,
      "poseFPS": poseFPS,
      "processingFPS": poseFPS,
      "lowLightActive": cameraTelemetry?.lowLightBoostEnabled ?? lowLightDetected
    ]

    payload["cameraFPS"] = cameraTelemetry?.captureFPS as Any
    payload["cameraProcessingBacklog"] = cameraTelemetry?.processingBacklog as Any
    payload["cameraAverageProcessingMs"] = cameraTelemetry?.averageProcessingMs as Any
    payload["dropRate"] = cameraTelemetry?.dropRate as Any

    if debugEnabled {
      var diagnostics: [String: Any] = [:]
      diagnostics["reasonCodes"] = quality.reasonCodes
      diagnostics["repBlockedReasons"] = rep.blockedReasons
      diagnostics["jointCount"] = payloadJoints.count
      diagnostics["visibleJointCount"] = visibleJointCount
      diagnostics["viewWidth"] = bounds.width
      diagnostics["viewHeight"] = bounds.height
      diagnostics["mirrored"] = mirrored
      diagnostics["orientation"] = orientation.rawValue
      diagnostics["debugSessionID"] = debugSessionID
      diagnostics["dropCount"] = cameraTelemetry?.droppedFrames ?? 0
      diagnostics["dropLateCount"] = cameraTelemetry?.droppedLateFrames ?? 0
      diagnostics["dropOutOfBuffersCount"] = cameraTelemetry?.droppedOutOfBuffers ?? 0
      diagnostics["cameraProcessingBacklog"] = cameraTelemetry?.processingBacklog ?? 0
      diagnostics["cameraAverageProcessingMs"] = cameraTelemetry?.averageProcessingMs ?? 0
      diagnostics["cameraLowLightBoostSupported"] = cameraTelemetry?.lowLightBoostSupported ?? false
      diagnostics["cameraExposureDurationSeconds"] = cameraTelemetry?.exposureDurationSeconds ?? 0
      diagnostics["poseMode"] = quality.poseMode.rawValue
      diagnostics["poseTrackingState"] = quality.poseTrackingState.rawValue
      diagnostics["modeConfidence"] = quality.modeConfidence
      payload["diagnostics"] = diagnostics
    }

    return payload
  }
}
#endif
