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

    smoothedElbowAngle = smoothedElbowAngle * (1 - config.rep.elbowSmoothAlpha) + signal.elbowAngle * config.rep.elbowSmoothAlpha
    if smoothedShoulderY == 0 {
      smoothedShoulderY = signal.shoulderY
      previousShoulderY = signal.shoulderY
    } else {
      previousShoulderY = smoothedShoulderY
      smoothedShoulderY = smoothedShoulderY * (1 - config.rep.shoulderSmoothAlpha) + signal.shoulderY * config.rep.shoulderSmoothAlpha
    }
    let shoulderVelocity = smoothedShoulderY - previousShoulderY

    var blockedReasons: [String] = []
    if quality.logicQuality < config.rep.minLogicQualityToProgress {
      blockedReasons.append("logic_quality_low")
    }
    if signal.measuredEvidence < config.rep.minMeasuredEvidence {
      blockedReasons.append("measured_evidence_low")
    }
    if signal.torsoStability < config.rep.minTorsoStability {
      blockedReasons.append("torso_unstable")
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
      if smoothedElbowAngle < config.rep.descendAngleMax && shoulderVelocity > config.rep.shoulderVelocityMinForDescent {
        state = .descending
      }
      if smoothedElbowAngle < config.rep.bottomAngleMax && shoulderVelocity > config.rep.shoulderVelocityMinForDescent {
        state = .bottomReached
        bottomReached = true
      }
      if bottomReached && smoothedElbowAngle > config.rep.ascendAngleMin && shoulderVelocity < -config.rep.shoulderVelocityMinForAscent {
        state = .ascending
      }
      if bottomReached && smoothedElbowAngle > config.rep.repCompleteAngleMin &&
        quality.logicQuality >= config.rep.minLogicQualityToCount &&
        signal.measuredEvidence >= config.rep.minMeasuredEvidence &&
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
    formScore: Double,
    hasRenderableBody: Bool
  ) {
    let shoulderPair = bestPair(joints[.leftShoulder], joints[.rightShoulder])
    let hipPair = bestPair(joints[.leftHip], joints[.rightHip])
    let anklePair = bestPair(joints[.leftAnkle], joints[.rightAnkle], fallback: bestPair(joints[.leftKnee], joints[.rightKnee]))

    let arm = bestArm(joints: joints)
    let elbowAngle = arm.map { angle(a: $0.shoulder.smoothedPosition, b: $0.elbow.smoothedPosition, c: $0.wrist.smoothedPosition) } ?? 180

    let shoulderY = shoulderPair?.smoothedPosition.y ?? arm?.shoulder.smoothedPosition.y ?? 0.5

    let torsoStability: Double
    if let shoulder = shoulderPair, let hip = hipPair, let ankle = anklePair {
      let bodyAngle = angle(a: shoulder.smoothedPosition, b: hip.smoothedPosition, c: ankle.smoothedPosition)
      torsoStability = max(0, min(1, 1 - Double(abs(bodyAngle - 180)) / 44.0))
    } else if shoulderPair != nil && hipPair != nil {
      torsoStability = 0.54
    } else {
      torsoStability = 0.32
    }

    let usable = joints.values.filter(\.isLogicUsable)
    let measuredLike = usable.filter { $0.sourceType == .measured || $0.sourceType == .lowConfidenceMeasured }
    let measuredEvidence = usable.isEmpty ? 0 : Double(measuredLike.count) / Double(usable.count)

    let formScore = max(0.16, min(0.99, torsoStability * 0.68 + measuredEvidence * 0.32))
    let hasRenderableBody = joints.values.filter(\.isRenderable).count >= 4

    return (elbowAngle, shoulderY, torsoStability, measuredEvidence, formScore, hasRenderableBody)
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
}
#endif
