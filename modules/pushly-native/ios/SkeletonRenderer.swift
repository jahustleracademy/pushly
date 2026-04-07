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

  private let minStiffness: CGFloat = 0.75
  private let maxStiffness: CGFloat = 0.95
  private let stableDamping: CGFloat = 0.86
  private let movingDamping: CGFloat = 0.76
  private let microJitterThresholdPx: CGFloat = 0.9
  private let maxVelocityPerFrame: CGFloat = 0.085

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
    let speedNorm = min(1, max(0, CGFloat(avgBodyVelocity / 0.22)))
    let dampingFactor = stableDamping - (stableDamping - movingDamping) * speedNorm
    let stiffness = minStiffness + (maxStiffness - minStiffness) * speedNorm

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
        state.currentPosition = state.targetPosition
        state.velocity = CGVector(dx: nextVelocity.dx * 0.1, dy: nextVelocity.dy * 0.1)
        states[name] = state
        output[name] = state.currentPosition
        continue
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
  private struct VirtualHeadAttachment {
    let shoulderMid: CGPoint
    let neck: CGPoint
    let upperHead: CGPoint
    let useInferredPath: Bool
  }

  private let measuredLineLayer = CAShapeLayer()
  private let inferredLineLayer = CAShapeLayer()
  private let measuredJointLayer = CAShapeLayer()
  private let inferredJointLayer = CAShapeLayer()
  private let rawJointLayer = CAShapeLayer()
  private let trackedJointLayer = CAShapeLayer()
  private let springJointLayer = CAShapeLayer()

  private let springAnimator = JointSpringAnimator()
  private let lineEndpointAlpha: CGFloat

  private let connections: [(PushlyJointName, PushlyJointName)] = [
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
  private var lastVirtualHeadAttachment: (shoulderMid: CGPoint, neck: CGPoint, upperHead: CGPoint)?
  private var lastHeadUpDirection = CGVector(dx: 0, dy: 1)
  private var lastShoulderMid: CGPoint?
  private var lastShoulderSpan: CGFloat = 0.14
#if DEBUG
  private var debugInvalidGeometryCount = 0
  private var debugVirtualHeadIssueCount = 0
#endif

  init(containerLayer: CALayer, lineEndpointAlpha: CGFloat) {
    self.lineEndpointAlpha = min(0.9, max(0.35, lineEndpointAlpha))
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
    guard showSkeleton,
          joints.count >= 3,
          bounds.width.isFinite,
          bounds.height.isFinite,
          bounds.width > 0,
          bounds.height > 0 else {
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

    if let attachment = buildVirtualHeadAttachment(joints: joints, springPositions: springPositions) {
      let path = attachment.useInferredPath ? inferredLinePath : measuredLinePath
      let headJointPath = attachment.useInferredPath ? inferredDots : measuredDots

      if let shoulderMidPx = safeConvert(attachment.shoulderMid, in: bounds),
         let neckPx = safeConvert(attachment.neck, in: bounds),
         let upperHeadPx = safeConvert(attachment.upperHead, in: bounds) {
        let bridge = smoothEndpointsForLine(key: "virtual_head_shoulder_bridge", p1: shoulderMidPx, p2: neckPx)
        addLine(path: path, from: bridge.0, to: bridge.1)

        let crown = smoothEndpointsForLine(key: "virtual_head_crown", p1: neckPx, p2: upperHeadPx)
        addLine(path: path, from: crown.0, to: crown.1)

        addDot(path: headJointPath, center: neckPx, radius: 2.2)
        addDot(path: headJointPath, center: upperHeadPx, radius: 2.8)
      } else {
#if DEBUG
        debugInvalidGeometryCount += 1
        if debugInvalidGeometryCount <= 3 || debugInvalidGeometryCount % 30 == 0 {
          print("[Pose][SkeletonRenderer] dropped virtual-head segment due to non-finite geometry. count=\(debugInvalidGeometryCount)")
        }
#endif
      }
    }

    for (a, b) in connections {
      guard let ja = joints[a], ja.sourceType != .missing,
            let jb = joints[b], jb.sourceType != .missing,
            let sa = springPositions[a], let sb = springPositions[b] else {
        continue
      }

      guard let p1 = safeConvert(sa, in: bounds),
            let p2 = safeConvert(sb, in: bounds) else {
#if DEBUG
        debugInvalidGeometryCount += 1
        if debugInvalidGeometryCount <= 3 || debugInvalidGeometryCount % 40 == 0 {
          print("[Pose][SkeletonRenderer] skipped non-finite line geometry for \(a.rawValue)-\(b.rawValue). count=\(debugInvalidGeometryCount)")
        }
#endif
        continue
      }
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

      guard let springCenter = safeConvert(springPosition, in: bounds) else {
        continue
      }
      let springRadius: CGFloat = (joint.sourceType == .inferred || joint.sourceType == .predicted) ? 2.2 : 2.9
      let jointPath = (joint.sourceType == .inferred || joint.sourceType == .predicted) ? inferredDots : measuredDots
      addDot(path: jointPath, center: springCenter, radius: springRadius)

      if debugMode {
        if let rawCenter = safeConvert(joint.rawPosition, in: bounds) {
          addDot(path: rawDots, center: rawCenter, radius: 1.7)
        }
        if let trackedCenter = safeConvert(joint.smoothedPosition, in: bounds) {
          addDot(path: trackedDots, center: trackedCenter, radius: 2.0)
        }
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

    let alpha: CGFloat = lineEndpointAlpha
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
      self.lastVirtualHeadAttachment = nil
      self.lastHeadUpDirection = CGVector(dx: 0, dy: 1)
      self.lastShoulderMid = nil
      self.lastShoulderSpan = 0.14
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
      guard let rawPx = safeConvert(joint.rawPosition, in: bounds),
            let trackedPx = safeConvert(joint.smoothedPosition, in: bounds),
            let springPx = safeConvert(spring, in: bounds) else {
        continue
      }

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

  private func buildVirtualHeadAttachment(
    joints: [PushlyJointName: TrackedJoint],
    springPositions: [PushlyJointName: CGPoint]
  ) -> VirtualHeadAttachment? {
    let leftShoulder = sanitizeCanonicalPoint(springPositions[.leftShoulder])
    let rightShoulder = sanitizeCanonicalPoint(springPositions[.rightShoulder])
    let nose = sanitizeCanonicalPoint(springPositions[.nose])
    let measuredHead = sanitizeCanonicalPoint(springPositions[.head])
    var usedFallbackGeometry = false

    var shoulderMid: CGPoint?
    var shoulderSpan = lastShoulderSpan
    if let leftShoulder, let rightShoulder {
      let mid = midpoint(leftShoulder, rightShoulder)
      shoulderMid = mid
      lastShoulderMid = mid
      let span = distance(leftShoulder, rightShoulder)
      if span.isFinite, span > 0.04 {
        shoulderSpan = min(0.46, max(0.08, span))
        lastShoulderSpan = shoulderSpan
      }
    } else if let fallback = lastShoulderMid {
      shoulderMid = fallback
      usedFallbackGeometry = true
    } else if let leftShoulder {
      shoulderMid = leftShoulder
      usedFallbackGeometry = true
    } else if let rightShoulder {
      shoulderMid = rightShoulder
      usedFallbackGeometry = true
    }

    guard let shoulderMid, isFinitePoint(shoulderMid) else { return nil }

    var upDirection = lastHeadUpDirection
    if let leftShoulder, let rightShoulder {
      let shoulders = CGVector(dx: rightShoulder.x - leftShoulder.x, dy: rightShoulder.y - leftShoulder.y)
      let shoulderAxis = normalize(shoulders)
      var orthogonal = normalize(CGVector(dx: -shoulderAxis.dy, dy: shoulderAxis.dx))

      if let nose {
        let toNose = normalize(CGVector(dx: nose.x - shoulderMid.x, dy: nose.y - shoulderMid.y))
        if dot(orthogonal, toNose) < 0 {
          orthogonal = orthogonal * -1
        }
        orthogonal = normalize(blend(orthogonal, toNose, alpha: 0.3))
      }

      upDirection = normalize(blend(lastHeadUpDirection, orthogonal, alpha: 0.35))
    } else if let nose {
      let toNose = normalize(CGVector(dx: nose.x - shoulderMid.x, dy: nose.y - shoulderMid.y))
      upDirection = normalize(blend(lastHeadUpDirection, toNose, alpha: 0.22))
    } else if let measuredHead {
      let toHead = normalize(CGVector(dx: measuredHead.x - shoulderMid.x, dy: measuredHead.y - shoulderMid.y))
      upDirection = normalize(blend(lastHeadUpDirection, toHead, alpha: 0.2))
    }
    lastHeadUpDirection = upDirection

    let neckLengthFactor: CGFloat = 0.11
    let headLengthFactor: CGFloat = 0.34
    let noseLiftFactor: CGFloat = 0.12
    let neckMinLen: CGFloat = 0.024
    let neckMaxLen: CGFloat = 0.055
    let crownMinLen: CGFloat = 0.048
    let crownMaxLen: CGFloat = 0.118
    let headSpanMinClampFactor: CGFloat = 0.24
    let headSpanMaxClampFactor: CGFloat = 0.46

    let neckLength = min(neckMaxLen, max(neckMinLen, shoulderSpan * neckLengthFactor))
    let crownLength = min(crownMaxLen, max(crownMinLen, shoulderSpan * headLengthFactor))
    let noseLift = min(0.03, max(0.01, shoulderSpan * noseLiftFactor))

    let crownFromShoulders = clampNormalizedPoint(shoulderMid + upDirection * crownLength)
    let neckTarget = clampAlongDirection(
      origin: shoulderMid,
      candidate: clampNormalizedPoint(shoulderMid + upDirection * neckLength),
      direction: upDirection,
      minLength: neckLength * 0.7,
      maxLength: neckLength * 1.15
    )

    let upperHeadTarget: CGPoint
    if let nose {
      let crownFromNose = clampAlongDirection(
        origin: shoulderMid,
        candidate: clampNormalizedPoint(nose + upDirection * noseLift),
        direction: upDirection,
        minLength: crownLength * 0.72,
        maxLength: crownLength * 1.05
      )
      upperHeadTarget = blend(crownFromShoulders, crownFromNose, alpha: 0.34)
    } else if let measuredHead {
      let conservativeMeasuredHead = clampAlongDirection(
        origin: shoulderMid,
        candidate: measuredHead,
        direction: upDirection,
        minLength: crownLength * 0.75,
        maxLength: crownLength * 1.08
      )
      upperHeadTarget = blend(crownFromShoulders, conservativeMeasuredHead, alpha: 0.28)
    } else if let cached = lastVirtualHeadAttachment {
      let conservativeCached = clampAlongDirection(
        origin: shoulderMid,
        candidate: cached.upperHead,
        direction: upDirection,
        minLength: crownLength * 0.78,
        maxLength: crownLength * 1.04
      )
      upperHeadTarget = blend(crownFromShoulders, conservativeCached, alpha: 0.22)
      usedFallbackGeometry = true
    } else {
      upperHeadTarget = crownFromShoulders
    }

    let headMinLen = max(crownMinLen * 0.82, shoulderSpan * headSpanMinClampFactor)
    let headMaxLen = min(crownMaxLen * 1.08, max(headMinLen + 0.01, shoulderSpan * headSpanMaxClampFactor))
    let clampedUpperHeadTarget = clampAlongDirection(
      origin: shoulderMid,
      candidate: upperHeadTarget,
      direction: upDirection,
      minLength: headMinLen,
      maxLength: headMaxLen
    )

    let smoothedNeck: CGPoint
    let smoothedUpperHead: CGPoint
    if let cached = lastVirtualHeadAttachment {
      smoothedNeck = blend(cached.neck, neckTarget, alpha: 0.34)
      smoothedUpperHead = blend(cached.upperHead, clampedUpperHeadTarget, alpha: 0.32)
    } else {
      smoothedNeck = neckTarget
      smoothedUpperHead = clampedUpperHeadTarget
    }

    let smoothedShoulderMid: CGPoint
    if let cached = lastVirtualHeadAttachment {
      smoothedShoulderMid = blend(cached.shoulderMid, shoulderMid, alpha: 0.4)
    } else {
      smoothedShoulderMid = shoulderMid
    }

    guard isFinitePoint(smoothedShoulderMid),
          isFinitePoint(smoothedNeck),
          isFinitePoint(smoothedUpperHead) else {
#if DEBUG
      debugVirtualHeadIssueCount += 1
      if debugVirtualHeadIssueCount <= 3 || debugVirtualHeadIssueCount % 20 == 0 {
        print("[Pose][SkeletonRenderer] virtual-head geometry became non-finite. count=\(debugVirtualHeadIssueCount)")
      }
#endif
      return nil
    }

    guard validateVirtualHeadGeometry(
      shoulderMid: smoothedShoulderMid,
      neck: smoothedNeck,
      upperHead: smoothedUpperHead,
      shoulderSpan: shoulderSpan
    ) else {
      return nil
    }

    lastVirtualHeadAttachment = (shoulderMid: smoothedShoulderMid, neck: smoothedNeck, upperHead: smoothedUpperHead)

    let leftType = joints[.leftShoulder]?.sourceType
    let rightType = joints[.rightShoulder]?.sourceType
    let noseType = joints[.nose]?.sourceType
    let headType = joints[.head]?.sourceType
    let useInferredPath = usedFallbackGeometry || [leftType, rightType, noseType, headType].contains { type in
      type == .inferred || type == .predicted
    }

    return VirtualHeadAttachment(
      shoulderMid: smoothedShoulderMid,
      neck: smoothedNeck,
      upperHead: smoothedUpperHead,
      useInferredPath: useInferredPath
    )
  }

  private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
    CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
  }

  private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
  }

  private func blend(_ a: CGPoint, _ b: CGPoint, alpha: CGFloat) -> CGPoint {
    CGPoint(
      x: a.x + (b.x - a.x) * alpha,
      y: a.y + (b.y - a.y) * alpha
    )
  }

  private func blend(_ a: CGVector, _ b: CGVector, alpha: CGFloat) -> CGVector {
    CGVector(
      dx: a.dx + (b.dx - a.dx) * alpha,
      dy: a.dy + (b.dy - a.dy) * alpha
    )
  }

  private func normalize(_ vector: CGVector) -> CGVector {
    let m = hypot(vector.dx, vector.dy)
    guard m > 0.0001 else { return CGVector(dx: 0, dy: 1) }
    return CGVector(dx: vector.dx / m, dy: vector.dy / m)
  }

  private func dot(_ a: CGVector, _ b: CGVector) -> CGFloat {
    a.dx * b.dx + a.dy * b.dy
  }

  private func sanitizeCanonicalPoint(_ point: CGPoint?) -> CGPoint? {
    guard let point, point.x.isFinite, point.y.isFinite else { return nil }
    return clampNormalizedPoint(point)
  }

  private func isFinitePoint(_ point: CGPoint) -> Bool {
    point.x.isFinite && point.y.isFinite
  }

  private func isFiniteVector(_ vector: CGVector) -> Bool {
    vector.dx.isFinite && vector.dy.isFinite
  }

  private func clampNormalizedPoint(_ point: CGPoint) -> CGPoint {
    let x = point.x.isFinite ? min(1, max(0, point.x)) : 0.5
    let y = point.y.isFinite ? min(1, max(0, point.y)) : 0.5
    return CGPoint(x: x, y: y)
  }

  private func clampAlongDirection(
    origin: CGPoint,
    candidate: CGPoint,
    direction: CGVector,
    minLength: CGFloat,
    maxLength: CGFloat
  ) -> CGPoint {
    guard isFinitePoint(origin),
          isFinitePoint(candidate),
          isFiniteVector(direction),
          minLength.isFinite,
          maxLength.isFinite else {
      return clampNormalizedPoint(origin)
    }
    let dir = normalize(direction)
    guard isFiniteVector(dir) else {
      return clampNormalizedPoint(origin)
    }
    let delta = CGVector(dx: candidate.x - origin.x, dy: candidate.y - origin.y)
    let projected = dot(delta, dir)
    let safeMinLength = max(0, minLength)
    let safeMaxLength = max(safeMinLength, maxLength)
    let safeProjected = projected.isFinite ? projected : safeMinLength
    let clamped = min(safeMaxLength, max(safeMinLength, safeProjected))
    return clampNormalizedPoint(
      CGPoint(
        x: origin.x + dir.dx * clamped,
        y: origin.y + dir.dy * clamped
      )
    )
  }

  private func safeConvert(_ point: CGPoint, in bounds: CGRect) -> CGPoint? {
    guard bounds.width.isFinite,
          bounds.height.isFinite,
          bounds.width > 0,
          bounds.height > 0,
          isFinitePoint(point) else {
      return nil
    }
    let converted = convert(clampNormalizedPoint(point), in: bounds)
    guard isFinitePoint(converted) else {
      return nil
    }
    return converted
  }

  private func validateVirtualHeadGeometry(
    shoulderMid: CGPoint,
    neck: CGPoint,
    upperHead: CGPoint,
    shoulderSpan: CGFloat
  ) -> Bool {
    guard shoulderSpan.isFinite else {
      return false
    }
    let neckLen = distance(shoulderMid, neck)
    let headLen = distance(shoulderMid, upperHead)
    guard neckLen.isFinite, headLen.isFinite else {
#if DEBUG
      debugVirtualHeadIssueCount += 1
      if debugVirtualHeadIssueCount <= 3 || debugVirtualHeadIssueCount % 20 == 0 {
        print("[Pose][SkeletonRenderer] virtual-head length non-finite. count=\(debugVirtualHeadIssueCount)")
      }
#endif
      return false
    }
    let neckHardMax = min(0.075, max(0.032, shoulderSpan * 0.28))
    let headHardMin = max(0.03, shoulderSpan * 0.16)
    let headHardMax = min(0.14, max(0.065, shoulderSpan * 0.58))

    let geometryInRange = neckLen <= neckHardMax + 0.006
      && headLen >= headHardMin - 0.01
      && headLen <= headHardMax + 0.008
      && neckLen <= headLen + 0.004

    if !geometryInRange {
#if DEBUG
      debugVirtualHeadIssueCount += 1
      if debugVirtualHeadIssueCount <= 3 || debugVirtualHeadIssueCount % 20 == 0 {
        print("[Pose][SkeletonRenderer] virtual-head out-of-range; skipping frame. neckLen=\(neckLen) headLen=\(headLen) shoulderSpan=\(shoulderSpan) count=\(debugVirtualHeadIssueCount)")
      }
#endif
      return false
    }
    return true
  }
}
#endif
