import Foundation

#if os(iOS)
import AVFoundation

struct PoseFrameInput {
  let sampleBuffer: CMSampleBuffer
  let orientation: CGImagePropertyOrientation
  let mirrored: Bool
  let roiHint: CGRect?
  let timestamp: TimeInterval
  let targetMode: BodyTrackingMode
  let reacquireSource: ReacquireSource
  let relockSuccessCount: Int
  let relockFailureCount: Int
}

protocol PoseBackend {
  var kind: PoseBackendKind { get }
  var isAvailable: Bool { get }

  func process(frame: PoseFrameInput) throws -> PoseProcessingResult
}

final class PoseBackendCoordinator {
  private let config: PushlyPoseConfig
  private let mediaPipeBackend: PoseBackend
  private let visionFallbackBackend: PoseBackend

  private(set) var activeBackend: PoseBackendKind
  private var recentPrimaryFailures = 0
  private var recentFrames = 0
  private var preferenceOverride: PushlyPoseConfig.PoseBackendPreference?
  private let diagnostics: PoseDiagnostics?

  init(config: PushlyPoseConfig, mediaPipeBackend: PoseBackend, visionFallbackBackend: PoseBackend, diagnostics: PoseDiagnostics? = nil) {
    self.config = config
    self.mediaPipeBackend = mediaPipeBackend
    self.visionFallbackBackend = visionFallbackBackend
    self.diagnostics = diagnostics

    let initial = config.pipeline.backendPreference
    switch initial {
    case .vision:
      activeBackend = .visionFallback
    case .mediapipe, .auto, .mlkit:
      activeBackend = mediaPipeBackend.isAvailable ? .mediapipe : .visionFallback
    }

    diagnostics?.recordBackendInitialized(kind: .mediapipe, available: mediaPipeBackend.isAvailable)
    diagnostics?.recordBackendInitialized(kind: .visionFallback, available: visionFallbackBackend.isAvailable)
    if !mediaPipeBackend.isAvailable {
      diagnostics?.recordBackendUnavailable(kind: .mediapipe, reason: "Primary backend not available")
    }
  }

  func process(frame: PoseFrameInput) throws -> PoseProcessingResult {
    let preferredKind = resolvedPreferredKind()
    let previousActive = activeBackend
    activeBackend = preferredKind

    let primary = backend(for: preferredKind)
    let fallback = fallbackBackend(for: preferredKind)

    do {
      let primaryResult = try primary.process(frame: frame)
      registerFrameQuality(result: primaryResult)

      let shouldFallbackForQuality = primaryResult.detectedJointCount < 3 || primaryResult.coverage.upperBodyCoverage < config.mode.upperBodyCoverageLost
      guard config.pipeline.enableAutoBackendFallback, shouldFallbackForQuality, let fallback else {
        return primaryResult
      }

      let fallbackResult = try fallback.process(frame: frame)
      if fallbackResult.detectedJointCount > primaryResult.detectedJointCount || fallbackResult.coverage.upperBodyCoverage > primaryResult.coverage.upperBodyCoverage {
        activeBackend = fallback.kind
        diagnostics?.recordBackendSwitch(from: previousActive, to: fallback.kind, reason: "quality_degraded")
        return fallbackResult
      }

      return primaryResult
    } catch {
      guard config.pipeline.enableAutoBackendFallback,
            let fallback,
            fallback.isAvailable else {
        throw error
      }
      let fallbackResult = try fallback.process(frame: frame)
      activeBackend = fallback.kind
      diagnostics?.recordBackendSwitch(from: previousActive, to: fallback.kind, reason: "primary_error")
      return fallbackResult
    }
  }

  func setPreferenceOverride(_ override: PushlyPoseConfig.PoseBackendPreference?) {
    preferenceOverride = override
  }

  private func resolvedPreferredKind() -> PoseBackendKind {
    let preference = preferenceOverride ?? config.pipeline.backendPreference

    switch preference {
    case .vision:
      return .visionFallback
    case .mediapipe, .mlkit:
      return mediaPipeBackend.isAvailable ? .mediapipe : .visionFallback
    case .auto:
      if mediaPipeBackend.isAvailable {
        if recentFrames >= config.pipeline.backendFailureWindow,
           recentPrimaryFailures >= config.pipeline.backendSwitchThreshold {
          return .visionFallback
        }
        return .mediapipe
      }
      return .visionFallback
    }
  }

  var isFallbackAvailable: Bool {
    mediaPipeBackend.isAvailable && visionFallbackBackend.isAvailable
  }

  private func registerFrameQuality(result: PoseProcessingResult) {
    recentFrames += 1
    if result.detectedJointCount < 3 {
      recentPrimaryFailures += 1
    } else {
      recentPrimaryFailures = max(0, recentPrimaryFailures - 1)
    }

    if recentFrames > max(config.pipeline.backendFailureWindow * 2, 24) {
      recentFrames = config.pipeline.backendFailureWindow
      recentPrimaryFailures = min(recentPrimaryFailures, config.pipeline.backendSwitchThreshold)
    }
  }

  private func backend(for kind: PoseBackendKind) -> PoseBackend {
    switch kind {
    case .mediapipe:
      return mediaPipeBackend
    case .visionFallback, .vision, .mlkit:
      return visionFallbackBackend
    }
  }

  private func fallbackBackend(for kind: PoseBackendKind) -> PoseBackend? {
    switch kind {
    case .mediapipe:
      return visionFallbackBackend.isAvailable ? visionFallbackBackend : nil
    case .visionFallback, .vision, .mlkit:
      return mediaPipeBackend.isAvailable ? mediaPipeBackend : nil
    }
  }
}
#endif
