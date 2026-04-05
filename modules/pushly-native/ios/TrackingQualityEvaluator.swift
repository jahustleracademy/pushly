import Foundation

#if os(iOS)
import CoreGraphics

final class TrackingQualityEvaluator {
  private let config: PushlyPoseConfig
  private var smoothedSpread: Double = 0.26
  private var hasSmoothedSpread = false

  init(config: PushlyPoseConfig) {
    self.config = config
  }

  func evaluate(
    joints: [PushlyJointName: TrackedJoint],
    lowLightDetected: Bool,
    trackingState: TrackingContinuityState,
    poseState: BodyState,
    poseMode: BodyTrackingMode,
    modeConfidence: Double,
    roiCoverage: Double,
    coverageHint: PoseVisibilityCoverage?
  ) -> TrackingQuality {
    let renderable = joints.values.filter(\.isRenderable)
    let logicUsable = joints.values.filter(\.isLogicUsable)
    let upperBodyRenderable = countUpperBodyRenderable(joints: joints)

    let trackedCoverage = PoseCoverageCalculator.coverage(tracked: joints)
    let mergedCoverage = mergedCoverage(hint: coverageHint, tracked: trackedCoverage)

    let renderCoverage = poseMode == .fullBody
      ? mergedCoverage.fullBodyCoverage
      : mergedCoverage.upperBodyCoverage
    let logicCoverage = renderable.isEmpty ? 0 : Double(logicUsable.count) / Double(max(1, renderable.count))

    let torsoScore = torsoIntegrityScore(joints: joints)
    let armScore = armIntegrityScore(joints: joints)
    let spreadScore = framingSpreadScore(joints: joints)
    smoothedSpread = updateSmoothedSpread(spreadScore)
    let continuityScore = temporalContinuityScore(joints: joints)
    let reliability = reliabilityScore(joints: joints, continuityScore: continuityScore)

    let inferredRatio = inferredJointRatio(joints: joints)
    let wristRetention = wristRetentionScore(joints: joints)

    var reasons: [String] = []
    if upperBodyRenderable < config.quality.minUpperBodyRenderableJoints {
      reasons.append("upper_body_missing")
    }
    if poseMode == .fullBody && mergedCoverage.fullBodyCoverage < config.mode.fullBodyCoverageLost {
      reasons.append("lower_body_missing")
    }
    if torsoScore < 0.32 {
      reasons.append("torso_weak")
    }
    if armScore < 0.34 {
      reasons.append("arm_weak")
    }
    if smoothedSpread < 0.24 {
      reasons.append("framing_tight")
    }
    if lowLightDetected {
      reasons.append("low_light")
    }
    if inferredRatio > 0.42 {
      reasons.append("prediction_heavy")
    }

    let renderQuality = clamp01(
      0.3 * renderCoverage +
      0.2 * torsoScore +
      0.2 * armScore +
      0.1 * spreadScore +
      0.1 * continuityScore +
      0.1 * modeConfidence
    )

    let logicPenalty = lowLightDetected ? 0.06 : 0
    let logicQuality = clamp01(
      0.28 * logicCoverage +
      0.2 * torsoScore +
      0.2 * armScore +
      0.12 * continuityScore +
      0.1 * mergedCoverage.upperBodyCoverage +
      0.1 * wristRetention - logicPenalty
    )

    let trackingQuality = clamp01(renderQuality * 0.55 + logicQuality * 0.45)
    let bodyVisibilityState: BodyVisibilityState

    if mergedCoverage.upperBodyCoverage < config.quality.notFoundThreshold {
      bodyVisibilityState = .notFound
    } else if trackingQuality < config.quality.assistedThreshold {
      bodyVisibilityState = .partial
    } else if logicQuality < config.quality.pushupLogicMin {
      bodyVisibilityState = .assisted
    } else if trackingQuality >= config.quality.goodThreshold {
      bodyVisibilityState = .good
    } else {
      bodyVisibilityState = .assisted
    }

    return TrackingQuality(
      trackingQuality: trackingQuality,
      renderQuality: renderQuality,
      logicQuality: logicQuality,
      bodyVisibilityState: bodyVisibilityState,
      trackingState: trackingState,
      poseTrackingState: poseState,
      poseMode: poseMode,
      reasonCodes: reasons,
      spreadScore: spreadScore,
      smoothedSpread: smoothedSpread,
      visibleJointCount: renderable.count,
      upperBodyRenderableCount: upperBodyRenderable,
      reliability: reliability,
      roiCoverage: roiCoverage,
      fullBodyCoverage: mergedCoverage.fullBodyCoverage,
      upperBodyCoverage: mergedCoverage.upperBodyCoverage,
      handCoverage: mergedCoverage.handCoverage,
      wristRetention: wristRetention,
      inferredJointRatio: inferredRatio,
      modeConfidence: modeConfidence
    )
  }

  private func mergedCoverage(hint: PoseVisibilityCoverage?, tracked: PoseVisibilityCoverage) -> PoseVisibilityCoverage {
    guard let hint else { return tracked }
    return PoseVisibilityCoverage(
      upperBodyCoverage: max(hint.upperBodyCoverage, tracked.upperBodyCoverage),
      fullBodyCoverage: max(hint.fullBodyCoverage, tracked.fullBodyCoverage),
      handCoverage: max(hint.handCoverage, tracked.handCoverage)
    )
  }

  private func countUpperBodyRenderable(joints: [PushlyJointName: TrackedJoint]) -> Int {
    let upper: [PushlyJointName] = [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist, .nose]
    return upper.reduce(0) { acc, joint in
      acc + ((joints[joint]?.isRenderable ?? false) ? 1 : 0)
    }
  }

  private func wristRetentionScore(joints: [PushlyJointName: TrackedJoint]) -> Double {
    let candidates: [PushlyJointName] = [.leftWrist, .rightWrist]
    let usable = candidates.filter { joints[$0]?.isRenderable == true }.count
    return Double(usable) / Double(candidates.count)
  }

  private func inferredJointRatio(joints: [PushlyJointName: TrackedJoint]) -> Double {
    let visible = joints.values.filter(\.isRenderable)
    guard !visible.isEmpty else { return 1 }
    let inferred = visible.filter { $0.sourceType == .inferred || $0.sourceType == .predicted }.count
    return Double(inferred) / Double(visible.count)
  }

  private func torsoIntegrityScore(joints: [PushlyJointName: TrackedJoint]) -> Double {
    let shoulder = (joints[.leftShoulder], joints[.rightShoulder])
    let hip = (joints[.leftHip], joints[.rightHip])

    var score = 0.0
    if shoulder.0?.isRenderable == true || shoulder.1?.isRenderable == true { score += 0.26 }
    if hip.0?.isRenderable == true || hip.1?.isRenderable == true { score += 0.24 }
    if shoulder.0?.isRenderable == true && shoulder.1?.isRenderable == true { score += 0.22 }
    if hip.0?.isRenderable == true && hip.1?.isRenderable == true { score += 0.18 }

    let shoulderMid = midpoint(joints[.leftShoulder]?.smoothedPosition, joints[.rightShoulder]?.smoothedPosition)
    let hipMid = midpoint(joints[.leftHip]?.smoothedPosition, joints[.rightHip]?.smoothedPosition)
    if let shoulderMid, let hipMid {
      let dy = abs(shoulderMid.y - hipMid.y)
      score += dy > 0.1 ? 0.1 : 0.02
    }

    return clamp01(score)
  }

  private func armIntegrityScore(joints: [PushlyJointName: TrackedJoint]) -> Double {
    let left = armScore(shoulder: .leftShoulder, elbow: .leftElbow, wrist: .leftWrist, joints: joints)
    let right = armScore(shoulder: .rightShoulder, elbow: .rightElbow, wrist: .rightWrist, joints: joints)
    return max(left, right) * 0.7 + min(left, right) * 0.3
  }

  private func armScore(
    shoulder: PushlyJointName,
    elbow: PushlyJointName,
    wrist: PushlyJointName,
    joints: [PushlyJointName: TrackedJoint]
  ) -> Double {
    let s = joints[shoulder]
    let e = joints[elbow]
    let w = joints[wrist]
    var score = 0.0
    if s?.isRenderable == true { score += 0.34 }
    if e?.isRenderable == true { score += 0.34 }
    if w?.isRenderable == true { score += 0.32 }
    return clamp01(score)
  }

  private func framingSpreadScore(joints: [PushlyJointName: TrackedJoint]) -> Double {
    let points = joints.values.filter(\.isRenderable).map(\.smoothedPosition)
    guard points.count >= 4 else {
      return 0.12
    }

    let minX = points.map(\.x).min() ?? 0
    let maxX = points.map(\.x).max() ?? 0
    let minY = points.map(\.y).min() ?? 0
    let maxY = points.map(\.y).max() ?? 0
    let width = maxX - minX
    let height = maxY - minY

    return clamp01(Double(width * 0.65 + height * 0.35))
  }

  private func temporalContinuityScore(joints: [PushlyJointName: TrackedJoint]) -> Double {
    let visible = joints.values.filter(\.isRenderable)
    guard !visible.isEmpty else {
      return 0
    }
    let predictedRatio = Double(visible.filter { $0.sourceType == .predicted }.count) / Double(visible.count)
    let inferredRatio = Double(visible.filter { $0.sourceType == .inferred }.count) / Double(visible.count)
    return clamp01(1 - predictedRatio * 0.65 - inferredRatio * 0.35)
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

  private func clamp01(_ value: Double) -> Double {
    min(1, max(0, value))
  }

  private func updateSmoothedSpread(_ spreadScore: Double) -> Double {
    if !hasSmoothedSpread {
      hasSmoothedSpread = true
      smoothedSpread = spreadScore
      return smoothedSpread
    }
    let alpha = 0.24
    smoothedSpread = smoothedSpread + (spreadScore - smoothedSpread) * alpha
    return smoothedSpread
  }

  private func reliabilityScore(joints: [PushlyJointName: TrackedJoint], continuityScore: Double) -> Double {
    let visible = joints.values.filter(\.isRenderable)
    guard !visible.isEmpty else {
      return 0
    }
    let avgConfidence = visible.map { Double($0.renderConfidence) }.reduce(0, +) / Double(visible.count)
    let speedValues = visible.map { sqrt(Double($0.velocity.dx * $0.velocity.dx + $0.velocity.dy * $0.velocity.dy)) }
    let avgSpeed = speedValues.reduce(0, +) / Double(speedValues.count)
    let plausibleMotion = clamp01(1 - min(1, avgSpeed / 0.65))
    return clamp01(avgConfidence * 0.45 + continuityScore * 0.35 + plausibleMotion * 0.2)
  }
}
#endif
