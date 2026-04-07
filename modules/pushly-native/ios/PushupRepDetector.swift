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
  }

  func update(
    joints: [PushlyJointName: TrackedJoint],
    quality: TrackingQuality,
    repTarget: Int
  ) -> RepDetectionOutput {
    let signal = computeSignal(joints: joints)
    let floorState = quality.pushupFloorModeActive || signal.pushupFloorState
    let minMeasuredEvidence = floorState ? config.rep.floorMinMeasuredEvidence : config.rep.minMeasuredEvidence
    let minTorsoStability = floorState ? config.rep.floorMinTorsoStability : config.rep.minTorsoStability
    let minShoulderHipLineQuality = floorState ? config.rep.floorMinShoulderHipLineQuality : config.rep.minShoulderHipLineQuality
    let dominantEvidence = max(signal.measuredEvidence, signal.structuralEvidence, signal.upperBodyEvidence)

    guard signal.hasRenderableBody else {
      state = .lostTracking
      plankFrames = 0
      bottomReached = false
      bottomOcclusionFrames = 0
      return RepDetectionOutput(state: state, repCount: repCount, formEvidenceScore: signal.formEvidenceScore, blockedReasons: ["body_not_found"])
    }

    previousSmoothedElbowAngle = smoothedElbowAngle
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
    let elbowVelocity = smoothedElbowAngle - previousSmoothedElbowAngle
    let torsoVelocity = smoothedTorsoY - previousTorsoY
    let elbowVelocityMinForDescent = floorState ? config.rep.floorElbowVelocityMinForDescent : config.rep.elbowVelocityMinForDescent
    let elbowVelocityMinForAscent = floorState ? config.rep.floorElbowVelocityMinForAscent : config.rep.elbowVelocityMinForAscent

    var blockedReasons: [String] = []
    if quality.logicQuality < config.rep.minLogicQualityToProgress {
      blockedReasons.append("logic_quality_low")
    }
    if dominantEvidence < minMeasuredEvidence {
      blockedReasons.append("measured_evidence_low")
    }
    if signal.torsoStability < minTorsoStability {
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
    if floorState && blockedReasons.contains("torso_unstable") && signal.torsoStability >= 0.26 {
      blockedReasons.removeAll { $0 == "torso_unstable" }
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
    let canProgress = logicReady || logicBlockedFrames <= config.rep.logicGateGraceFrames

    if !canProgress {
      if quality.renderQuality >= config.quality.renderMin {
        state = .trackingAssisted
      } else {
        state = .lostTracking
      }
      descendingFrames = 0
      bottomFrames = 0
      ascendingFrames = 0
      bottomOcclusionFrames = 0
      return RepDetectionOutput(state: state, repCount: repCount, formEvidenceScore: signal.formEvidenceScore, blockedReasons: blockedReasons)
    }

    if signal.hasElbowMeasurement, smoothedElbowAngle > config.rep.plankAngleMin, signal.torsoStability > minTorsoStability {
      plankFrames += 1
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
      if plankFrames >= config.rep.plankLockFrames {
        state = .plankLocked
      } else {
        state = .bodyFound
      }
    } else if state == .plankLocked || state == .descending || state == .ascending || bottomReached {
      let descendingByShoulder = shoulderVelocity > config.rep.shoulderVelocityMinForDescent
      let ascendingByShoulder = shoulderVelocity < -config.rep.shoulderVelocityMinForAscent
      let descendingByElbow = signal.hasElbowMeasurement && elbowVelocity < -elbowVelocityMinForDescent
      let ascendingByElbow = signal.hasElbowMeasurement && elbowVelocity > elbowVelocityMinForAscent
      let descendingByTorso = torsoVelocity > config.rep.torsoVelocityMinForDescent
      let ascendingByTorso = torsoVelocity < -config.rep.torsoVelocityMinForAscent
      // Primary progression depends on torso/shoulder motion for frontal stability.
      let descendingSignal = descendingByTorso || descendingByShoulder
      let ascendingSignal = ascendingByTorso || ascendingByShoulder
      let torsoTopReference = hasFloorBaselineTorsoY ? floorBaselineTorsoY : repStartTorsoY
      let torsoDownTravel = max(0, repMaxTorsoY - torsoTopReference)
      let torsoRecoveryToTop = max(0, repMaxTorsoY - smoothedTorsoY)
      let shoulderDownTravel = max(0, repMaxShoulderY - repStartShoulderY)
      let shoulderRecoveryToTop = max(0, repMaxShoulderY - smoothedShoulderY)
      let elbowAtDescent = signal.hasElbowMeasurement && smoothedElbowAngle < config.rep.descendAngleMax
      let elbowAtBottom = signal.hasElbowMeasurement && smoothedElbowAngle < config.rep.bottomAngleMax
      let elbowAtAscent = signal.hasElbowMeasurement && smoothedElbowAngle > config.rep.ascendAngleMin
      let allowBottomOcclusion = bottomReached && bottomOcclusionFrames <= config.rep.bottomOcclusionGraceFrames
      let elbowSecondaryDescentConfirm = elbowAtDescent || descendingByElbow
      let elbowSecondaryAscendConfirm = elbowAtAscent || ascendingByElbow || allowBottomOcclusion

      if descendingSignal && elbowSecondaryDescentConfirm {
        if descendingFrames == 0 {
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
        repMaxShoulderY = max(repMaxShoulderY, smoothedShoulderY)
        repMaxTorsoY = max(repMaxTorsoY, smoothedTorsoY)
        if descendingFrames >= config.rep.descentConfirmFrames {
          state = .descending
        }
      } else {
        descendingFrames = max(0, descendingFrames - 1)
      }

      if elbowAtBottom || allowBottomOcclusion {
        if descendingSignal || state == .descending || bottomReached {
          bottomFrames += 1
        }
        if signal.hasElbowMeasurement {
          repMinElbowAngle = min(repMinElbowAngle, smoothedElbowAngle)
        }
        repMaxShoulderY = max(repMaxShoulderY, smoothedShoulderY)
        repMaxTorsoY = max(repMaxTorsoY, smoothedTorsoY)
        if bottomFrames >= config.rep.bottomConfirmFrames &&
          torsoDownTravel >= config.rep.minTorsoDownTravelForBottom &&
          shoulderDownTravel >= config.rep.minShoulderDownTravelForBottom {
          state = .bottomReached
          bottomReached = true
        }
      } else if !bottomReached {
        bottomFrames = max(0, bottomFrames - 1)
      }

      if bottomReached && elbowSecondaryAscendConfirm && ascendingSignal {
        ascendingFrames += 1
        if ascendingFrames >= config.rep.ascendingConfirmFrames {
          state = .ascending
        }
      } else if bottomReached {
        ascendingFrames = max(0, ascendingFrames - 1)
      }

      let repTravel = max(0, repStartElbowAngle - repMinElbowAngle)
      let elbowComplete = signal.hasElbowMeasurement && smoothedElbowAngle > config.rep.repCompleteAngleMin
      if bottomReached && elbowComplete &&
        ascendingFrames >= config.rep.ascendingConfirmFrames &&
        repMinElbowAngle < config.rep.bottomAngleMax &&
        repTravel >= config.rep.minRepAngleTravel &&
        torsoDownTravel >= config.rep.minTorsoCycleTravel &&
        torsoRecoveryToTop >= config.rep.minTorsoRecoveryTravel &&
        shoulderDownTravel >= config.rep.minShoulderCycleTravel &&
        shoulderRecoveryToTop >= config.rep.minShoulderRecoveryTravel &&
        smoothedTorsoY <= torsoTopReference + config.rep.maxTorsoTopRecoveryOffset &&
        quality.logicQuality >= config.rep.minLogicQualityToCount &&
        dominantEvidence >= minMeasuredEvidence &&
        signal.torsoStability >= minTorsoStability &&
        signal.shoulderHipLineQuality >= minShoulderHipLineQuality {
        repCount += 1
        state = .repCounted
        bottomReached = false
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
        if floorState {
          if hasFloorBaselineTorsoY {
            floorBaselineTorsoY = floorBaselineTorsoY * 0.8 + smoothedTorsoY * 0.2
          } else {
            floorBaselineTorsoY = smoothedTorsoY
            hasFloorBaselineTorsoY = true
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
      }
      state = .bodyFound
    }

    if repCount >= repTarget {
      state = .repCounted
    }

    return RepDetectionOutput(state: state, repCount: repCount, formEvidenceScore: signal.formEvidenceScore, blockedReasons: blockedReasons)
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
    let hasRenderableBody = joints.values.filter(\.isRenderable).count >= 4 || (pushupFloorState && shoulderPair != nil && bestRenderableArm != nil)

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
    guard let nose = joints[.nose], nose.isRenderable else {
      return false
    }
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
    return abs(Double(nose.smoothedPosition.y - shoulderMid.y)) < config.rep.floorStateNoseShoulderDeltaMax &&
      shoulderHipDelta < config.rep.floorStateShoulderHipDeltaMax
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
