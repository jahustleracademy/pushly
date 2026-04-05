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
  }

  func update(
    joints: [PushlyJointName: TrackedJoint],
    quality: TrackingQuality,
    repTarget: Int
  ) -> RepDetectionOutput {
    let signal = computeSignal(joints: joints)

    guard signal.hasRenderableBody else {
      state = .lostTracking
      plankFrames = 0
      bottomReached = false
      return RepDetectionOutput(state: state, repCount: repCount, formScore: signal.formScore, blockedReasons: ["body_not_found"])
    }

    previousSmoothedElbowAngle = smoothedElbowAngle
    smoothedElbowAngle = smoothedElbowAngle * (1 - config.rep.elbowSmoothAlpha) + signal.elbowAngle * config.rep.elbowSmoothAlpha
    if smoothedShoulderY == 0 {
      smoothedShoulderY = signal.shoulderY
      previousShoulderY = signal.shoulderY
    } else {
      previousShoulderY = smoothedShoulderY
      smoothedShoulderY = smoothedShoulderY * (1 - config.rep.shoulderSmoothAlpha) + signal.shoulderY * config.rep.shoulderSmoothAlpha
    }
    let shoulderVelocity = smoothedShoulderY - previousShoulderY
    let elbowVelocity = smoothedElbowAngle - previousSmoothedElbowAngle

    var blockedReasons: [String] = []
    if quality.logicQuality < config.rep.minLogicQualityToProgress {
      blockedReasons.append("logic_quality_low")
    }
    if max(signal.measuredEvidence, signal.structuralEvidence) < config.rep.minMeasuredEvidence {
      blockedReasons.append("measured_evidence_low")
    }
    if signal.torsoStability < config.rep.minTorsoStability {
      blockedReasons.append("torso_unstable")
    }
    let floorState = signal.pushupFloorState
    if floorState && blockedReasons.contains("measured_evidence_low") {
      blockedReasons.removeAll { $0 == "measured_evidence_low" }
    }
    if floorState && blockedReasons.contains("torso_unstable") && signal.torsoStability >= 0.26 {
      blockedReasons.removeAll { $0 == "torso_unstable" }
    }
    let logicReady = blockedReasons.isEmpty

    if !logicReady {
      if quality.renderQuality >= config.quality.renderMin {
        state = .trackingAssisted
      } else {
        state = .lostTracking
      }
      return RepDetectionOutput(state: state, repCount: repCount, formScore: signal.formScore, blockedReasons: blockedReasons)
    }

    if smoothedElbowAngle > config.rep.plankAngleMin, signal.torsoStability > config.rep.minTorsoStability {
      plankFrames += 1
      if plankFrames >= config.rep.plankLockFrames {
        state = .plankLocked
      } else {
        state = .bodyFound
      }
    } else if state == .plankLocked || state == .descending || bottomReached {
      let descendingByShoulder = shoulderVelocity > config.rep.shoulderVelocityMinForDescent
      let ascendingByShoulder = shoulderVelocity < -config.rep.shoulderVelocityMinForAscent
      let descendingByElbow = elbowVelocity < (floorState ? -0.3 : -0.42)
      let ascendingByElbow = elbowVelocity > (floorState ? 0.3 : 0.42)
      let descendingSignal = descendingByShoulder || descendingByElbow
      let ascendingSignal = ascendingByShoulder || ascendingByElbow

      if smoothedElbowAngle < config.rep.descendAngleMax && descendingSignal {
        state = .descending
      }
      if smoothedElbowAngle < config.rep.bottomAngleMax && descendingSignal {
        state = .bottomReached
        bottomReached = true
      }
      if bottomReached && smoothedElbowAngle > config.rep.ascendAngleMin && ascendingSignal {
        state = .ascending
      }
      if bottomReached && smoothedElbowAngle > config.rep.repCompleteAngleMin &&
        quality.logicQuality >= config.rep.minLogicQualityToCount &&
        max(signal.measuredEvidence, signal.structuralEvidence) >= config.rep.minMeasuredEvidence &&
        signal.torsoStability >= config.rep.minTorsoStability {
        repCount += 1
        state = .repCounted
        bottomReached = false
        plankFrames = config.rep.plankLockFrames
      }
    } else {
      plankFrames = max(0, plankFrames - 1)
      state = .bodyFound
    }

    if repCount >= repTarget {
      state = .repCounted
    }

    return RepDetectionOutput(state: state, repCount: repCount, formScore: signal.formScore, blockedReasons: blockedReasons)
  }

  private func computeSignal(joints: [PushlyJointName: TrackedJoint]) -> (
    elbowAngle: CGFloat,
    shoulderY: CGFloat,
    torsoStability: Double,
    measuredEvidence: Double,
    structuralEvidence: Double,
    formScore: Double,
    hasRenderableBody: Bool,
    pushupFloorState: Bool
  ) {
    let shoulderPair = bestPair(joints[.leftShoulder], joints[.rightShoulder])
    let hipPair = bestPair(joints[.leftHip], joints[.rightHip])
    let anklePair = bestPair(joints[.leftAnkle], joints[.rightAnkle], fallback: bestPair(joints[.leftKnee], joints[.rightKnee]))
    let pushupFloorState = isLikelyPushupFloorState(joints: joints, shoulder: shoulderPair)

    let arm = bestArm(joints: joints)
    let elbowAngle = arm.map { angle(a: $0.shoulder.smoothedPosition, b: $0.elbow.smoothedPosition, c: $0.wrist.smoothedPosition) } ?? 180

    let shoulderY = shoulderPair?.smoothedPosition.y ?? arm?.shoulder.smoothedPosition.y ?? 0.5

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

    let usable = joints.values.filter(\.isLogicUsable)
    let measuredLike = usable.filter { $0.sourceType == .measured || $0.sourceType == .lowConfidenceMeasured }
    let measuredEvidence = usable.isEmpty ? 0 : Double(measuredLike.count) / Double(usable.count)
    let structuralEvidence = structuralEvidenceScore(joints: joints, floorState: pushupFloorState)

    let evidence = max(measuredEvidence, structuralEvidence)
    let formScore = max(0.16, min(0.99, torsoStability * 0.56 + evidence * 0.44))
    let hasRenderableBody = joints.values.filter(\.isRenderable).count >= 4 || (pushupFloorState && shoulderPair != nil && arm != nil)

    return (elbowAngle, shoulderY, torsoStability, measuredEvidence, structuralEvidence, formScore, hasRenderableBody, pushupFloorState)
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
    let required: [PushlyJointName] = floorState
      ? [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftHip, .rightHip]
      : [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftHip, .rightHip, .leftAnkle, .rightAnkle]
    let score = required.reduce(0.0) { partial, name in
      guard let joint = joints[name], joint.isRenderable else { return partial }
      let sourceWeight: Double
      switch joint.sourceType {
      case .measured:
        sourceWeight = 1.0
      case .lowConfidenceMeasured:
        sourceWeight = 0.85
      case .inferred:
        sourceWeight = floorState ? 0.72 : 0.42
      case .predicted:
        sourceWeight = 0.18
      case .missing:
        sourceWeight = 0
      }
      return partial + sourceWeight * Double(max(0.18, joint.renderConfidence))
    }
    return min(1, score / Double(required.count) * 1.4)
  }

  private func isLikelyPushupFloorState(
    joints: [PushlyJointName: TrackedJoint],
    shoulder: TrackedJoint?
  ) -> Bool {
    guard let nose = joints[.nose], nose.isRenderable else {
      return false
    }
    let shoulderMid = midpoint(shoulder?.smoothedPosition, joints[.rightShoulder]?.smoothedPosition)
    guard let shoulderMid else {
      return false
    }
    return abs(Double(nose.smoothedPosition.y - shoulderMid.y)) < 0.16
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
