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
    var lockedHipCenter: CGPoint = .zero
    var lockedHipHalfSpan: CGFloat = 0.06
    var lockedShoulderAxis: CGVector = CGVector(dx: 1, dy: 0)
    var torsoDirection: CGVector = CGVector(dx: 0, dy: -1)
  }

  private let config: PushlyPoseConfig
  private let diagnostics: PoseDiagnostics?
  private let poseLandmarker: PoseLandmarker?
  private let handLandmarker: HandLandmarker?
  private var tooCloseLock = TooCloseLockState()
  private var segmentationPresenceEMA: Double = 0

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
      gpuOptions.shouldOutputSegmentationMasks = config.mediaPipe.enablePoseSegmentationPresenceAssist

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
        cpuOptions.shouldOutputSegmentationMasks = config.mediaPipe.enablePoseSegmentationPresenceAssist
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
    let segmentationCoverage = updateSegmentationPresence(from: poseResult.segmentationMasks)

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
    let tooCloseInferredHipCount = [PushlyJointName.leftHip, .rightHip].reduce(0) { partial, name in
      guard let joint = mapped[name], joint.sourceType == .inferred else { return partial }
      return partial + 1
    }
    let tooCloseFallbackActive = tooCloseInferredHipCount > 0

    let segmentationAssistActive =
      config.mediaPipe.enablePoseSegmentationPresenceAssist &&
      segmentationCoverage >= config.mediaPipe.poseSegmentationAssistCoverageThreshold
    let detectedJointCount = mapped.count
    let minMeasuredJoints = segmentationAssistActive
      ? max(1, config.mediaPipe.poseSegmentationRelaxedMeasuredMinJoints)
      : 3
    let measured = detectedJointCount >= minMeasuredJoints ? mapped : [:]
    let coverage = PoseCoverageCalculator.coverage(measured: measured)
    let segmentationBottomAssistActive =
      config.mediaPipe.enablePoseSegmentationPresenceAssist
      && segmentationCoverage >= config.mediaPipe.poseSegmentationBottomAssistCoverageThreshold
      && (
        isLikelyFloorState(joints: mapped)
          || coverage.upperBodyCoverage >= config.mediaPipe.poseSegmentationBottomAssistUpperCoverageFloor
      )

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
      handRefinedJointCount: handRefinedJointCount,
      segmentationAssistActive: segmentationAssistActive,
      segmentationBottomAssistActive: segmentationBottomAssistActive,
      segmentationPresenceCoverage: segmentationCoverage,
      tooCloseFallbackActive: tooCloseFallbackActive,
      tooCloseInferredHipCount: tooCloseInferredHipCount
    )

    return PoseProcessingResult(
      measured: measured,
      avgConfidence: avgConfidence,
      brightnessLuma: brightness,
      lowLightDetected: lowLightDetected,
      observationExists: !poseResult.landmarks.isEmpty || segmentationAssistActive,
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

    let floorState = isLikelyFloorState(joints: output)
    let leftHipWeak = isHipWeak(output[.leftHip], floorState: floorState)
    let rightHipWeak = isHipWeak(output[.rightHip], floorState: floorState)
    let shoulderWidthRaw = hypot(
      rightShoulder.point.x - leftShoulder.point.x,
      rightShoulder.point.y - leftShoulder.point.y
    )
    guard shoulderWidthRaw.isFinite, shoulderWidthRaw > 0.0001 else {
      return output
    }
    let shoulderWidth = max(0.06, shoulderWidthRaw)
    let nearCameraHint = shoulderWidthRaw > 0.17
    let tooCloseDetected = nearCameraHint && (leftHipWeak || rightHipWeak)
    let shoulderMid = CGPoint(
      x: (leftShoulder.point.x + rightShoulder.point.x) * 0.5,
      y: (leftShoulder.point.y + rightShoulder.point.y) * 0.5
    )
    guard isFinitePoint(shoulderMid) else {
      return output
    }
    let shoulderAxis = normalizeOrFallback(
      CGVector(
        dx: rightShoulder.point.x - leftShoulder.point.x,
        dy: rightShoulder.point.y - leftShoulder.point.y
      ),
      fallback: tooCloseLock.lockedShoulderAxis
    )
    guard isFiniteVector(shoulderAxis) else {
      return output
    }
    let downDirection = torsoDownDirection(
      joints: output,
      shoulderMid: shoulderMid,
      shoulderAxis: shoulderAxis,
      fallback: tooCloseLock.torsoDirection
    )

    if floorState {
      tooCloseLock.isActive = false
      tooCloseLock.torsoDirection = downDirection
      output = applyFloorStateLowerBodyRetention(
        to: output,
        leftShoulder: leftShoulder,
        rightShoulder: rightShoulder,
        timestamp: timestamp
      )
      return output
    }

    if tooCloseDetected {
      // Previous hard fallback snapped hips directly under shoulders and suppressed lower body,
      // which produced abrupt lateral jumps and occasional geometric side inversions.
      let currentGeometry = hipGeometry(
        joints: output,
        shoulderAxis: shoulderAxis,
        shoulderMid: shoulderMid,
        shoulderWidth: shoulderWidth,
        downDirection: downDirection
      )

      var alignedShoulderAxis = shoulderAxis
      let axisDot = tooCloseLock.lockedShoulderAxis.dx * shoulderAxis.dx + tooCloseLock.lockedShoulderAxis.dy * shoulderAxis.dy
      if tooCloseLock.isActive && axisDot < 0 {
        alignedShoulderAxis = shoulderAxis * -1
      }

      if !tooCloseLock.isActive || timestamp > tooCloseLock.holdUntil {
        tooCloseLock.lockedHipCenter = currentGeometry.center
        tooCloseLock.lockedHipHalfSpan = currentGeometry.halfSpan
        tooCloseLock.lockedShoulderAxis = alignedShoulderAxis
      } else {
        let alpha: CGFloat = 0.24
        tooCloseLock.lockedHipCenter = blendPoint(tooCloseLock.lockedHipCenter, currentGeometry.center, alpha: alpha)
        tooCloseLock.lockedHipHalfSpan = blendScalar(tooCloseLock.lockedHipHalfSpan, currentGeometry.halfSpan, alpha: alpha)
        tooCloseLock.lockedShoulderAxis = normalizeOrFallback(
          blendVector(tooCloseLock.lockedShoulderAxis, alignedShoulderAxis, alpha: 0.24),
          fallback: tooCloseLock.lockedShoulderAxis
        )
      }
      tooCloseLock.torsoDirection = normalizeOrFallback(
        blendVector(tooCloseLock.torsoDirection, downDirection, alpha: 0.28),
        fallback: tooCloseLock.torsoDirection
      )
      tooCloseLock.isActive = true
      tooCloseLock.holdUntil = timestamp + 0.28
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
    let stableShoulderAxis = tooCloseLock.lockedShoulderAxis
    let hipHalfSpan = max(shoulderWidth * 0.22, tooCloseLock.lockedHipHalfSpan)
    let inferredLeftHip = PoseCoordinateConverter.clampNormalizedPoint(
      CGPoint(
        x: tooCloseLock.lockedHipCenter.x - stableShoulderAxis.dx * hipHalfSpan,
        y: tooCloseLock.lockedHipCenter.y - stableShoulderAxis.dy * hipHalfSpan
      )
    )
    let inferredRightHip = PoseCoordinateConverter.clampNormalizedPoint(
      CGPoint(
        x: tooCloseLock.lockedHipCenter.x + stableShoulderAxis.dx * hipHalfSpan,
        y: tooCloseLock.lockedHipCenter.y + stableShoulderAxis.dy * hipHalfSpan
      )
    )
    guard isFinitePoint(inferredLeftHip), isFinitePoint(inferredRightHip) else {
      return output
    }

    if leftHipWeak {
      output[.leftHip] = PoseJointMeasurement(
        name: .leftHip,
        point: inferredLeftHip,
        confidence: inferredConfidence,
        visibility: inferredVisibility,
        presence: inferredPresence,
        sourceType: .inferred,
        inFrame: true,
        backend: kind,
        measuredAt: timestamp
      )
    }
    if rightHipWeak {
      output[.rightHip] = PoseJointMeasurement(
        name: .rightHip,
        point: inferredRightHip,
        confidence: inferredConfidence,
        visibility: inferredVisibility,
        presence: inferredPresence,
        sourceType: .inferred,
        inFrame: true,
        backend: kind,
        measuredAt: timestamp
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
    joints: [PushlyJointName: PoseJointMeasurement]
  ) -> Bool {
    guard let nose = joints[.nose],
          let leftShoulder = joints[.leftShoulder],
          let rightShoulder = joints[.rightShoulder],
          nose.confidence >= 0.08 else {
      return false
    }

    let floorThreshold: CGFloat = 0.15
    let leftVerticalDistance = abs(nose.point.y - leftShoulder.point.y)
    let rightVerticalDistance = abs(nose.point.y - rightShoulder.point.y)
    return leftVerticalDistance < floorThreshold && rightVerticalDistance < floorThreshold
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

  private func hipGeometry(
    joints: [PushlyJointName: PoseJointMeasurement],
    shoulderAxis: CGVector,
    shoulderMid: CGPoint,
    shoulderWidth: CGFloat,
    downDirection: CGVector
  ) -> (center: CGPoint, halfSpan: CGFloat) {
    if let leftHip = joints[.leftHip], let rightHip = joints[.rightHip],
       !isHipWeak(leftHip, floorState: false), !isHipWeak(rightHip, floorState: false) {
      let center = PoseCoordinateConverter.clampNormalizedPoint(
        CGPoint(
          x: (leftHip.point.x + rightHip.point.x) * 0.5,
          y: (leftHip.point.y + rightHip.point.y) * 0.5
        )
      )
      let measuredHalfSpan = distanceAlongAxis(from: center, to: rightHip.point, axis: shoulderAxis)
      let safeMeasuredHalfSpan = measuredHalfSpan.isFinite ? measuredHalfSpan : shoulderWidth * 0.3
      let halfSpan = max(shoulderWidth * 0.2, min(shoulderWidth * 0.5, safeMeasuredHalfSpan))
      return (center, halfSpan)
    }

    let drop = shoulderWidth * 0.95
    let center = PoseCoordinateConverter.clampNormalizedPoint(
      CGPoint(
        x: shoulderMid.x + downDirection.dx * drop,
        y: shoulderMid.y + downDirection.dy * drop
      )
    )
    let halfSpan = shoulderWidth * 0.32
    return (center, halfSpan)
  }

  private func torsoDownDirection(
    joints: [PushlyJointName: PoseJointMeasurement],
    shoulderMid: CGPoint,
    shoulderAxis: CGVector,
    fallback: CGVector
  ) -> CGVector {
    let fallbackDown = normalizeOrFallback(fallback, fallback: CGVector(dx: 0, dy: -1))
    if let leftHip = joints[.leftHip], let rightHip = joints[.rightHip],
       !isHipWeak(leftHip, floorState: false), !isHipWeak(rightHip, floorState: false) {
      let hipMid = CGPoint(
        x: (leftHip.point.x + rightHip.point.x) * 0.5,
        y: (leftHip.point.y + rightHip.point.y) * 0.5
      )
      let candidate = CGVector(dx: hipMid.x - shoulderMid.x, dy: hipMid.y - shoulderMid.y)
      return normalizeOrFallback(candidate, fallback: fallbackDown)
    }
    var orthogonal = normalizeOrFallback(CGVector(dx: -shoulderAxis.dy, dy: shoulderAxis.dx), fallback: fallbackDown)
    if orthogonal.dy > 0 {
      orthogonal = orthogonal * -1
    }
    return normalizeOrFallback(blendVector(fallbackDown, orthogonal, alpha: 0.3), fallback: fallbackDown)
  }

  private func distanceAlongAxis(from a: CGPoint, to b: CGPoint, axis: CGVector) -> CGFloat {
    guard isFinitePoint(a), isFinitePoint(b), isFiniteVector(axis) else {
      return 0
    }
    let delta = CGVector(dx: b.x - a.x, dy: b.y - a.y)
    return abs(delta.dx * axis.dx + delta.dy * axis.dy)
  }

  private func blendPoint(_ a: CGPoint, _ b: CGPoint, alpha: CGFloat) -> CGPoint {
    CGPoint(
      x: a.x + (b.x - a.x) * alpha,
      y: a.y + (b.y - a.y) * alpha
    )
  }

  private func blendScalar(_ a: CGFloat, _ b: CGFloat, alpha: CGFloat) -> CGFloat {
    a + (b - a) * alpha
  }

  private func blendVector(_ a: CGVector, _ b: CGVector, alpha: CGFloat) -> CGVector {
    CGVector(
      dx: a.dx + (b.dx - a.dx) * alpha,
      dy: a.dy + (b.dy - a.dy) * alpha
    )
  }

  private func normalize(_ vector: CGVector) -> CGVector {
    let m = hypot(vector.dx, vector.dy)
    guard m > 0.0001 else { return CGVector(dx: 0, dy: -1) }
    return CGVector(dx: vector.dx / m, dy: vector.dy / m)
  }

  private func normalizeOrFallback(_ vector: CGVector, fallback: CGVector) -> CGVector {
    guard isFiniteVector(vector) else {
      return normalize(fallback)
    }
    let m = hypot(vector.dx, vector.dy)
    guard m > 0.0001 else {
      return normalize(fallback)
    }
    return CGVector(dx: vector.dx / m, dy: vector.dy / m)
  }

  private func isFinitePoint(_ point: CGPoint) -> Bool {
    point.x.isFinite && point.y.isFinite
  }

  private func isFiniteVector(_ vector: CGVector) -> Bool {
    vector.dx.isFinite && vector.dy.isFinite
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

  private func updateSegmentationPresence(from masks: [Mask]) -> Double {
    guard config.mediaPipe.enablePoseSegmentationPresenceAssist else {
      segmentationPresenceEMA = 0
      return 0
    }

    let rawCoverage = segmentationCoverage(from: masks.first)
    let alpha = max(0.01, min(1, config.mediaPipe.poseSegmentationSmoothingAlpha))
    segmentationPresenceEMA += (rawCoverage - segmentationPresenceEMA) * alpha
    return segmentationPresenceEMA
  }

  private func segmentationCoverage(from mask: Mask?) -> Double {
    guard let mask else { return 0 }
    let width = max(0, mask.width)
    let height = max(0, mask.height)
    guard width > 0, height > 0 else { return 0 }

    let stride = max(1, config.mediaPipe.poseSegmentationSampleStride)
    let threshold = max(0, min(1, config.mediaPipe.poseSegmentationForegroundThreshold))
    let values = mask.float32Data

    var fgCount = 0
    var totalCount = 0
    var y = 0
    while y < height {
      var x = 0
      while x < width {
        let index = y * width + x
        if values[index] >= threshold {
          fgCount += 1
        }
        totalCount += 1
        x += stride
      }
      y += stride
    }

    guard totalCount > 0 else { return 0 }
    return Double(fgCount) / Double(totalCount)
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
