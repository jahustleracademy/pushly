import Foundation

#if os(iOS)
import AVFoundation

// Legacy backend retained only for compatibility with older debug controls.
// The production pipeline is MediaPipe-first with Vision fallback.
final class MLKitPoseBackend: PoseBackend {
  var kind: PoseBackendKind { .mlkit }
  var isAvailable: Bool { false }

  init(config: PushlyPoseConfig) {}

  func process(frame: PoseFrameInput) throws -> PoseProcessingResult {
    PoseProcessingResult(
      measured: [:],
      avgConfidence: 0,
      brightnessLuma: 0.5,
      lowLightDetected: false,
      observationExists: false,
      detectedJointCount: 0,
      backend: .mlkit,
      mode: .unknown,
      modeConfidence: 0,
      coverage: .empty,
      backendDiagnostics: PoseBackendDiagnostics(
        rawObservationCount: 0,
        trackedJointCount: 0,
        averageJointConfidence: 0,
        roiUsed: frame.roiHint,
        durationMs: 0,
        modeConfidence: 0,
        reliability: 0,
        handRefinedJointCount: 0
      ),
      reacquireDiagnostics: ReacquireDiagnostics(
        source: frame.reacquireSource,
        roi: frame.roiHint,
        relockSuccessCount: frame.relockSuccessCount,
        relockFailureCount: frame.relockFailureCount
      )
    )
  }
}
#endif
