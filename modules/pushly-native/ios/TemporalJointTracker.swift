import Foundation

#if os(iOS)
import CoreGraphics

private struct JointTrackState {
  var smoothedPosition: CGPoint
  var rawPosition: CGPoint
  var velocity: CGVector
  var acceleration: CGVector
  var renderConfidence: Float
  var logicConfidence: Float
  var visibility: Float
  var presence: Float
  var inFrame: Bool
  var sourceType: PushlyJointSourceType
  var lastUpdateTime: TimeInterval
  var lastMeasuredTime: TimeInterval
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
  private struct OneEuroParameters {
    let minCutoff: CGFloat
    let beta: CGFloat
    let dCutoff: CGFloat
    let predictionLeadSeconds: CGFloat
  }

  private let minDetectedJointsForBody = 3
  private let hardResetGap: TimeInterval = 0.12
  private let missingJointPredictionMaxAge: TimeInterval = 0.1

  private let config: PushlyPoseConfig
  private var stateByJoint: [PushlyJointName: JointTrackState] = [:]
  private var filtersByJoint: [PushlyJointName: OneEuroJointFilter] = [:]
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
          next[jointName] = explicitMissingJoint(name: jointName, fallbackPoint: measurement.point, now: frameTimestamp)
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
      applyKinematicInference(joints: &next, now: frameTimestamp)
    }

    stateByJoint = Dictionary(uniqueKeysWithValues: next.map { name, joint in
      let previousMeasuredAt = stateByJoint[name]?.lastMeasuredTime ?? joint.timestamp
      let lastMeasuredAt: TimeInterval = {
        switch joint.sourceType {
        case .predicted, .missing:
          return previousMeasuredAt
        default:
          return joint.timestamp
        }
      }()

      return (name, JointTrackState(
        smoothedPosition: joint.smoothedPosition,
        rawPosition: joint.rawPosition,
        velocity: joint.velocity,
        acceleration: stateByJoint[name]?.acceleration ?? .zero,
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
    roiHint: CGRect?
  ) -> TrackedJoint {
    let previous = stateByJoint[measurement.name]
    let previousSmoothed = previous?.smoothedPosition ?? measurement.point
    let previousVelocity = previous?.velocity ?? .zero

    let measuredVelocity = CGVector(
      dx: (measurement.point.x - previousSmoothed.x) / CGFloat(max(dt, 0.0001)),
      dy: (measurement.point.y - previousSmoothed.y) / CGFloat(max(dt, 0.0001))
    )

    let velocity = previousVelocity * 0.24 + measuredVelocity * 0.76
    let acceleration = CGVector(
      dx: (velocity.dx - previousVelocity.dx) / CGFloat(max(dt, 0.0001)),
      dy: (velocity.dy - previousVelocity.dy) / CGFloat(max(dt, 0.0001))
    )

    let predictedFromDynamics = clamp01(
      CGPoint(
        x: previousSmoothed.x + velocity.dx * CGFloat(dt) + 0.5 * acceleration.dx * CGFloat(dt * dt),
        y: previousSmoothed.y + velocity.dy * CGFloat(dt) + 0.5 * acceleration.dy * CGFloat(dt * dt)
      )
    )

    let sourceType = sourceTypeForMeasurement(measurement, hasHistory: previous != nil)

    let blendedTarget = blendMeasuredAndPredicted(
      measured: measurement.point,
      predicted: predictedFromDynamics,
      confidence: measurement.confidence,
      sourceType: sourceType,
      hasHistory: previous != nil
    )

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

    let filteredTarget = oneEuro.filter(
      blendedTarget,
      dt: dt,
      minCutoff: oneEuroParams.minCutoff,
      beta: oneEuroParams.beta,
      dCutoff: oneEuroParams.dCutoff
    )
    filtersByJoint[measurement.name] = oneEuro

    let blendedVelocity = CGVector(
      dx: (filteredTarget.x - previousSmoothed.x) / CGFloat(max(dt, 0.0001)),
      dy: (filteredTarget.y - previousSmoothed.y) / CGFloat(max(dt, 0.0001))
    )

    let roiBoost = roiHint == nil ? 1.0 : 0.94
    let predictedPos = clamp01(
      filteredTarget + (blendedVelocity * (oneEuroParams.predictionLeadSeconds * roiBoost))
    )
    let lockBlend = sourceType == .inferred ? 0.7 : 0.92
    let lockedPos = lerp(from: filteredTarget, to: predictedPos, alpha: lockBlend)

    let renderConfidence = blendedRenderConfidence(
      sourceType: sourceType,
      measurementConfidence: measurement.confidence,
      previous: previous?.renderConfidence ?? 0
    )
    let logicConfidence: Float = sourceType == .inferred ? 0 : max(0.1, measurement.confidence)

    stateByJoint[measurement.name] = JointTrackState(
      smoothedPosition: lockedPos,
      rawPosition: measurement.point,
      velocity: blendedVelocity,
      acceleration: acceleration,
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
      rawPosition: measurement.point,
      smoothedPosition: lockedPos,
      velocity: blendedVelocity,
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

  private func updateMissingJoint(name: PushlyJointName, now: TimeInterval, dt: TimeInterval) -> TrackedJoint? {
    guard let previous = stateByJoint[name] else {
      return nil
    }

    let ageSinceMeasured = now - previous.lastMeasuredTime
    guard ageSinceMeasured <= missingJointPredictionMaxAge else {
      return nil
    }

    let predicted = clamp01(
      CGPoint(
        x: previous.smoothedPosition.x + previous.velocity.dx * CGFloat(dt) + 0.5 * previous.acceleration.dx * CGFloat(dt * dt),
        y: previous.smoothedPosition.y + previous.velocity.dy * CGFloat(dt) + 0.5 * previous.acceleration.dy * CGFloat(dt * dt)
      )
    )
    let decay = Float(exp(-6.0 * ageSinceMeasured / missingJointPredictionMaxAge))
    let renderConfidence = max(0.04, previous.renderConfidence * decay)
    let dampedVelocity = previous.velocity * 0.8

    let nextState = JointTrackState(
      smoothedPosition: predicted,
      rawPosition: previous.rawPosition,
      velocity: dampedVelocity,
      acceleration: previous.acceleration * 0.7,
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
      rawPosition: previous.rawPosition,
      smoothedPosition: predicted,
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

  private func blendMeasuredAndPredicted(
    measured: CGPoint,
    predicted: CGPoint,
    confidence: Float,
    sourceType: PushlyJointSourceType,
    hasHistory: Bool
  ) -> CGPoint {
    guard hasHistory else {
      return measured
    }

    if sourceType == .inferred {
      return lerp(from: predicted, to: measured, alpha: 0.35)
    }

    let high: Float = max(config.tracker.highConfidenceMin, 0.55)
    let medium: Float = max(config.tracker.lowConfidenceMin, 0.2)

    if confidence >= high {
      return measured
    }

    if confidence >= medium {
      let t = CGFloat((confidence - medium) / max(0.0001, high - medium))
      return lerp(from: predicted, to: measured, alpha: t)
    }

    return predicted
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

    let confidence = measurement.confidence
    if confidence >= max(config.tracker.highConfidenceMin, 0.55) {
      return .measured
    }
    if confidence >= max(config.tracker.lowConfidenceMin, 0.2) {
      return .lowConfidenceMeasured
    }
    return hasHistory ? .inferred : .lowConfidenceMeasured
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

  private func oneEuroParameters(
    joint: PushlyJointName,
    sourceType: PushlyJointSourceType,
    confidence: Float,
    lowLightDetected: Bool
  ) -> OneEuroParameters {
    var minCutoff: CGFloat
    var beta: CGFloat
    let dCutoff: CGFloat = 1.7

    switch joint {
    case .nose, .head, .leftShoulder, .rightShoulder, .leftHip, .rightHip:
      minCutoff = 0.05
      beta = 4.2
    case .leftElbow, .rightElbow, .leftKnee, .rightKnee:
      minCutoff = 0.1
      beta = 4.6
    case .leftWrist, .rightWrist, .leftHand, .rightHand, .leftAnkle, .rightAnkle, .leftFoot, .rightFoot:
      minCutoff = 0.1
      beta = 5.0
    }

    if lowLightDetected {
      minCutoff *= 0.95
      beta *= 0.96
    }

    if confidence < 0.35 {
      minCutoff *= 0.9
      beta *= 0.92
    }

    if sourceType == .inferred || sourceType == .predicted {
      minCutoff *= 0.9
      beta *= 0.9
    }

    return OneEuroParameters(
      minCutoff: max(0.05, minCutoff),
      beta: max(4.0, beta),
      dCutoff: dCutoff,
      predictionLeadSeconds: 0.0
    )
  }

  private func applyKinematicInference(joints: inout [PushlyJointName: TrackedJoint], now: TimeInterval) {
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
    wristJoint.logicConfidence = 0
    wristJoint.visibility = min(shoulderJoint.visibility, elbowJoint.visibility) * 0.6
    wristJoint.presence = min(shoulderJoint.presence, elbowJoint.presence) * 0.6
    wristJoint.inFrame = true
    wristJoint.sourceType = .inferred
    wristJoint.timestamp = now
    joints[wrist] = wristJoint
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
