import Foundation

#if os(iOS)
import AVFoundation
import Vision

final class VisionPoseBackend: PoseBackend {
  private let minDetectedJointsForBody = 3
  private let request = VNDetectHumanBodyPoseRequest()
  private let sequenceHandler = VNSequenceRequestHandler()
  private let config: PushlyPoseConfig
  private let diagnostics: PoseDiagnostics?
  private let heuristics = PoseHeuristicsSolver()

  var kind: PoseBackendKind { .visionFallback }
  var isAvailable: Bool { true }

  init(config: PushlyPoseConfig, diagnostics: PoseDiagnostics? = nil) {
    self.config = config
    self.diagnostics = diagnostics
    diagnostics?.recordBackendInitialized(kind: .visionFallback, available: true)
  }

  func process(frame: PoseFrameInput) throws -> PoseProcessingResult {
    let started = CACurrentMediaTime()
    if let roiHint = frame.roiHint {
      request.regionOfInterest = PoseCoordinateConverter.visionROIFromCanonical(
        roiHint,
        orientation: frame.orientation,
        mirrored: frame.mirrored
      )
    } else {
      request.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
    }
    try sequenceHandler.perform([request], on: frame.sampleBuffer, orientation: frame.orientation)

    let brightness = estimateBrightness(sampleBuffer: frame.sampleBuffer)
    let lowLightDetected = brightness < config.quality.lowLightLumaThreshold

    guard let observation = (request.results ?? []).first,
          let points = try? observation.recognizedPoints(.all) else {
      let diagnostics = PoseBackendDiagnostics(
        rawObservationCount: (request.results ?? []).count,
        trackedJointCount: 0,
        averageJointConfidence: 0,
        roiUsed: frame.roiHint,
        durationMs: (CACurrentMediaTime() - started) * 1000,
        modeConfidence: 0,
        reliability: 0,
        handRefinedJointCount: 0
      )

      return PoseProcessingResult(
        measured: [:],
        avgConfidence: 0,
        brightnessLuma: brightness,
        lowLightDetected: lowLightDetected,
        observationExists: false,
        detectedJointCount: 0,
        backend: kind,
        mode: .unknown,
        modeConfidence: 0,
        coverage: .empty,
        backendDiagnostics: diagnostics,
        reacquireDiagnostics: ReacquireDiagnostics(
          source: frame.reacquireSource,
          roi: frame.roiHint,
          relockSuccessCount: frame.relockSuccessCount,
          relockFailureCount: frame.relockFailureCount
        )
      )
    }

    var mapped: [PushlyJointName: PoseJointMeasurement] = [:]
    var confidenceSum: Float = 0

    for jointName in PushlyJointName.allCases {
      guard let visionName = jointName.visionJoint,
            let point = points[visionName] else {
        continue
      }

      let threshold = lowLightDetected ? config.tracker.measuredConfidenceMin * 0.5 : config.tracker.measuredConfidenceMin
      guard point.confidence > threshold else {
        continue
      }

      let existing = mapped[jointName]
      if existing == nil || existing!.confidence < point.confidence {
        mapped[jointName] = PoseJointMeasurement(
          name: jointName,
          point: PoseCoordinateConverter.clampNormalizedPoint(point.location),
          confidence: point.confidence,
          visibility: point.confidence,
          presence: point.confidence,
          sourceType: point.confidence >= config.tracker.lowConfidenceMin ? .measured : .lowConfidenceMeasured,
          inFrame: point.confidence > 0.01,
          backend: kind,
          measuredAt: frame.timestamp
        )
      }
      confidenceSum += point.confidence
    }

    mapped = heuristics.applyTooCloseHeuristics(joints: mapped, backend: kind, timestamp: frame.timestamp)

    let detectedJointCount = mapped.count
    let avgConfidence = detectedJointCount > 0 ? Double(confidenceSum) / Double(detectedJointCount) : 0
    let measured = detectedJointCount >= minDetectedJointsForBody ? mapped : [:]

    let coverage = PoseCoverageCalculator.coverage(measured: measured)
    let hasFull = measured[.leftKnee] != nil && measured[.rightKnee] != nil && measured[.leftAnkle] != nil && measured[.rightAnkle] != nil
    let mode: BodyTrackingMode
    if hasFull && coverage.fullBodyCoverage >= config.mode.fullBodyCoverageEnter {
      mode = .fullBody
    } else if coverage.upperBodyCoverage >= config.mode.upperBodyCoverageEnter {
      mode = .upperBody
    } else {
      mode = .unknown
    }

    let modeConfidence = mode == .fullBody ? coverage.fullBodyCoverage : coverage.upperBodyCoverage
    let diagnostics = PoseBackendDiagnostics(
      rawObservationCount: 1,
      trackedJointCount: measured.count,
      averageJointConfidence: avgConfidence,
      roiUsed: frame.roiHint,
      durationMs: (CACurrentMediaTime() - started) * 1000,
      modeConfidence: modeConfidence,
      reliability: min(1, max(0, avgConfidence * 0.7 + coverage.upperBodyCoverage * 0.3)),
      handRefinedJointCount: 0
    )

    return PoseProcessingResult(
      measured: measured,
      avgConfidence: avgConfidence,
      brightnessLuma: brightness,
      lowLightDetected: lowLightDetected,
      observationExists: true,
      detectedJointCount: detectedJointCount,
      backend: kind,
      mode: mode,
      modeConfidence: modeConfidence,
      coverage: coverage,
      backendDiagnostics: diagnostics,
      reacquireDiagnostics: ReacquireDiagnostics(
        source: frame.reacquireSource,
        roi: frame.roiHint,
        relockSuccessCount: frame.relockSuccessCount,
        relockFailureCount: frame.relockFailureCount
      )
    )
  }

  private func estimateBrightness(sampleBuffer: CMSampleBuffer) -> Double {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return 0.5
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
      return 0.5
    }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)

    let stepX = max(12, width / 38)
    let stepY = max(12, height / 32)
    var total = 0.0
    var samples = 0.0

    var y = 0
    while y < height {
      var x = 0
      while x < width {
        let offset = y * bytesPerRow + x * 4
        let b = Double(bytes[offset])
        let g = Double(bytes[offset + 1])
        let r = Double(bytes[offset + 2])
        total += (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
        samples += 1
        x += stepX
      }
      y += stepY
    }

    guard samples > 0 else {
      return 0.5
    }
    return total / samples
  }
}
#endif
