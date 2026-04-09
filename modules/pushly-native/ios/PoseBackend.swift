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
  var mediaPipeAvailabilityDiagnostics: MediaPipeAvailabilityDiagnostics? { get }

  func process(frame: PoseFrameInput) throws -> PoseProcessingResult
}

extension PoseBackend {
  var mediaPipeAvailabilityDiagnostics: MediaPipeAvailabilityDiagnostics? { nil }
}

final class PoseBackendCoordinator {
  private let config: PushlyPoseConfig
  private let mediaPipeBackend: PoseBackend
  private let visionFallbackBackend: PoseBackend

  private(set) var activeBackend: PoseBackendKind
  private var recentPrimaryFailures = 0
  private var recentFrames = 0
  private var preferenceOverride: PushlyPoseConfig.PoseBackendPreference?
  private var fallbackAllowedOverride: Bool?
  private let diagnostics: PoseDiagnostics?
  private(set) var lastBackendDebugState: PoseBackendDebugState

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

    let initialMediaPipeDiagnostics = mediaPipeBackend.mediaPipeAvailabilityDiagnostics ?? MediaPipeAvailabilityDiagnostics(
      compiledWithMediaPipe: false,
      poseModelFound: false,
      poseModelName: nil,
      poseModelPath: nil,
      poseLandmarkerInitStatus: "not_compiled",
      mediapipeInitReason: "mediapipe_tasks_vision_not_compiled"
    )

    lastBackendDebugState = PoseBackendDebugState(
      requestedBackend: activeBackend,
      activeBackend: activeBackend,
      fallbackAllowed: config.pipeline.enableAutoBackendFallback,
      fallbackUsed: false,
      fallbackReason: nil,
      mediapipeAvailable: mediaPipeBackend.isAvailable,
      mediaPipeDiagnostics: initialMediaPipeDiagnostics
    )
  }

  func process(frame: PoseFrameInput) throws -> PoseProcessingResult {
    let fallbackAllowed = resolvedFallbackAllowed()
    let requestedKind = resolvedRequestedKind()
    let preferredKind = resolvedPreferredKind(fallbackAllowed: fallbackAllowed)
    let previousActive = activeBackend
    activeBackend = preferredKind

    let primary = backend(for: preferredKind)
    let fallback = fallbackAllowed ? fallbackBackend(for: preferredKind) : nil
    let preflightFallbackReason: String? = {
      if requestedKind == .mediapipe, !mediaPipeBackend.isAvailable {
        return "mediapipe_unavailable"
      }
      return nil
    }()
    updateDebugState(
      requestedBackend: requestedKind,
      activeBackend: preferredKind,
      fallbackAllowed: fallbackAllowed,
      fallbackUsed: false,
      fallbackReason: preflightFallbackReason
    )

    do {
      let primaryResult = try primary.process(frame: frame)
      registerFrameQuality(result: primaryResult)

      let segmentationAssistProtected = primaryResult.backend == .mediapipe
        && (primaryResult.backendDiagnostics.segmentationAssistActive
          || primaryResult.backendDiagnostics.segmentationBottomAssistActive)
      let shouldFallbackForQuality = !segmentationAssistProtected
        && (primaryResult.detectedJointCount < 3 || primaryResult.coverage.upperBodyCoverage < config.mode.upperBodyCoverageLost)
      guard fallbackAllowed, shouldFallbackForQuality, let fallback else {
        return primaryResult
      }

      let fallbackResult = try fallback.process(frame: frame)
      if fallbackResult.detectedJointCount > primaryResult.detectedJointCount || fallbackResult.coverage.upperBodyCoverage > primaryResult.coverage.upperBodyCoverage {
        activeBackend = fallback.kind
        updateDebugState(
          requestedBackend: requestedKind,
          activeBackend: fallback.kind,
          fallbackAllowed: fallbackAllowed,
          fallbackUsed: true,
          fallbackReason: "quality_degraded"
        )
        diagnostics?.recordBackendSwitch(from: previousActive, to: fallback.kind, reason: "quality_degraded")
        return fallbackResult
      }

      return primaryResult
    } catch {
      let noFallbackReason: String = {
        if requestedKind == .mediapipe && !mediaPipeBackend.isAvailable {
          return "mediapipe_unavailable"
        }
        return "primary_error"
      }()
      guard fallbackAllowed,
            let fallback,
            fallback.isAvailable else {
        updateDebugState(
          requestedBackend: requestedKind,
          activeBackend: preferredKind,
          fallbackAllowed: fallbackAllowed,
          fallbackUsed: false,
          fallbackReason: noFallbackReason
        )
        throw error
      }
      let fallbackResult = try fallback.process(frame: frame)
      activeBackend = fallback.kind
      updateDebugState(
        requestedBackend: requestedKind,
        activeBackend: fallback.kind,
        fallbackAllowed: fallbackAllowed,
        fallbackUsed: true,
        fallbackReason: "primary_error"
      )
      diagnostics?.recordBackendSwitch(from: previousActive, to: fallback.kind, reason: "primary_error")
      return fallbackResult
    }
  }

  func setPreferenceOverride(_ override: PushlyPoseConfig.PoseBackendPreference?) {
    preferenceOverride = override
  }

  func setFallbackAllowedOverride(_ isAllowed: Bool?) {
    fallbackAllowedOverride = isAllowed
  }

  private func resolvedRequestedKind() -> PoseBackendKind {
    let preference = preferenceOverride ?? config.pipeline.backendPreference

    switch preference {
    case .vision:
      return .visionFallback
    case .mediapipe, .mlkit:
      return .mediapipe
    case .auto:
      return mediaPipeBackend.isAvailable ? .mediapipe : .visionFallback
    }
  }

  private func resolvedPreferredKind(fallbackAllowed: Bool) -> PoseBackendKind {
    let preference = preferenceOverride ?? config.pipeline.backendPreference

    switch preference {
    case .vision:
      return .visionFallback
    case .mediapipe, .mlkit:
      if mediaPipeBackend.isAvailable || !fallbackAllowed {
        return .mediapipe
      }
      return .visionFallback
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

  private func resolvedFallbackAllowed() -> Bool {
    if let fallbackAllowedOverride {
      return fallbackAllowedOverride
    }
    return config.pipeline.enableAutoBackendFallback
  }

  var isFallbackAvailable: Bool {
    mediaPipeBackend.isAvailable && visionFallbackBackend.isAvailable
  }

  private func updateDebugState(
    requestedBackend: PoseBackendKind,
    activeBackend: PoseBackendKind,
    fallbackAllowed: Bool,
    fallbackUsed: Bool,
    fallbackReason: String?
  ) {
    lastBackendDebugState = PoseBackendDebugState(
      requestedBackend: requestedBackend,
      activeBackend: activeBackend,
      fallbackAllowed: fallbackAllowed,
      fallbackUsed: fallbackUsed,
      fallbackReason: fallbackReason,
      mediapipeAvailable: mediaPipeBackend.isAvailable,
      mediaPipeDiagnostics: resolvedMediaPipeDiagnostics()
    )
  }

  private func resolvedMediaPipeDiagnostics() -> MediaPipeAvailabilityDiagnostics {
    if let diagnostics = mediaPipeBackend.mediaPipeAvailabilityDiagnostics {
      return diagnostics
    }
    return MediaPipeAvailabilityDiagnostics(
      compiledWithMediaPipe: false,
      poseModelFound: false,
      poseModelName: nil,
      poseModelPath: nil,
      poseLandmarkerInitStatus: "not_compiled",
      mediapipeInitReason: "mediapipe_tasks_vision_not_compiled"
    )
  }

  private func registerFrameQuality(result: PoseProcessingResult) {
    recentFrames += 1
    let segmentationAssistProtected = result.backend == .mediapipe
      && (result.backendDiagnostics.segmentationAssistActive
        || result.backendDiagnostics.segmentationBottomAssistActive)
    if result.detectedJointCount < 3 && !segmentationAssistProtected {
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
