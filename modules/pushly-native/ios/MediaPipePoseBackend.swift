import Foundation

#if os(iOS)
import AVFoundation

#if canImport(MediaPipeTasksVision)
import MediaPipeTasksVision
import UIKit

final class MediaPipePoseBackend: PoseBackend {
  private struct TooCloseLockState {
    var isActive = false
    var holdUntil: TimeInterval = 0
    var lockedLeftHip: CGPoint = .zero
    var lockedRightHip: CGPoint = .zero
  }
  private struct MediaPipeInputTransform {
    let orientation: UIImage.Orientation
    let appliedMirroring: Bool
  }

  private let config: PushlyPoseConfig
  private let diagnostics: PoseDiagnostics?
  private let poseLandmarker: PoseLandmarker?
  private let handLandmarker: HandLandmarker?
  private var tooCloseLock = TooCloseLockState()

  var kind: PoseBackendKind { .mediapipe }
  var isAvailable: Bool { poseLandmarker != nil }

  init(config: PushlyPoseConfig, diagnostics: PoseDiagnostics? = nil) {
    self.config = config
    self.diagnostics = diagnostics

    if let poseModelPath = Self.locateModel(
      fileName: config.mediaPipe.poseModelFileName,
      fileExtension: config.mediaPipe.poseModelFileExtension
    ) {
      let gpuOptions = PoseLandmarkerOptions()
      gpuOptions.baseOptions.modelAssetPath = poseModelPath
      gpuOptions.baseOptions.delegate = .gpu
      gpuOptions.runningMode = .video
      gpuOptions.numPoses = config.mediaPipe.numPoses
      gpuOptions.minPoseDetectionConfidence = config.mediaPipe.minPoseDetectionConfidence
      gpuOptions.minPosePresenceConfidence = config.mediaPipe.minPosePresenceConfidence
      gpuOptions.minTrackingConfidence = config.mediaPipe.minPoseTrackingConfidence

      if let gpuLandmarker = try? PoseLandmarker(options: gpuOptions) {
        poseLandmarker = gpuLandmarker
      } else {
        let cpuOptions = PoseLandmarkerOptions()
        cpuOptions.baseOptions.modelAssetPath = poseModelPath
        cpuOptions.baseOptions.delegate = .cpu
        cpuOptions.runningMode = .video
        cpuOptions.numPoses = config.mediaPipe.numPoses
        cpuOptions.minPoseDetectionConfidence = config.mediaPipe.minPoseDetectionConfidence
        cpuOptions.minPosePresenceConfidence = config.mediaPipe.minPosePresenceConfidence
        cpuOptions.minTrackingConfidence = config.mediaPipe.minPoseTrackingConfidence
        poseLandmarker = try? PoseLandmarker(options: cpuOptions)
      }
      diagnostics?.recordBackendInitialized(kind: .mediapipe, available: poseLandmarker != nil, details: [
        "poseModelFound": "true",
        "poseModelPath": poseModelPath,
        "poseDelegateRequested": "gpu"
      ])
    } else {
      poseLandmarker = nil
      diagnostics?.recordBackendUnavailable(kind: .mediapipe, reason: "pose_model_missing")
    }

    if config.mediaPipe.enableHandRefinement,
       let handModelPath = Self.locateModel(
         fileName: config.mediaPipe.handModelFileName,
         fileExtension: config.mediaPipe.handModelFileExtension
       ) {
      let handOptions = HandLandmarkerOptions()
      handOptions.baseOptions.modelAssetPath = handModelPath
      handOptions.baseOptions.delegate = .gpu
      handOptions.runningMode = .video
      handOptions.numHands = config.mediaPipe.numHands
      handOptions.minHandDetectionConfidence = config.mediaPipe.minHandDetectionConfidence
      handOptions.minHandPresenceConfidence = config.mediaPipe.minHandPresenceConfidence
      handOptions.minTrackingConfidence = config.mediaPipe.minHandTrackingConfidence
      handLandmarker = try? HandLandmarker(options: handOptions)
      diagnostics?.recordBackendInitialized(kind: .mediapipe, available: handLandmarker != nil, details: [
        "handModelFound": "true",
        "handRefinementEnabled": "\(config.mediaPipe.enableHandRefinement)"
      ])
    } else {
      handLandmarker = nil
      diagnostics?.recordBackendInitialized(kind: .mediapipe, available: poseLandmarker != nil, details: [
        "handModelFound": "false",
        "handRefinementEnabled": "\(config.mediaPipe.enableHandRefinement)"
      ])
    }
  }

  func process(frame: PoseFrameInput) throws -> PoseProcessingResult {
    let started = CACurrentMediaTime()
    let brightness = estimateBrightness(sampleBuffer: frame.sampleBuffer)
    let lowLightDetected = brightness < config.quality.lowLightLumaThreshold

    guard let poseLandmarker else {
      return emptyResult(
        frame: frame,
        brightness: brightness,
        lowLightDetected: lowLightDetected,
        started: started
      )
    }

    let inputTransform = mediaPipeInputTransform(sampleBuffer: frame.sampleBuffer, isFrontCamera: frame.mirrored)
    let mpImage = try MPImage(sampleBuffer: frame.sampleBuffer, orientation: inputTransform.orientation)
    let timestampMs = max(0, Int(frame.timestamp * 1000.0))

    let poseResult = try poseLandmarker.detect(videoFrame: mpImage, timestampInMilliseconds: timestampMs)
    let poseLandmarks = poseResult.landmarks.first ?? []

    let canonicalMirroringNeeded = frame.mirrored && !inputTransform.appliedMirroring
    var mapped = mapPoseLandmarks(poseLandmarks, mirrored: canonicalMirroringNeeded, timestamp: frame.timestamp)
    if let roiHint = frame.roiHint,
       frame.reacquireSource == .previousTrack || frame.reacquireSource == .face || frame.reacquireSource == .upperBody {
      mapped = applyROIGating(to: mapped, roi: roiHint)
    }
    var handRefinedJointCount = 0

    if !mapped.isEmpty,
       let handLandmarker,
       config.mediaPipe.enableHandRefinement {
      let handResult = try? handLandmarker.detect(videoFrame: mpImage, timestampInMilliseconds: timestampMs)
      if let handResult {
        handRefinedJointCount = applyHandRefinement(
          handResult: handResult,
          joints: &mapped,
          mirrored: canonicalMirroringNeeded,
          timestamp: frame.timestamp
        )
      }
    }

    if mapped[.head] == nil, let nose = mapped[.nose] {
      mapped[.head] = PoseJointMeasurement(
        name: .head,
        point: nose.point,
        confidence: nose.confidence,
        visibility: nose.visibility,
        presence: nose.presence,
        sourceType: nose.sourceType,
        inFrame: nose.inFrame,
        backend: kind,
        measuredAt: frame.timestamp
      )
    }

    mapped = applyTooCloseHardCutoff(to: mapped, timestamp: frame.timestamp)

    let detectedJointCount = mapped.count
    let measured = detectedJointCount >= 3 ? mapped : [:]
    let coverage = PoseCoverageCalculator.coverage(measured: measured)

    let hasFullLower = measured[.leftKnee] != nil && measured[.rightKnee] != nil && measured[.leftAnkle] != nil && measured[.rightAnkle] != nil
    let mode: BodyTrackingMode
    if hasFullLower && coverage.fullBodyCoverage >= config.mode.fullBodyCoverageEnter {
      mode = .fullBody
    } else if coverage.upperBodyCoverage >= config.mode.upperBodyCoverageEnter {
      mode = .upperBody
    } else {
      mode = .unknown
    }

    let modeConfidence = mode == .fullBody ? coverage.fullBodyCoverage : coverage.upperBodyCoverage
    let avgConfidence = measured.isEmpty
      ? 0
      : measured.values.map { Double($0.confidence) }.reduce(0, +) / Double(measured.count)

    let diagnostics = PoseBackendDiagnostics(
      rawObservationCount: poseResult.landmarks.count,
      trackedJointCount: measured.count,
      averageJointConfidence: avgConfidence,
      roiUsed: frame.roiHint,
      durationMs: (CACurrentMediaTime() - started) * 1000,
      modeConfidence: modeConfidence,
      reliability: min(1, max(0, avgConfidence * 0.66 + coverage.upperBodyCoverage * 0.24 + coverage.handCoverage * 0.1)),
      handRefinedJointCount: handRefinedJointCount
    )

    return PoseProcessingResult(
      measured: measured,
      avgConfidence: avgConfidence,
      brightnessLuma: brightness,
      lowLightDetected: lowLightDetected,
      observationExists: !poseResult.landmarks.isEmpty,
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

  private func mapPoseLandmarks(
    _ landmarks: [NormalizedLandmark],
    mirrored: Bool,
    timestamp: TimeInterval
  ) -> [PushlyJointName: PoseJointMeasurement] {
    var output: [PushlyJointName: PoseJointMeasurement] = [:]

    let indexMap: [(PushlyJointName, Int)] = [
      (.nose, 0),
      (.leftShoulder, 11),
      (.rightShoulder, 12),
      (.leftElbow, 13),
      (.rightElbow, 14),
      (.leftWrist, 15),
      (.rightWrist, 16),
      (.leftHip, 23),
      (.rightHip, 24),
      (.leftKnee, 25),
      (.rightKnee, 26),
      (.leftAnkle, 27),
      (.rightAnkle, 28),
      (.leftFoot, 31),
      (.rightFoot, 32)
    ]

    for (jointName, index) in indexMap {
      guard index >= 0, index < landmarks.count else { continue }
      let landmark = landmarks[index]
      let normalizedPoint = PoseCoordinateConverter.canonicalPointFromMediaPipe(
        CGPoint(x: CGFloat(landmark.x), y: CGFloat(landmark.y)),
        mirrored: mirrored
      )

      let visibility = landmark.visibility ?? 0.8
      let presence = landmark.presence ?? visibility
      let confidence = Float(max(0, min(1, Double(visibility * 0.65 + presence * 0.35))))

      output[jointName] = PoseJointMeasurement(
        name: jointName,
        point: normalizedPoint,
        confidence: confidence,
        visibility: visibility,
        presence: presence,
        sourceType: confidence >= config.tracker.lowConfidenceMin ? .measured : .lowConfidenceMeasured,
        inFrame: landmark.x >= 0 && landmark.x <= 1 && landmark.y >= 0 && landmark.y <= 1,
        backend: kind,
        measuredAt: timestamp
      )
    }

    return output
  }

  private func applyHandRefinement(
    handResult: HandLandmarkerResult,
    joints: inout [PushlyJointName: PoseJointMeasurement],
    mirrored: Bool,
    timestamp: TimeInterval
  ) -> Int {
    guard !handResult.landmarks.isEmpty else {
      return 0
    }

    var candidates: [(point: CGPoint, confidence: Float)] = []
    for hand in handResult.landmarks {
      guard let wrist = hand.first else { continue }
      let point = PoseCoordinateConverter.canonicalPointFromMediaPipe(
        CGPoint(x: CGFloat(wrist.x), y: CGFloat(wrist.y)),
        mirrored: mirrored
      )
      let visibility = wrist.visibility ?? 0.75
      let presence = wrist.presence ?? visibility
      let confidence = Float(max(0, min(1, Double(visibility * 0.6 + presence * 0.4))))
      guard confidence >= config.mediaPipe.handRefinementMinConfidence else { continue }
      candidates.append((point: point, confidence: confidence))
    }

    guard !candidates.isEmpty else {
      return 0
    }

    candidates.sort { $0.point.x < $1.point.x }
    let leftCandidate = candidates.first
    let rightCandidate = candidates.count > 1 ? candidates.last : candidates.first

    var refinedCount = 0
    if let leftCandidate {
      refinedCount += 1
      let alpha = config.mediaPipe.handRefinementBlendAlpha
      let blended: CGPoint
      if let existing = joints[.leftWrist] {
        blended = CGPoint(
          x: existing.point.x + (leftCandidate.point.x - existing.point.x) * alpha,
          y: existing.point.y + (leftCandidate.point.y - existing.point.y) * alpha
        )
      } else {
        blended = leftCandidate.point
      }
      let confidence = max(leftCandidate.confidence, joints[.leftWrist]?.confidence ?? 0)
      let clamped = PoseCoordinateConverter.clampNormalizedPoint(blended)
      joints[.leftWrist] = PoseJointMeasurement(
        name: .leftWrist,
        point: clamped,
        confidence: confidence,
        visibility: confidence,
        presence: confidence,
        sourceType: .measured,
        inFrame: true,
        backend: kind,
        measuredAt: timestamp
      )
      joints[.leftHand] = PoseJointMeasurement(
        name: .leftHand,
        point: clamped,
        confidence: confidence,
        visibility: confidence,
        presence: confidence,
        sourceType: .measured,
        inFrame: true,
        backend: kind,
        measuredAt: timestamp
      )
    }

    if let rightCandidate {
      refinedCount += 1
      let alpha = config.mediaPipe.handRefinementBlendAlpha
      let blended: CGPoint
      if let existing = joints[.rightWrist] {
        blended = CGPoint(
          x: existing.point.x + (rightCandidate.point.x - existing.point.x) * alpha,
          y: existing.point.y + (rightCandidate.point.y - existing.point.y) * alpha
        )
      } else {
        blended = rightCandidate.point
      }
      let confidence = max(rightCandidate.confidence, joints[.rightWrist]?.confidence ?? 0)
      let clamped = PoseCoordinateConverter.clampNormalizedPoint(blended)
      joints[.rightWrist] = PoseJointMeasurement(
        name: .rightWrist,
        point: clamped,
        confidence: confidence,
        visibility: confidence,
        presence: confidence,
        sourceType: .measured,
        inFrame: true,
        backend: kind,
        measuredAt: timestamp
      )
      joints[.rightHand] = PoseJointMeasurement(
        name: .rightHand,
        point: clamped,
        confidence: confidence,
        visibility: confidence,
        presence: confidence,
        sourceType: .measured,
        inFrame: true,
        backend: kind,
        measuredAt: timestamp
      )
    }

    return refinedCount
  }

  private func applyROIGating(
    to joints: [PushlyJointName: PoseJointMeasurement],
    roi: CGRect
  ) -> [PushlyJointName: PoseJointMeasurement] {
    let padded = PoseCoordinateConverter.clampNormalizedROI(
      CGRect(
        x: roi.minX - roi.width * 0.12,
        y: roi.minY - roi.height * 0.12,
        width: roi.width * 1.24,
        height: roi.height * 1.24
      ),
      minSize: config.reacquire.roiMinSize
    )

    var output: [PushlyJointName: PoseJointMeasurement] = [:]
    for (name, joint) in joints {
      if padded.contains(joint.point) {
        output[name] = joint
      } else {
        output[name] = PoseJointMeasurement(
          name: name,
          point: joint.point,
          worldPoint: joint.worldPoint,
          confidence: joint.confidence * 0.4,
          visibility: joint.visibility * 0.6,
          presence: joint.presence * 0.6,
          sourceType: .lowConfidenceMeasured,
          inFrame: joint.inFrame,
          backend: joint.backend,
          measuredAt: joint.measuredAt
        )
      }
    }
    return output
  }

  private func applyTooCloseHardCutoff(
    to joints: [PushlyJointName: PoseJointMeasurement],
    timestamp: TimeInterval
  ) -> [PushlyJointName: PoseJointMeasurement] {
    var output = joints

    guard let leftShoulder = output[.leftShoulder], leftShoulder.confidence > 0.45,
          let rightShoulder = output[.rightShoulder], rightShoulder.confidence > 0.45 else {
      tooCloseLock.isActive = false
      return output
    }

    let leftHipWeak = isHipWeak(output[.leftHip])
    let rightHipWeak = isHipWeak(output[.rightHip])
    let tooCloseDetected = leftHipWeak || rightHipWeak

    if tooCloseDetected {
      let left = leftShoulder.point
      let right = rightShoulder.point
      let shoulderWidthRaw = hypot(right.x - left.x, right.y - left.y)
      guard shoulderWidthRaw.isFinite else {
        return output
      }
      let shoulderWidth = max(0.06, shoulderWidthRaw)
      let drop = shoulderWidth * 1.5

      if !tooCloseLock.isActive || timestamp > tooCloseLock.holdUntil {
        tooCloseLock.lockedLeftHip = PoseCoordinateConverter.clampNormalizedPoint(
          CGPoint(x: left.x, y: left.y - drop)
        )
        tooCloseLock.lockedRightHip = PoseCoordinateConverter.clampNormalizedPoint(
          CGPoint(x: right.x, y: right.y - drop)
        )
      }
      tooCloseLock.isActive = true
      tooCloseLock.holdUntil = timestamp + 0.2
    } else if tooCloseLock.isActive && timestamp < tooCloseLock.holdUntil {
      // Keep lock briefly to prevent on/off flicker around threshold.
    } else {
      tooCloseLock.isActive = false
    }

    guard tooCloseLock.isActive else {
      return output
    }

    let inferredVisibility = min(leftShoulder.visibility, rightShoulder.visibility) * 0.8
    let inferredPresence = min(leftShoulder.presence, rightShoulder.presence) * 0.8
    let inferredConfidence = min(leftShoulder.confidence, rightShoulder.confidence) * 0.75

    output[.leftHip] = PoseJointMeasurement(
      name: .leftHip,
      point: tooCloseLock.lockedLeftHip,
      confidence: inferredConfidence,
      visibility: inferredVisibility,
      presence: inferredPresence,
      sourceType: .inferred,
      inFrame: true,
      backend: kind,
      measuredAt: timestamp
    )
    output[.rightHip] = PoseJointMeasurement(
      name: .rightHip,
      point: tooCloseLock.lockedRightHip,
      confidence: inferredConfidence,
      visibility: inferredVisibility,
      presence: inferredPresence,
      sourceType: .inferred,
      inFrame: true,
      backend: kind,
      measuredAt: timestamp
    )

    let lowerBodyToSuppress: [PushlyJointName] = [.leftKnee, .rightKnee, .leftAnkle, .rightAnkle, .leftFoot, .rightFoot]
    for jointName in lowerBodyToSuppress {
      output[jointName] = PoseJointMeasurement(
        name: jointName,
        point: output[jointName]?.point ?? CGPoint(x: 0.5, y: 0.0),
        confidence: 0,
        visibility: 0,
        presence: 0,
        sourceType: .missing,
        inFrame: false,
        backend: kind,
        measuredAt: timestamp
      )
    }

    return output
  }

  private func isHipWeak(_ hip: PoseJointMeasurement?) -> Bool {
    guard let hip else { return true }
    let outOfBounds = !hip.inFrame || hip.point.y > 1.0
    return hip.confidence < 0.3 || outOfBounds
  }

  private func mediaPipeInputTransform(
    sampleBuffer: CMSampleBuffer,
    isFrontCamera: Bool
  ) -> MediaPipeInputTransform {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return MediaPipeInputTransform(
        orientation: isFrontCamera ? .upMirrored : .up,
        appliedMirroring: isFrontCamera
      )
    }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let isPortraitBuffer = height >= width

    if isPortraitBuffer {
      return MediaPipeInputTransform(
        orientation: isFrontCamera ? .upMirrored : .up,
        appliedMirroring: isFrontCamera
      )
    }

    // Sensor-native landscape buffers still need explicit rotation for portrait UI pipelines.
    return MediaPipeInputTransform(
      orientation: isFrontCamera ? .leftMirrored : .right,
      appliedMirroring: isFrontCamera
    )
  }

  private func emptyResult(
    frame: PoseFrameInput,
    brightness: Double,
    lowLightDetected: Bool,
    started: CFTimeInterval
  ) -> PoseProcessingResult {
    let diagnostics = PoseBackendDiagnostics(
      rawObservationCount: 0,
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

  private static func locateModel(fileName: String, fileExtension: String) -> String? {
    let classBundle = Bundle(for: MediaPipePoseBackend.self)
    let mainBundle = Bundle.main

    let bundles: [Bundle] = {
      var list = [classBundle, mainBundle]
      if let bundleURL = classBundle.url(forResource: "PushlyNativeResources", withExtension: "bundle"),
         let resourcesBundle = Bundle(url: bundleURL) {
        list.insert(resourcesBundle, at: 0)
      }
      return list
    }()

    for bundle in bundles {
      if let path = bundle.path(forResource: fileName, ofType: fileExtension) {
        return path
      }
    }

    return nil
  }
}

#else
final class MediaPipePoseBackend: PoseBackend {
  var kind: PoseBackendKind { .mediapipe }
  var isAvailable: Bool { false }

  init(config: PushlyPoseConfig, diagnostics: PoseDiagnostics? = nil) {}

  func process(frame: PoseFrameInput) throws -> PoseProcessingResult {
    PoseProcessingResult(
      measured: [:],
      avgConfidence: 0,
      brightnessLuma: 0.5,
      lowLightDetected: false,
      observationExists: false,
      detectedJointCount: 0,
      backend: kind,
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
#endif
