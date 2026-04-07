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
    visibleJointCount: Int
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

    var payload: [String: Any] = [
      "bodyDetected": quality.bodyVisibilityState != .notFound,
      "confidence": avgConfidence,
      "formEvidenceScore": rep.formEvidenceScore,
      "instruction": instruction,
      "joints": payloadJoints,
      "repCount": rep.repCount,
      "state": rep.state.rawValue,

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
