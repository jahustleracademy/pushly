import Foundation

#if os(iOS)
import CoreGraphics

private struct JointTrackState {
  var smoothedPosition: CGPoint
  var rawPosition: CGPoint
  var velocity: CGVector
  var renderConfidence: Float
  var logicConfidence: Float
  var visibility: Float
  var presence: Float
  var inFrame: Bool
  var sourceType: PushlyJointSourceType
  var lastUpdateTime: TimeInterval
  var lastMeasuredTime: TimeInterval
}

private struct KinematicOffsetState {
  var vector: CGVector
  var timestamp: TimeInterval
  var confidence: Float
}

private struct LowPassFilter1D {
  var initialized = false
  var value: CGFloat = 0

  mutating func filter(_ newValue: CGFloat, alpha: CGFloat) -> CGFloat {
    if !initialized {
      initialized = true
      value = newValue
      return newValue
    }
    value = alpha * newValue + (1 - alpha) * value
    return value
  }
}

private struct OneEuroJointFilter {
  var xFilter = LowPassFilter1D()
  var yFilter = LowPassFilter1D()
  var dxFilter = LowPassFilter1D()
  var dyFilter = LowPassFilter1D()
  var previousRawX: CGFloat = 0
  var previousRawY: CGFloat = 0
  var initialized = false

  mutating func reset() {
    xFilter = LowPassFilter1D()
    yFilter = LowPassFilter1D()
    dxFilter = LowPassFilter1D()
    dyFilter = LowPassFilter1D()
    previousRawX = 0
    previousRawY = 0
    initialized = false
  }

  mutating func filter(
    _ point: CGPoint,
    dt: TimeInterval,
    minCutoff: CGFloat,
    beta: CGFloat,
    dCutoff: CGFloat
  ) -> CGPoint {
    let dtSafe = CGFloat(max(dt, 1.0 / 120.0))
    if !initialized {
      initialized = true
      previousRawX = point.x
      previousRawY = point.y
      _ = dxFilter.filter(0, alpha: 1)
      _ = dyFilter.filter(0, alpha: 1)
      let x = xFilter.filter(point.x, alpha: 1)
      let y = yFilter.filter(point.y, alpha: 1)
      return CGPoint(x: x, y: y)
    }

    let dx = (point.x - previousRawX) / dtSafe
    let dy = (point.y - previousRawY) / dtSafe
    previousRawX = point.x
    previousRawY = point.y

    let edx = dxFilter.filter(dx, alpha: smoothingAlpha(dt: dtSafe, cutoff: dCutoff))
    let edy = dyFilter.filter(dy, alpha: smoothingAlpha(dt: dtSafe, cutoff: dCutoff))
    let cutoffX = max(0.01, minCutoff + beta * abs(edx))
    let cutoffY = max(0.01, minCutoff + beta * abs(edy))

    let fx = xFilter.filter(point.x, alpha: smoothingAlpha(dt: dtSafe, cutoff: cutoffX))
    let fy = yFilter.filter(point.y, alpha: smoothingAlpha(dt: dtSafe, cutoff: cutoffY))
    return CGPoint(x: fx, y: fy)
  }

  private func smoothingAlpha(dt: CGFloat, cutoff: CGFloat) -> CGFloat {
    let tau = 1 / (2 * .pi * max(0.0001, cutoff))
    return 1 / (1 + tau / dt)
  }
}

final class TemporalJointTracker {
  private struct KinematicLink {
    let child: PushlyJointName
    let parent: PushlyJointName
    let confidenceMultiplier: Float
  }

  private struct OneEuroParameters {
    let minCutoff: CGFloat
    let beta: CGFloat
    let dCutoff: CGFloat
  }

  private let minDetectedJointsForBody = 3
  private let hardResetGap: TimeInterval = 0.32
  private let missingJointPredictionMaxAge: TimeInterval = 0.42
  private let lowerBodyLinks: [KinematicLink] = [
    KinematicLink(child: .leftHip, parent: .leftShoulder, confidenceMultiplier: 0.82),
    KinematicLink(child: .rightHip, parent: .rightShoulder, confidenceMultiplier: 0.82),
    KinematicLink(child: .leftKnee, parent: .leftHip, confidenceMultiplier: 0.74),
    KinematicLink(child: .rightKnee, parent: .rightHip, confidenceMultiplier: 0.74),
    KinematicLink(child: .leftAnkle, parent: .leftKnee, confidenceMultiplier: 0.66),
    KinematicLink(child: .rightAnkle, parent: .rightKnee, confidenceMultiplier: 0.66),
    KinematicLink(child: .leftFoot, parent: .leftAnkle, confidenceMultiplier: 0.62),
    KinematicLink(child: .rightFoot, parent: .rightAnkle, confidenceMultiplier: 0.62)
  ]

  private let config: PushlyPoseConfig
  private var stateByJoint: [PushlyJointName: JointTrackState] = [:]
  private var filtersByJoint: [PushlyJointName: OneEuroJointFilter] = [:]
  private var hysteresisVisibilityByJoint: [PushlyJointName: Bool] = [:]
  private var lockedOffsetsByJoint: [PushlyJointName: KinematicOffsetState] = [:]
  private var lastTimestamp: TimeInterval = 0
  private var lastValidFrameTime: TimeInterval?

  init(config: PushlyPoseConfig) {
    self.config = config
  }

  func update(
    measured: [PushlyJointName: PoseJointMeasurement],
    lowLightDetected: Bool,
    roiHint: CGRect?,
    frameTimestamp: TimeInterval
  ) -> [PushlyJointName: TrackedJoint] {
    let dt = frameDelta(now: frameTimestamp)
    let hasValidBody = measured.count >= minDetectedJointsForBody

    if hasValidBody {
      lastValidFrameTime = frameTimestamp
    } else if let lastValidFrameTime, frameTimestamp - lastValidFrameTime > hardResetGap {
      hardReset()
      lastTimestamp = frameTimestamp
      return [:]
    }

    var next: [PushlyJointName: TrackedJoint] = [:]

    for jointName in PushlyJointName.allCases {
      if let measurement = measured[jointName] {
        if measurement.sourceType == .missing {
          if let tracked = updateMissingJoint(name: jointName, fallbackPoint: measurement.point, now: frameTimestamp, dt: dt) {
            next[jointName] = tracked
          } else {
            next[jointName] = explicitMissingJoint(name: jointName, fallbackPoint: measurement.point, now: frameTimestamp)
          }
          continue
        }

        let tracked = updateMeasuredJoint(
          measurement,
          now: frameTimestamp,
          dt: dt,
          lowLightDetected: lowLightDetected,
          roiHint: roiHint
        )
        next[jointName] = tracked
        continue
      }

      if let tracked = updateMissingJoint(name: jointName, now: frameTimestamp, dt: dt) {
        next[jointName] = tracked
      }
    }

    if hasValidBody {
      updateStableOffsets(from: next, now: frameTimestamp)
      applyKinematicInference(joints: &next, now: frameTimestamp)
    }

    for jointName in PushlyJointName.allCases {
      hysteresisVisibilityByJoint[jointName] = next[jointName]?.sourceType != .missing && next[jointName] != nil
    }

    stateByJoint = Dictionary(uniqueKeysWithValues: next.map { name, joint in
      let previousMeasuredAt = stateByJoint[name]?.lastMeasuredTime ?? joint.timestamp
      let lastMeasuredAt: TimeInterval = {
        switch joint.sourceType {
        case .inferred, .predicted, .missing:
          return previousMeasuredAt
        default:
          return joint.timestamp
        }
      }()

      return (name, JointTrackState(
        smoothedPosition: joint.smoothedPosition,
        rawPosition: joint.rawPosition,
        velocity: joint.velocity,
        renderConfidence: joint.renderConfidence,
        logicConfidence: joint.logicConfidence,
        visibility: joint.visibility,
        presence: joint.presence,
        inFrame: joint.inFrame,
        sourceType: joint.sourceType,
        lastUpdateTime: joint.timestamp,
        lastMeasuredTime: lastMeasuredAt
      ))
    })

    lastTimestamp = frameTimestamp
    return next
  }

  func hardReset() {
    stateByJoint.removeAll()
    filtersByJoint.removeAll()
    hysteresisVisibilityByJoint.removeAll()
    lockedOffsetsByJoint.removeAll()
    lastValidFrameTime = nil
    lastTimestamp = 0
  }

  private func frameDelta(now: TimeInterval) -> TimeInterval {
    if lastTimestamp <= 0 {
      return 1.0 / 30.0
    }
    return max(1.0 / 120.0, min(now - lastTimestamp, 1.0 / 8.0))
  }

  private func updateMeasuredJoint(
    _ measurement: PoseJointMeasurement,
    now: TimeInterval,
    dt: TimeInterval,
    lowLightDetected: Bool,
    roiHint _: CGRect?
  ) -> TrackedJoint {
    let previous = stateByJoint[measurement.name]
    let previousSmoothed = previous?.smoothedPosition ?? measurement.point

    let sourceType = sourceTypeForMeasurement(measurement, hasHistory: previous != nil)
    hysteresisVisibilityByJoint[measurement.name] = sourceType != .missing

    var oneEuro = filtersByJoint[measurement.name] ?? OneEuroJointFilter()
    if previous == nil || dt > hardResetGap {
      oneEuro.reset()
    }

    let oneEuroParams = oneEuroParameters(
      joint: measurement.name,
      sourceType: sourceType,
      confidence: measurement.confidence,
      lowLightDetected: lowLightDetected
    )

    let stabilizedMeasurement = stabilizedMeasurementPoint(
      measurement: measurement,
      previousSmoothed: previousSmoothed,
      dt: dt
    )

    let filteredRaw = oneEuro.filter(
      stabilizedMeasurement,
      dt: dt,
      minCutoff: oneEuroParams.minCutoff,
      beta: oneEuroParams.beta,
      dCutoff: oneEuroParams.dCutoff
    )
    filtersByJoint[measurement.name] = oneEuro
    let maxStep = maxPerFrameStep(
      sourceType: sourceType,
      confidence: measurement.confidence,
      dt: dt
    )
    let filteredTarget = clampStep(from: previousSmoothed, to: filteredRaw, maxStep: maxStep)

    let smoothedVelocity = CGVector(
      dx: (filteredTarget.x - previousSmoothed.x) / CGFloat(max(dt, 0.0001)),
      dy: (filteredTarget.y - previousSmoothed.y) / CGFloat(max(dt, 0.0001))
    )

    let renderConfidence = blendedRenderConfidence(
      sourceType: sourceType,
      measurementConfidence: measurement.confidence,
      previous: previous?.renderConfidence ?? 0
    )
    let logicConfidence = logicConfidenceForTrackedMeasurement(
      sourceType: sourceType,
      confidence: measurement.confidence
    )

    stateByJoint[measurement.name] = JointTrackState(
      smoothedPosition: filteredTarget,
      rawPosition: stabilizedMeasurement,
      velocity: smoothedVelocity,
      renderConfidence: renderConfidence,
      logicConfidence: logicConfidence,
      visibility: measurement.visibility,
      presence: measurement.presence,
      inFrame: measurement.inFrame,
      sourceType: sourceType,
      lastUpdateTime: now,
      lastMeasuredTime: now
    )

    return TrackedJoint(
      name: measurement.name,
      rawPosition: stabilizedMeasurement,
      smoothedPosition: filteredTarget,
      velocity: smoothedVelocity,
      rawConfidence: measurement.confidence,
      renderConfidence: renderConfidence,
      logicConfidence: logicConfidence,
      visibility: measurement.visibility,
      presence: measurement.presence,
      inFrame: measurement.inFrame,
      sourceType: sourceType,
      timestamp: now
    )
  }

  private func updateMissingJoint(
    name: PushlyJointName,
    fallbackPoint: CGPoint? = nil,
    now: TimeInterval,
    dt: TimeInterval
  ) -> TrackedJoint? {
    guard let previous = stateByJoint[name] else {
      return nil
    }

    let ageSinceMeasured = now - previous.lastMeasuredTime
    guard ageSinceMeasured <= missingJointPredictionMaxAge else {
      return nil
    }

    let decay = Float(exp(-6.0 * ageSinceMeasured / missingJointPredictionMaxAge))
    let renderConfidence = max(0.04, previous.renderConfidence * decay)
    let dampedVelocity = previous.velocity * 0.5

    let nextState = JointTrackState(
      smoothedPosition: previous.smoothedPosition,
      rawPosition: previous.rawPosition,
      velocity: dampedVelocity,
      renderConfidence: renderConfidence,
      logicConfidence: 0,
      visibility: previous.visibility * decay,
      presence: previous.presence * decay,
      inFrame: previous.inFrame,
      sourceType: .predicted,
      lastUpdateTime: now,
      lastMeasuredTime: previous.lastMeasuredTime
    )
    stateByJoint[name] = nextState

    return TrackedJoint(
      name: name,
      rawPosition: fallbackPoint ?? previous.rawPosition,
      smoothedPosition: previous.smoothedPosition,
      velocity: dampedVelocity,
      rawConfidence: 0,
      renderConfidence: renderConfidence,
      logicConfidence: 0,
      visibility: nextState.visibility,
      presence: nextState.presence,
      inFrame: nextState.inFrame,
      sourceType: .predicted,
      timestamp: now
    )
  }

  private func explicitMissingJoint(
    name: PushlyJointName,
    fallbackPoint: CGPoint,
    now: TimeInterval
  ) -> TrackedJoint {
    filtersByJoint[name] = nil
    stateByJoint[name] = nil
    hysteresisVisibilityByJoint[name] = false
    let clamped = clamp01(fallbackPoint)
    return TrackedJoint(
      name: name,
      rawPosition: clamped,
      smoothedPosition: clamped,
      velocity: .zero,
      rawConfidence: 0,
      renderConfidence: 0,
      logicConfidence: 0,
      visibility: 0,
      presence: 0,
      inFrame: false,
      sourceType: .missing,
      timestamp: now
    )
  }

  private func sourceTypeForMeasurement(_ measurement: PoseJointMeasurement, hasHistory: Bool) -> PushlyJointSourceType {
    if measurement.sourceType == .missing {
      return .missing
    }
    if measurement.sourceType == .inferred {
      return .inferred
    }
    if measurement.sourceType == .predicted {
      return .predicted
    }

    let gateOpen = confidenceGateAllowsTracking(measurement)
    guard gateOpen else {
      return hasHistory ? .inferred : .missing
    }

    let confidence = measurement.confidence
    if confidence >= config.tracker.confidenceHysteresisEnter {
      return .measured
    }
    if confidence >= config.tracker.confidenceHysteresisExit {
      return .lowConfidenceMeasured
    }
    return hasHistory ? .inferred : .lowConfidenceMeasured
  }

  private func confidenceGateAllowsTracking(_ measurement: PoseJointMeasurement) -> Bool {
    let wasVisible = hysteresisVisibilityByJoint[measurement.name] ?? false
    let support = min(measurement.visibility, measurement.presence)
    let evidence = measurement.inFrame ? min(measurement.confidence, support) : measurement.confidence * 0.5

    if wasVisible {
      return measurement.confidence >= config.tracker.confidenceHysteresisExit
        || support >= config.tracker.confidenceHysteresisExit
    }

    return evidence >= config.tracker.confidenceHysteresisEnter
  }

  private func blendedRenderConfidence(
    sourceType: PushlyJointSourceType,
    measurementConfidence: Float,
    previous: Float
  ) -> Float {
    switch sourceType {
    case .measured:
      return min(1, max(0.2, measurementConfidence))
    case .lowConfidenceMeasured:
      return min(0.8, max(0.1, measurementConfidence * 0.8 + previous * 0.2))
    case .inferred, .predicted:
      return max(0.06, previous * 0.85)
    case .missing:
      return 0
    }
  }

  private func logicConfidenceForTrackedMeasurement(
    sourceType: PushlyJointSourceType,
    confidence: Float
  ) -> Float {
    switch sourceType {
    case .measured:
      return max(0.24, confidence)
    case .lowConfidenceMeasured:
      return max(0.18, confidence * 0.92)
    case .inferred:
      return max(0.2, confidence * 0.5)
    case .predicted, .missing:
      return 0
    }
  }

  private func maxPerFrameStep(
    sourceType: PushlyJointSourceType,
    confidence: Float,
    dt: TimeInterval
  ) -> CGFloat {
    let base: CGFloat
    switch sourceType {
    case .measured:
      base = 0.072
    case .lowConfidenceMeasured:
      base = 0.056
    case .inferred:
      base = 0.046
    case .predicted, .missing:
      base = 0.042
    }

    let confidenceBoost = CGFloat(max(0, min(1, confidence))) * 0.05
    let frameScale = CGFloat(max(0.7, min(2.0, dt / (1.0 / 30.0))))
    return max(0.028, (base + confidenceBoost) * frameScale)
  }

  private func clampStep(from previous: CGPoint, to target: CGPoint, maxStep: CGFloat) -> CGPoint {
    let delta = CGVector(dx: target.x - previous.x, dy: target.y - previous.y)
    let distance = sqrt(delta.dx * delta.dx + delta.dy * delta.dy)
    guard distance > maxStep, distance > 0.0001 else {
      return target
    }
    let scale = maxStep / distance
    return CGPoint(
      x: previous.x + delta.dx * scale,
      y: previous.y + delta.dy * scale
    )
  }

  private func oneEuroParameters(
    joint: PushlyJointName,
    sourceType: PushlyJointSourceType,
    confidence: Float,
    lowLightDetected: Bool
  ) -> OneEuroParameters {
    var minCutoff: CGFloat
    var beta: CGFloat
    let dCutoff: CGFloat = 1.0

    switch joint {
    case .nose, .head, .leftShoulder, .rightShoulder, .leftHip, .rightHip:
      minCutoff = 0.02
      beta = 4.5
    case .leftElbow, .rightElbow, .leftKnee, .rightKnee:
      minCutoff = 0.03
      beta = 5.2
    case .leftWrist, .rightWrist, .leftHand, .rightHand, .leftAnkle, .rightAnkle, .leftFoot, .rightFoot:
      minCutoff = 0.05
      beta = 6.0
    }

    if lowLightDetected {
      minCutoff *= 1.1
      beta *= 0.95
    }

    if confidence < 0.35 {
      minCutoff *= 1.15
      beta *= 0.96
    }

    if sourceType == .inferred || sourceType == .predicted {
      minCutoff *= 1.1
      beta *= 0.9
    }

    return OneEuroParameters(
      minCutoff: min(0.05, max(0.02, minCutoff)),
      beta: min(6.0, max(4.5, beta)),
      dCutoff: dCutoff
    )
  }

  private func stabilizedMeasurementPoint(
    measurement: PoseJointMeasurement,
    previousSmoothed: CGPoint,
    dt: TimeInterval
  ) -> CGPoint {
    let clampedMeasurement = clamp01(measurement.point)
    let delta = CGVector(
      dx: clampedMeasurement.x - previousSmoothed.x,
      dy: clampedMeasurement.y - previousSmoothed.y
    )
    let distance = vectorMagnitude(delta)
    let frameScale = CGFloat(max(0.8, min(1.6, dt / (1.0 / 30.0))))
    let freezeThreshold = microJitterThreshold(for: measurement.name, confidence: measurement.confidence) * frameScale

    if distance <= freezeThreshold {
      return previousSmoothed
    }

    let alpha: CGFloat = {
      let c = CGFloat(max(0, min(1, measurement.confidence)))
      // Low confidence should move cautiously; high confidence can follow faster.
      return min(0.88, max(0.44, 0.44 + c * 0.44))
    }()

    return CGPoint(
      x: previousSmoothed.x + (clampedMeasurement.x - previousSmoothed.x) * alpha,
      y: previousSmoothed.y + (clampedMeasurement.y - previousSmoothed.y) * alpha
    )
  }

  private func microJitterThreshold(for joint: PushlyJointName, confidence: Float) -> CGFloat {
    let base: CGFloat
    switch joint {
    case .nose, .head, .leftShoulder, .rightShoulder, .leftHip, .rightHip:
      base = 0.0026
    case .leftElbow, .rightElbow, .leftKnee, .rightKnee:
      base = 0.0029
    case .leftWrist, .rightWrist, .leftHand, .rightHand, .leftAnkle, .rightAnkle, .leftFoot, .rightFoot:
      base = 0.0033
    }

    let confidenceFactor = CGFloat(max(0, min(1, confidence)))
    let lowConfidenceBoost = (1 - confidenceFactor) * 0.0016
    return base + lowConfidenceBoost
  }

  private func applyKinematicInference(joints: inout [PushlyJointName: TrackedJoint], now: TimeInterval) {
    for link in lowerBodyLinks {
      inferLinkedJoint(link, joints: &joints, now: now)
    }
    inferArmJoint(
      shoulder: .leftShoulder,
      elbow: .leftElbow,
      wrist: .leftWrist,
      joints: &joints,
      now: now
    )
    inferArmJoint(
      shoulder: .rightShoulder,
      elbow: .rightElbow,
      wrist: .rightWrist,
      joints: &joints,
      now: now
    )
  }

  private func inferArmJoint(
    shoulder: PushlyJointName,
    elbow: PushlyJointName,
    wrist: PushlyJointName,
    joints: inout [PushlyJointName: TrackedJoint],
    now: TimeInterval
  ) {
    guard let shoulderJoint = joints[shoulder], shoulderJoint.isRenderable,
          let elbowJoint = joints[elbow], elbowJoint.isRenderable else {
      return
    }
    guard var wristJoint = joints[wrist], wristJoint.sourceType == .missing || wristJoint.renderConfidence < 0.08 else {
      return
    }

    let vector = CGVector(
      dx: elbowJoint.smoothedPosition.x - shoulderJoint.smoothedPosition.x,
      dy: elbowJoint.smoothedPosition.y - shoulderJoint.smoothedPosition.y
    )
    let estimated = clamp01(
      CGPoint(
        x: elbowJoint.smoothedPosition.x + vector.dx * config.tracker.kinematicArmExtensionRatio,
        y: elbowJoint.smoothedPosition.y + vector.dy * config.tracker.kinematicArmExtensionRatio
      )
    )

    wristJoint.rawPosition = estimated
    wristJoint.smoothedPosition = estimated
    wristJoint.velocity = .zero
    wristJoint.rawConfidence = 0
    wristJoint.renderConfidence = min(shoulderJoint.renderConfidence, elbowJoint.renderConfidence) * 0.5
    wristJoint.logicConfidence = max(0.18, wristJoint.renderConfidence * 0.42)
    wristJoint.visibility = min(shoulderJoint.visibility, elbowJoint.visibility) * 0.6
    wristJoint.presence = min(shoulderJoint.presence, elbowJoint.presence) * 0.6
    wristJoint.inFrame = true
    wristJoint.sourceType = .inferred
    wristJoint.timestamp = now
    joints[wrist] = wristJoint
  }

  private func updateStableOffsets(from joints: [PushlyJointName: TrackedJoint], now: TimeInterval) {
    for link in lowerBodyLinks {
      guard let parent = joints[link.parent],
            let child = joints[link.child],
            isStableMeasuredJoint(parent),
            isStableMeasuredJoint(child) else {
        continue
      }

      lockedOffsetsByJoint[link.child] = KinematicOffsetState(
        vector: CGVector(
          dx: child.smoothedPosition.x - parent.smoothedPosition.x,
          dy: child.smoothedPosition.y - parent.smoothedPosition.y
        ),
        timestamp: now,
        confidence: min(parent.renderConfidence, child.renderConfidence)
      )
    }
  }

  private func inferLinkedJoint(
    _ link: KinematicLink,
    joints: inout [PushlyJointName: TrackedJoint],
    now: TimeInterval
  ) {
    guard needsKinematicLock(for: joints[link.child]) else {
      return
    }
    guard let parentJoint = joints[link.parent],
          parentJoint.isRenderable,
          parentJoint.renderConfidence >= config.tracker.kinematicParentConfidenceMin else {
      return
    }
    guard let offset = lockedOffsetsByJoint[link.child],
          now - offset.timestamp <= config.tracker.kinematicLowerBodyMaxAge else {
      return
    }

    let estimated = clamp01(
      CGPoint(
        x: parentJoint.smoothedPosition.x + offset.vector.dx,
        y: parentJoint.smoothedPosition.y + offset.vector.dy
      )
    )

    let inferredConfidence = min(parentJoint.renderConfidence, offset.confidence) * link.confidenceMultiplier
    joints[link.child] = TrackedJoint(
      name: link.child,
      rawPosition: estimated,
      smoothedPosition: estimated,
      velocity: .zero,
      rawConfidence: 0,
      renderConfidence: max(config.tracker.inferenceConfidenceFloor, inferredConfidence),
      logicConfidence: max(0.2, inferredConfidence * 0.42),
      visibility: min(parentJoint.visibility, inferredConfidence),
      presence: min(parentJoint.presence, inferredConfidence),
      inFrame: true,
      sourceType: .inferred,
      timestamp: now
    )
  }

  private func isStableMeasuredJoint(_ joint: TrackedJoint) -> Bool {
    (joint.sourceType == .measured || joint.sourceType == .lowConfidenceMeasured)
      && joint.renderConfidence >= max(config.tracker.confidenceHysteresisExit, 0.32)
      && joint.inFrame
  }

  private func needsKinematicLock(for joint: TrackedJoint?) -> Bool {
    guard let joint else { return true }
    if joint.sourceType == .missing || joint.sourceType == .predicted || joint.sourceType == .inferred {
      return true
    }
    return joint.renderConfidence < config.tracker.confidenceHysteresisExit || !joint.inFrame
  }

  private func vectorMagnitude(_ vector: CGVector) -> CGFloat {
    sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
  }

  private func lerp(from: CGPoint, to: CGPoint, alpha: CGFloat) -> CGPoint {
    CGPoint(
      x: from.x + (to.x - from.x) * alpha,
      y: from.y + (to.y - from.y) * alpha
    )
  }

  private func clamp01(_ point: CGPoint) -> CGPoint {
    CGPoint(x: min(1, max(0, point.x)), y: min(1, max(0, point.y)))
  }
}
#endif
