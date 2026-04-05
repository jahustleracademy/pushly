import Foundation

#if os(iOS)
import UIKit

private final class JointSpringAnimator {
  private struct SpringState {
    var currentPosition: CGPoint
    var targetPosition: CGPoint
    var velocity: CGVector
  }

  private var states: [PushlyJointName: SpringState] = [:]

  private let baseStiffness: CGFloat = 0.2
  private let stableDamping: CGFloat = 0.85
  private let movingDamping: CGFloat = 0.7
  private let microJitterThresholdPx: CGFloat = 2.0
  private let maxVelocityPerFrame: CGFloat = 0.03

  func updateTargets(_ joints: [PushlyJointName: TrackedJoint]) {
    for (name, joint) in joints {
      if var existing = states[name] {
        existing.targetPosition = joint.smoothedPosition
        states[name] = existing
      } else {
        states[name] = SpringState(
          currentPosition: joint.smoothedPosition,
          targetPosition: joint.smoothedPosition,
          velocity: .zero
        )
      }
    }

    let validNames = Set(joints.keys)
    states = states.filter { validNames.contains($0.key) }
  }

  func step(
    dt: TimeInterval,
    bounds: CGRect,
    avgBodyVelocity: Double
  ) -> [PushlyJointName: CGPoint] {
    let frameScale = max(0.6, min(1.6, CGFloat(dt * 60)))
    let stableBody = avgBodyVelocity < 0.07
    let dampingFactor = stableBody ? stableDamping : movingDamping
    let stiffness = stableBody ? max(0.15, baseStiffness - 0.03) : min(0.25, baseStiffness + 0.03)

    var output: [PushlyJointName: CGPoint] = [:]

    for (name, var state) in states {
      let dx = state.targetPosition.x - state.currentPosition.x
      let dy = state.targetPosition.y - state.currentPosition.y
      let force = CGVector(dx: dx * stiffness * frameScale, dy: dy * stiffness * frameScale)

      let dampedVelocity = CGVector(
        dx: (state.velocity.dx + force.dx) * dampingFactor,
        dy: (state.velocity.dy + force.dy) * dampingFactor
      )

      var nextVelocity = clampVelocity(dampedVelocity, maxMagnitude: maxVelocityPerFrame * frameScale)
      let distancePx = normalizedDistanceToPixels(dx: dx, dy: dy, bounds: bounds)
      if distancePx < microJitterThresholdPx {
        nextVelocity = CGVector(dx: nextVelocity.dx * 0.2, dy: nextVelocity.dy * 0.2)
      }

      var nextPosition = CGPoint(
        x: state.currentPosition.x + nextVelocity.dx,
        y: state.currentPosition.y + nextVelocity.dy
      )
      nextPosition.x = min(1, max(0, nextPosition.x))
      nextPosition.y = min(1, max(0, nextPosition.y))

      state.currentPosition = nextPosition
      state.velocity = nextVelocity
      states[name] = state
      output[name] = nextPosition
    }

    return output
  }

  func reset() {
    states.removeAll()
  }

  private func normalizedDistanceToPixels(dx: CGFloat, dy: CGFloat, bounds: CGRect) -> CGFloat {
    let px = dx * bounds.width
    let py = dy * bounds.height
    return sqrt(px * px + py * py)
  }

  private func clampVelocity(_ velocity: CGVector, maxMagnitude: CGFloat) -> CGVector {
    let magnitude = sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy)
    guard magnitude > maxMagnitude, magnitude > 0.0001 else {
      return velocity
    }
    let scale = maxMagnitude / magnitude
    return CGVector(dx: velocity.dx * scale, dy: velocity.dy * scale)
  }
}

struct SkeletonRenderDiagnostics {
  let rawToTrackedRmsPx: Double
  let trackedToSpringRmsPx: Double
  let inferredRatio: Double
  let measuredJointCount: Int
  let inferredJointCount: Int
}

final class SkeletonRenderer {
  private let measuredLineLayer = CAShapeLayer()
  private let inferredLineLayer = CAShapeLayer()
  private let measuredJointLayer = CAShapeLayer()
  private let inferredJointLayer = CAShapeLayer()
  private let rawJointLayer = CAShapeLayer()
  private let trackedJointLayer = CAShapeLayer()
  private let springJointLayer = CAShapeLayer()

  private let springAnimator = JointSpringAnimator()

  private let connections: [(PushlyJointName, PushlyJointName)] = [
    (.nose, .head),
    (.leftShoulder, .rightShoulder),
    (.leftShoulder, .leftElbow),
    (.leftElbow, .leftWrist),
    (.leftWrist, .leftHand),
    (.rightShoulder, .rightElbow),
    (.rightElbow, .rightWrist),
    (.rightWrist, .rightHand),
    (.leftShoulder, .leftHip),
    (.rightShoulder, .rightHip),
    (.leftHip, .rightHip),
    (.leftHip, .leftKnee),
    (.leftKnee, .leftAnkle),
    (.leftAnkle, .leftFoot),
    (.rightHip, .rightKnee),
    (.rightKnee, .rightAnkle),
    (.rightAnkle, .rightFoot)
  ]

  private var lastRenderTime: CFTimeInterval = CACurrentMediaTime()
  private var lastLineEndpoints: [String: (CGPoint, CGPoint)] = [:]
  private var isVisible = false
  private var pendingHideWorkItem: DispatchWorkItem?
  private var projectionContext: PoseCoordinateConverter.ProjectionContext?

  init(containerLayer: CALayer) {
    configure(layer: measuredLineLayer, lineWidth: 3.2, opacity: 1.0)
    configure(layer: inferredLineLayer, lineWidth: 3.2, opacity: 0.4)
    configure(layer: measuredJointLayer, lineWidth: 0, opacity: 1)
    configure(layer: inferredJointLayer, lineWidth: 0, opacity: 0.4)

    measuredJointLayer.fillColor = UIColor(red: 207 / 255, green: 255 / 255, blue: 110 / 255, alpha: 0.95).cgColor
    inferredJointLayer.fillColor = UIColor(red: 186 / 255, green: 250 / 255, blue: 32 / 255, alpha: 0.4).cgColor

    rawJointLayer.fillColor = UIColor(red: 255 / 255, green: 112 / 255, blue: 112 / 255, alpha: 0.6).cgColor
    trackedJointLayer.fillColor = UIColor(red: 112 / 255, green: 201 / 255, blue: 255 / 255, alpha: 0.65).cgColor
    springJointLayer.fillColor = UIColor(red: 204 / 255, green: 255 / 255, blue: 120 / 255, alpha: 0.95).cgColor

    containerLayer.addSublayer(inferredLineLayer)
    containerLayer.addSublayer(measuredLineLayer)
    containerLayer.addSublayer(inferredJointLayer)
    containerLayer.addSublayer(measuredJointLayer)
    containerLayer.addSublayer(rawJointLayer)
    containerLayer.addSublayer(trackedJointLayer)
    containerLayer.addSublayer(springJointLayer)
  }

  func updateFrame(_ bounds: CGRect) {
    measuredLineLayer.frame = bounds
    inferredLineLayer.frame = bounds
    measuredJointLayer.frame = bounds
    inferredJointLayer.frame = bounds
    rawJointLayer.frame = bounds
    trackedJointLayer.frame = bounds
    springJointLayer.frame = bounds
  }

  func updateProjectionContext(_ context: PoseCoordinateConverter.ProjectionContext?) {
    projectionContext = context
  }

  func render(
    joints: [PushlyJointName: TrackedJoint],
    in bounds: CGRect,
    showSkeleton: Bool,
    debugMode: Bool,
    avgBodyVelocity: Double,
    trackingState: TrackingContinuityState
  ) -> SkeletonRenderDiagnostics {
    guard showSkeleton, joints.count >= 3 else {
      hideAndClear()
      return SkeletonRenderDiagnostics(rawToTrackedRmsPx: 0, trackedToSpringRmsPx: 0, inferredRatio: 0, measuredJointCount: 0, inferredJointCount: 0)
    }

    showWithAnimationIfNeeded()
    pendingHideWorkItem?.cancel()
    pendingHideWorkItem = nil

    let now = CACurrentMediaTime()
    let dt = max(1.0 / 120.0, min(now - lastRenderTime, 1.0 / 15.0))
    lastRenderTime = now

    springAnimator.updateTargets(joints)
    let stateVelocity = trackingState == .reacquire ? avgBodyVelocity * 0.45 : avgBodyVelocity
    let springPositions = springAnimator.step(dt: dt, bounds: bounds, avgBodyVelocity: stateVelocity)
    let renderableNames = Set(springPositions.keys)
    guard renderableNames.count >= 3 else {
      hideAndClear()
      return SkeletonRenderDiagnostics(rawToTrackedRmsPx: 0, trackedToSpringRmsPx: 0, inferredRatio: 0, measuredJointCount: 0, inferredJointCount: 0)
    }

    let measuredLinePath = UIBezierPath()
    let inferredLinePath = UIBezierPath()
    let measuredDots = UIBezierPath()
    let inferredDots = UIBezierPath()
    let rawDots = UIBezierPath()
    let trackedDots = UIBezierPath()
    let springDots = UIBezierPath()

    for (a, b) in connections {
      guard let ja = joints[a], ja.sourceType != .missing,
            let jb = joints[b], jb.sourceType != .missing,
            let sa = springPositions[a], let sb = springPositions[b] else {
        continue
      }

      let p1 = convert(sa, in: bounds)
      let p2 = convert(sb, in: bounds)
      let key = "\(a.rawValue)-\(b.rawValue)"
      let smoothedEndpoints = smoothEndpointsForLine(key: key, p1: p1, p2: p2)
      let useInferred = ja.sourceType == .inferred || ja.sourceType == .predicted || jb.sourceType == .inferred || jb.sourceType == .predicted
      let path = useInferred ? inferredLinePath : measuredLinePath
      addLine(path: path, from: smoothedEndpoints.0, to: smoothedEndpoints.1)
    }

    for (name, joint) in joints {
      guard let springPosition = springPositions[name] else {
        continue
      }

      let springCenter = convert(springPosition, in: bounds)
      let springRadius: CGFloat = (joint.sourceType == .inferred || joint.sourceType == .predicted) ? 2.2 : 2.9
      let jointPath = (joint.sourceType == .inferred || joint.sourceType == .predicted) ? inferredDots : measuredDots
      addDot(path: jointPath, center: springCenter, radius: springRadius)

      if debugMode {
        addDot(path: rawDots, center: convert(joint.rawPosition, in: bounds), radius: 1.7)
        addDot(path: trackedDots, center: convert(joint.smoothedPosition, in: bounds), radius: 2.0)
        addDot(path: springDots, center: springCenter, radius: 2.3)
      }
    }

    let measuredAvgConfidence = averageConfidence(of: joints.values.filter { $0.sourceType != .inferred && $0.sourceType != .predicted })
    let inferredAvgConfidence = averageConfidence(of: joints.values.filter { $0.sourceType == .inferred || $0.sourceType == .predicted })
    measuredLineLayer.opacity = Float(max(0.6, min(1.0, measuredAvgConfidence)))
    measuredJointLayer.opacity = Float(max(0.65, min(1.0, measuredAvgConfidence)))
    inferredLineLayer.opacity = Float(max(0.22, min(0.4, inferredAvgConfidence * 0.45)))
    inferredJointLayer.opacity = Float(max(0.2, min(0.4, inferredAvgConfidence * 0.5)))

    measuredLineLayer.path = measuredLinePath.cgPath
    inferredLineLayer.path = inferredLinePath.cgPath
    measuredJointLayer.path = measuredDots.cgPath
    inferredJointLayer.path = inferredDots.cgPath

    rawJointLayer.path = debugMode ? rawDots.cgPath : nil
    trackedJointLayer.path = debugMode ? trackedDots.cgPath : nil
    springJointLayer.path = debugMode ? springDots.cgPath : nil
    rawJointLayer.isHidden = !debugMode
    trackedJointLayer.isHidden = !debugMode
    springJointLayer.isHidden = !debugMode

    let rms = computeRms(joints: joints, springPositions: springPositions, bounds: bounds)
    let inferredCount = joints.values.filter { $0.sourceType == .inferred || $0.sourceType == .predicted }.count
    let measuredCount = joints.values.filter { $0.sourceType == .measured || $0.sourceType == .lowConfidenceMeasured }.count
    let inferredRatio = joints.isEmpty ? 0 : Double(inferredCount) / Double(joints.count)
    return SkeletonRenderDiagnostics(
      rawToTrackedRmsPx: rms.rawToTracked,
      trackedToSpringRmsPx: rms.trackedToSpring,
      inferredRatio: inferredRatio,
      measuredJointCount: measuredCount,
      inferredJointCount: inferredCount
    )
  }

  private func configure(layer: CAShapeLayer, lineWidth: CGFloat, opacity: Float) {
    layer.fillColor = UIColor.clear.cgColor
    layer.strokeColor = UIColor(red: 186 / 255, green: 250 / 255, blue: 32 / 255, alpha: 0.98).cgColor
    layer.lineWidth = lineWidth
    layer.lineCap = .round
    layer.lineJoin = .round
    layer.shadowColor = UIColor(red: 186 / 255, green: 250 / 255, blue: 32 / 255, alpha: 1).cgColor
    layer.shadowOpacity = 0.25
    layer.shadowRadius = 7
    layer.opacity = opacity
  }

  private func addDot(path: UIBezierPath, center: CGPoint, radius: CGFloat) {
    path.move(to: CGPoint(x: center.x + radius, y: center.y))
    path.addArc(withCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
  }

  private func addLine(path: UIBezierPath, from p1: CGPoint, to p2: CGPoint) {
    let mid = CGPoint(x: (p1.x + p2.x) * 0.5, y: (p1.y + p2.y) * 0.5)
    path.move(to: p1)
    path.addQuadCurve(to: p2, controlPoint: mid)
  }

  private func smoothEndpointsForLine(key: String, p1: CGPoint, p2: CGPoint) -> (CGPoint, CGPoint) {
    guard let previous = lastLineEndpoints[key] else {
      lastLineEndpoints[key] = (p1, p2)
      return (p1, p2)
    }

    let alpha: CGFloat = 0.45
    let smoothed1 = CGPoint(
      x: previous.0.x + (p1.x - previous.0.x) * alpha,
      y: previous.0.y + (p1.y - previous.0.y) * alpha
    )
    let smoothed2 = CGPoint(
      x: previous.1.x + (p2.x - previous.1.x) * alpha,
      y: previous.1.y + (p2.y - previous.1.y) * alpha
    )
    lastLineEndpoints[key] = (smoothed1, smoothed2)
    return (smoothed1, smoothed2)
  }

  private func showWithAnimationIfNeeded() {
    guard !isVisible else { return }
    isVisible = true

    let layers = animatedLayers()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for layer in layers {
      layer.opacity = 1.0
      layer.setAffineTransform(CGAffineTransform(scaleX: 0.95, y: 0.95))
    }
    CATransaction.commit()

    for layer in layers {
      let opacity = CABasicAnimation(keyPath: "opacity")
      opacity.fromValue = 0.0
      opacity.toValue = 1.0
      opacity.duration = 0.15
      opacity.timingFunction = CAMediaTimingFunction(name: .easeOut)
      layer.add(opacity, forKey: "appearOpacity")

      let scale = CABasicAnimation(keyPath: "transform.scale")
      scale.fromValue = 0.95
      scale.toValue = 1.0
      scale.duration = 0.15
      scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
      layer.add(scale, forKey: "appearScale")

      layer.setAffineTransform(.identity)
    }
  }

  private func hideAndClear() {
    pendingHideWorkItem?.cancel()
    guard isVisible else {
      clear()
      springAnimator.reset()
      return
    }

    isVisible = false
    let layers = animatedLayers()
    for layer in layers {
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
      fade.toValue = 0.0
      fade.duration = 0.1
      fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      layer.add(fade, forKey: "disappearFade")
      layer.opacity = 0
    }

    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.clear()
      self.springAnimator.reset()
      self.lastLineEndpoints.removeAll()
    }
    pendingHideWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
  }

  private func clear() {
    measuredLineLayer.path = nil
    inferredLineLayer.path = nil
    measuredJointLayer.path = nil
    inferredJointLayer.path = nil
    rawJointLayer.path = nil
    trackedJointLayer.path = nil
    springJointLayer.path = nil
  }

  private func animatedLayers() -> [CAShapeLayer] {
    [measuredLineLayer, inferredLineLayer, measuredJointLayer, inferredJointLayer]
  }

  private func convert(_ point: CGPoint, in bounds: CGRect) -> CGPoint {
    if let projectionContext {
      return PoseCoordinateConverter.previewPointFromCanonical(point, projection: projectionContext)
    }
    return CGPoint(x: point.x * bounds.width, y: (1 - point.y) * bounds.height)
  }

  private func averageConfidence(of joints: [TrackedJoint]) -> Double {
    guard !joints.isEmpty else {
      return 0
    }
    return joints.map { Double($0.renderConfidence) }.reduce(0, +) / Double(joints.count)
  }

  private func computeRms(
    joints: [PushlyJointName: TrackedJoint],
    springPositions: [PushlyJointName: CGPoint],
    bounds: CGRect
  ) -> (rawToTracked: Double, trackedToSpring: Double) {
    guard !joints.isEmpty else { return (0, 0) }
    var rawTrackedSum = 0.0
    var trackedSpringSum = 0.0
    var count = 0.0

    for (name, joint) in joints {
      guard let spring = springPositions[name] else { continue }
      let rawPx = convert(joint.rawPosition, in: bounds)
      let trackedPx = convert(joint.smoothedPosition, in: bounds)
      let springPx = convert(spring, in: bounds)

      let rawTrackedDx = Double(rawPx.x - trackedPx.x)
      let rawTrackedDy = Double(rawPx.y - trackedPx.y)
      rawTrackedSum += rawTrackedDx * rawTrackedDx + rawTrackedDy * rawTrackedDy

      let trackedSpringDx = Double(trackedPx.x - springPx.x)
      let trackedSpringDy = Double(trackedPx.y - springPx.y)
      trackedSpringSum += trackedSpringDx * trackedSpringDx + trackedSpringDy * trackedSpringDy
      count += 1
    }

    guard count > 0 else { return (0, 0) }
    return (sqrt(rawTrackedSum / count), sqrt(trackedSpringSum / count))
  }
}
#endif
