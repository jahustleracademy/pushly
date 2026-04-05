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

    if let poseModelSelection = Self.locatePoseModel(config: config) {
      let poseModelPath = poseModelSelection.path
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
        "poseModelName": poseModelSelection.fileName,
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

    // Intentionally ignore frame.mirrored. MediaPipe always consumes native, unmirrored camera frames.
    let inputOrientation = mediaPipeInputOrientation(sampleBuffer: frame.sampleBuffer)
    let mpImage = try MPImage(sampleBuffer: frame.sampleBuffer, orientation: inputOrientation)
    let timestampMs = max(0, Int(frame.timestamp * 1000.0))

    let poseResult = try poseLandmarker.detect(videoFrame: mpImage, timestampInMilliseconds: timestampMs)
    let poseLandmarks = poseResult.landmarks.first ?? []

    var mapped = mapPoseLandmarks(poseLandmarks, mirrored: false, timestamp: frame.timestamp)
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
          mirrored: false,
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

    guard let leftShoulder = output[.leftShoulder],
          let rightShoulder = output[.rightShoulder] else {
      tooCloseLock.isActive = false
      return output
    }

    let minimumShoulderConfidence: Float = 0.12
    guard leftShoulder.confidence >= minimumShoulderConfidence,
          rightShoulder.confidence >= minimumShoulderConfidence else {
      tooCloseLock.isActive = false
      return output
    }

    let floorState = isLikelyFloorState(joints: output, leftShoulder: leftShoulder)
    let leftHipWeak = isHipWeak(output[.leftHip], floorState: floorState)
    let rightHipWeak = isHipWeak(output[.rightHip], floorState: floorState)
    let tooCloseDetected = leftHipWeak || rightHipWeak

    if floorState {
      tooCloseLock.isActive = false
      output = applyFloorStateLowerBodyRetention(
        to: output,
        leftShoulder: leftShoulder,
        rightShoulder: rightShoulder,
        timestamp: timestamp
      )
      return output
    }

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
      tooCloseLock.holdUntil = timestamp + 0.32
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
      output[jointName] = occludedJointMeasurement(
        name: jointName,
        fallbackPoint: output[jointName]?.point ?? CGPoint(x: 0.5, y: 0.0),
        timestamp: timestamp
      )
    }

    return output
  }

  private func isHipWeak(_ hip: PoseJointMeasurement?, floorState: Bool) -> Bool {
    guard let hip else { return true }
    let outOfBounds = !hip.inFrame || hip.point.y > 1.0 || hip.point.x < 0.0 || hip.point.x > 1.0
    let confidenceThreshold: Float = floorState ? 0.08 : 0.3
    let visibilityThreshold: Float = floorState ? 0.06 : 0.22
    let presenceThreshold: Float = floorState ? 0.06 : 0.2
    return hip.confidence < confidenceThreshold
      || hip.visibility < visibilityThreshold
      || hip.presence < presenceThreshold
      || outOfBounds
  }

  private func isLikelyFloorState(
    joints: [PushlyJointName: PoseJointMeasurement],
    leftShoulder: PoseJointMeasurement
  ) -> Bool {
    guard let nose = joints[.nose], nose.confidence >= 0.08 else {
      return false
    }
    return abs(nose.point.y - leftShoulder.point.y) < 0.15
  }

  private func applyFloorStateLowerBodyRetention(
    to joints: [PushlyJointName: PoseJointMeasurement],
    leftShoulder: PoseJointMeasurement,
    rightShoulder: PoseJointMeasurement,
    timestamp: TimeInterval
  ) -> [PushlyJointName: PoseJointMeasurement] {
    var output = joints

    let shoulderWidth = max(0.06, hypot(
      rightShoulder.point.x - leftShoulder.point.x,
      rightShoulder.point.y - leftShoulder.point.y
    ))
    let hipYOffset = shoulderWidth * 0.18
    let kneeBackOffset = shoulderWidth * 0.82
    let ankleBackOffset = shoulderWidth * 1.55
    let footBackOffset = shoulderWidth * 1.95

    let leftHipFallback = CGPoint(x: leftShoulder.point.x - shoulderWidth * 0.55, y: leftShoulder.point.y - hipYOffset)
    let rightHipFallback = CGPoint(x: rightShoulder.point.x + shoulderWidth * 0.55, y: rightShoulder.point.y - hipYOffset)

    output[.leftHip] = lowConfidenceJointMeasurement(
      name: .leftHip,
      point: retainedFloorPoint(existing: output[.leftHip], fallback: leftHipFallback, minimumConfidence: 0.2),
      timestamp: timestamp
    )
    output[.rightHip] = lowConfidenceJointMeasurement(
      name: .rightHip,
      point: retainedFloorPoint(existing: output[.rightHip], fallback: rightHipFallback, minimumConfidence: 0.2),
      timestamp: timestamp
    )

    let leftHipPoint = output[.leftHip]?.point ?? PoseCoordinateConverter.clampNormalizedPoint(leftHipFallback)
    let rightHipPoint = output[.rightHip]?.point ?? PoseCoordinateConverter.clampNormalizedPoint(rightHipFallback)

    output[.leftKnee] = lowConfidenceJointMeasurement(
      name: .leftKnee,
      point: retainedFloorPoint(
        existing: output[.leftKnee],
        fallback: CGPoint(x: leftHipPoint.x - kneeBackOffset, y: leftHipPoint.y),
        minimumConfidence: 0.16
      ),
      timestamp: timestamp
    )
    output[.rightKnee] = lowConfidenceJointMeasurement(
      name: .rightKnee,
      point: retainedFloorPoint(
        existing: output[.rightKnee],
        fallback: CGPoint(x: rightHipPoint.x + kneeBackOffset, y: rightHipPoint.y),
        minimumConfidence: 0.16
      ),
      timestamp: timestamp
    )
    output[.leftAnkle] = lowConfidenceJointMeasurement(
      name: .leftAnkle,
      point: retainedFloorPoint(
        existing: output[.leftAnkle],
        fallback: CGPoint(x: leftHipPoint.x - ankleBackOffset, y: leftHipPoint.y),
        minimumConfidence: 0.14
      ),
      timestamp: timestamp
    )
    output[.rightAnkle] = lowConfidenceJointMeasurement(
      name: .rightAnkle,
      point: retainedFloorPoint(
        existing: output[.rightAnkle],
        fallback: CGPoint(x: rightHipPoint.x + ankleBackOffset, y: rightHipPoint.y),
        minimumConfidence: 0.14
      ),
      timestamp: timestamp
    )
    output[.leftFoot] = lowConfidenceJointMeasurement(
      name: .leftFoot,
      point: retainedFloorPoint(
        existing: output[.leftFoot],
        fallback: CGPoint(x: leftHipPoint.x - footBackOffset, y: leftHipPoint.y),
        minimumConfidence: 0.12
      ),
      timestamp: timestamp
    )
    output[.rightFoot] = lowConfidenceJointMeasurement(
      name: .rightFoot,
      point: retainedFloorPoint(
        existing: output[.rightFoot],
        fallback: CGPoint(x: rightHipPoint.x + footBackOffset, y: rightHipPoint.y),
        minimumConfidence: 0.12
      ),
      timestamp: timestamp
    )

    return output
  }

  private func occludedJointMeasurement(
    name: PushlyJointName,
    fallbackPoint: CGPoint,
    timestamp: TimeInterval
  ) -> PoseJointMeasurement {
    PoseJointMeasurement(
      name: name,
      point: PoseCoordinateConverter.clampNormalizedPoint(fallbackPoint),
      confidence: 0.08,
      visibility: 0.08,
      presence: 0.08,
      sourceType: .lowConfidenceMeasured,
      inFrame: true,
      backend: kind,
      measuredAt: timestamp
    )
  }

  private func lowConfidenceJointMeasurement(
    name: PushlyJointName,
    point: CGPoint,
    timestamp: TimeInterval
  ) -> PoseJointMeasurement {
    PoseJointMeasurement(
      name: name,
      point: PoseCoordinateConverter.clampNormalizedPoint(point),
      confidence: 0.18,
      visibility: 0.18,
      presence: 0.18,
      sourceType: .lowConfidenceMeasured,
      inFrame: true,
      backend: kind,
      measuredAt: timestamp
    )
  }

  private func retainedFloorPoint(
    existing: PoseJointMeasurement?,
    fallback: CGPoint,
    minimumConfidence: Float
  ) -> CGPoint {
    guard let existing,
          existing.inFrame,
          existing.confidence >= minimumConfidence,
          existing.visibility >= minimumConfidence * 0.7,
          existing.presence >= minimumConfidence * 0.7 else {
      return PoseCoordinateConverter.clampNormalizedPoint(fallback)
    }
    return PoseCoordinateConverter.clampNormalizedPoint(existing.point)
  }

  private func mediaPipeInputOrientation(
    sampleBuffer: CMSampleBuffer
  ) -> UIImage.Orientation {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return .up
    }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let isPortraitBuffer = height >= width

    if isPortraitBuffer {
      return .up
    }

    // Sensor-native landscape buffers still need explicit rotation for portrait UI pipelines.
    return .right
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

  private static func locatePoseModel(config: PushlyPoseConfig) -> (fileName: String, path: String)? {
    for modelName in config.mediaPipe.preferredPoseModelFileNames {
      if let path = locateModel(fileName: modelName, fileExtension: config.mediaPipe.poseModelFileExtension) {
        return (modelName, path)
      }
    }
    if let path = locateModel(fileName: config.mediaPipe.poseModelFileName, fileExtension: config.mediaPipe.poseModelFileExtension) {
      return (config.mediaPipe.poseModelFileName, path)
    }
    return nil
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
