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
  var lastMeasuredPosition: CGPoint
}

private struct KinematicOffsetState {
  var vector: CGVector
  var timestamp: TimeInterval
  var confidence: Float
}

private struct TorsoFrameState {
  var shoulderMid: CGPoint
  var hipMid: CGPoint
  var shoulderAxis: CGVector
  var longitudinalAxis: CGVector
  var shoulderSpan: CGFloat
  var torsoLength: CGFloat
  var timestamp: TimeInterval
}

private struct TorsoOffsetState {
  var localX: CGFloat
  var localY: CGFloat
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
  var previousTimestamp: TimeInterval = 0
  var initialized = false

  mutating func reset() {
    xFilter = LowPassFilter1D()
    yFilter = LowPassFilter1D()
    dxFilter = LowPassFilter1D()
    dyFilter = LowPassFilter1D()
    previousRawX = 0
    previousRawY = 0
    previousTimestamp = 0
    initialized = false
  }

  mutating func filter(
    _ point: CGPoint,
    timestamp: TimeInterval,
    minCutoff: CGFloat,
    beta: CGFloat,
    dCutoff: CGFloat
  ) -> CGPoint {
    let dtRaw: TimeInterval
    if previousTimestamp > 0 {
      dtRaw = timestamp - previousTimestamp
    } else {
      dtRaw = 1.0 / 120.0
    }
    previousTimestamp = timestamp
    let dtSafe = CGFloat(max(dtRaw, 1.0 / 120.0))
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
  struct SideIdentityDiagnostics {
    let lockSwapped: Bool
    let swapEvidenceStreak: Int
    let keepEvidenceStreak: Int
    let swapAppliedThisFrame: Bool
  }
  private struct KinematicLink {
    let child: PushlyJointName
    let parent: PushlyJointName
    let confidenceMultiplier: Float
  }

  private struct BilateralPairEvidence {
    let left: PushlyJointName
    let right: PushlyJointName
    let weight: Double
  }

  private struct SideChainEvidence {
    let left: [PushlyJointName]
    let right: [PushlyJointName]
    let weight: Double
  }

  private struct SideEvidenceResult {
    let direction: SideEvidenceDirection
    let torsoSwapSupport: Double
    let torsoKeepSupport: Double
  }

  private enum SideEvidenceDirection {
    case keep
    case swap
    case neutral
  }

  private struct OneEuroParameters {
    let minCutoff: CGFloat
    let beta: CGFloat
    let dCutoff: CGFloat
    let predictionLeadSeconds: TimeInterval
  }

  private let minDetectedJointsForBody = 3
  private let hardResetGap: TimeInterval = 0.32
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
  private let sideEvidencePairs: [BilateralPairEvidence] = [
    BilateralPairEvidence(left: .leftShoulder, right: .rightShoulder, weight: 1.45),
    BilateralPairEvidence(left: .leftHip, right: .rightHip, weight: 1.35),
    BilateralPairEvidence(left: .leftElbow, right: .rightElbow, weight: 1.1),
    BilateralPairEvidence(left: .leftWrist, right: .rightWrist, weight: 1.1),
    BilateralPairEvidence(left: .leftKnee, right: .rightKnee, weight: 1.0),
    BilateralPairEvidence(left: .leftAnkle, right: .rightAnkle, weight: 1.0)
  ]
  private let sideSwapPairs: [(PushlyJointName, PushlyJointName)] = [
    (.leftShoulder, .rightShoulder),
    (.leftElbow, .rightElbow),
    (.leftWrist, .rightWrist),
    (.leftHand, .rightHand),
    (.leftHip, .rightHip),
    (.leftKnee, .rightKnee),
    (.leftAnkle, .rightAnkle),
    (.leftFoot, .rightFoot)
  ]
  private let sideEvidenceHistoryMaxAge: TimeInterval = 0.36
  private let sideEvidenceConfidenceMin: Float = 0.22
  private let sideEvidenceMinWeight: Double = 1.4
  private let sideCostMargin: CGFloat = 0.015
  private let sideChainEvidence: [SideChainEvidence] = [
    SideChainEvidence(left: [.leftShoulder, .leftElbow, .leftWrist], right: [.rightShoulder, .rightElbow, .rightWrist], weight: 1.2),
    SideChainEvidence(left: [.leftHip, .leftKnee, .leftAnkle], right: [.rightHip, .rightKnee, .rightAnkle], weight: 1.15),
    SideChainEvidence(left: [.leftShoulder, .leftHip], right: [.rightShoulder, .rightHip], weight: 1.05)
  ]

  private let config: PushlyPoseConfig
  private var stateByJoint: [PushlyJointName: JointTrackState] = [:]
  private var filtersByJoint: [PushlyJointName: OneEuroJointFilter] = [:]
  private var hysteresisVisibilityByJoint: [PushlyJointName: Bool] = [:]
  private var lockedOffsetsByJoint: [PushlyJointName: KinematicOffsetState] = [:]
  private var torsoOffsetsByJoint: [PushlyJointName: TorsoOffsetState] = [:]
  private var torsoFrame: TorsoFrameState?
  private var lastTimestamp: TimeInterval = 0
  private var lastValidFrameTime: TimeInterval?
  private var sideIdentityLockedAsSwapped = false
  private var sideSwapEvidenceStreak = 0
  private var sideKeepEvidenceStreak = 0
  private var swapAppliedThisFrame = false
  private var sideSwapBlockedUntil: TimeInterval = 0

  var sideIdentityDiagnostics: SideIdentityDiagnostics {
    SideIdentityDiagnostics(
      lockSwapped: sideIdentityLockedAsSwapped,
      swapEvidenceStreak: sideSwapEvidenceStreak,
      keepEvidenceStreak: sideKeepEvidenceStreak,
      swapAppliedThisFrame: swapAppliedThisFrame
    )
  }

  init(config: PushlyPoseConfig) {
    self.config = config
  }

  func update(
    measured: [PushlyJointName: PoseJointMeasurement],
    lowLightDetected: Bool,
    roiHint: CGRect?,
    frameTimestamp: TimeInterval,
    tooCloseFallbackActive: Bool = false,
    reacquireActive: Bool = false,
    pushupFloorModeActive: Bool = false
  ) -> [PushlyJointName: TrackedJoint] {
    let dt = frameDelta(now: frameTimestamp)
    updateSideSwapBlockers(
      measured: measured,
      now: frameTimestamp,
      tooCloseFallbackActive: tooCloseFallbackActive,
      reacquireActive: reacquireActive
    )
    let sideStabilizedMeasured = applySideIdentityLock(to: measured, now: frameTimestamp)
    let hasValidBody = sideStabilizedMeasured.count >= minDetectedJointsForBody

    if hasValidBody {
      lastValidFrameTime = frameTimestamp
    } else if let lastValidFrameTime, frameTimestamp - lastValidFrameTime > hardResetGap {
      hardReset()
      lastTimestamp = frameTimestamp
      return [:]
    }

    var next: [PushlyJointName: TrackedJoint] = [:]

    for jointName in PushlyJointName.allCases {
      if let measurement = sideStabilizedMeasured[jointName] {
        if measurement.sourceType == .missing {
          if let tracked = updateMissingJoint(
            name: jointName,
            fallbackPoint: measurement.point,
            now: frameTimestamp,
            dt: dt,
            pushupFloorModeActive: pushupFloorModeActive
          ) {
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

      if let tracked = updateMissingJoint(
        name: jointName,
        now: frameTimestamp,
        dt: dt,
        pushupFloorModeActive: pushupFloorModeActive
      ) {
        next[jointName] = tracked
      }
    }

    if hasValidBody {
      updateTorsoFrame(from: next, now: frameTimestamp)
      updateStableOffsets(from: next, now: frameTimestamp)
      updateStableTorsoOffsets(from: next, now: frameTimestamp)
      applyTorsoInference(joints: &next, now: frameTimestamp, pushupFloorModeActive: pushupFloorModeActive)
      applyKinematicInference(joints: &next, now: frameTimestamp, pushupFloorModeActive: pushupFloorModeActive)
    } else {
      updateTorsoFrame(from: next, now: frameTimestamp)
      applyTorsoInference(joints: &next, now: frameTimestamp, pushupFloorModeActive: pushupFloorModeActive)
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
        lastMeasuredTime: lastMeasuredAt,
        lastMeasuredPosition: {
          switch joint.sourceType {
          case .inferred, .predicted, .missing:
            return stateByJoint[name]?.lastMeasuredPosition ?? joint.rawPosition
          default:
            return joint.rawPosition
          }
        }()
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
    torsoOffsetsByJoint.removeAll()
    torsoFrame = nil
    sideIdentityLockedAsSwapped = false
    sideSwapEvidenceStreak = 0
    sideKeepEvidenceStreak = 0
    swapAppliedThisFrame = false
    sideSwapBlockedUntil = 0
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

    let projectedMeasurementPoint = predictedMeasurementPoint(
      measurement: measurement,
      previousRaw: previous?.rawPosition,
      dt: dt,
      leadSeconds: oneEuroParams.predictionLeadSeconds
    )
    let measurementForFilter = relockBlendedMeasurementPoint(
      measurementPoint: projectedMeasurementPoint,
      previous: previous
    )

    let smoothedPosition = oneEuro.filter(
      measurementForFilter,
      timestamp: now,
      minCutoff: oneEuroParams.minCutoff,
      beta: oneEuroParams.beta,
      dCutoff: oneEuroParams.dCutoff
    )
    filtersByJoint[measurement.name] = oneEuro

    let renderConfidence = blendedRenderConfidence(
      sourceType: sourceType,
      measurementConfidence: measurement.confidence,
      previous: previous?.renderConfidence ?? 0
    )
    let logicConfidence = logicConfidenceForTrackedMeasurement(
      sourceType: sourceType,
      confidence: measurement.confidence
    )

    let smoothedVelocity = CGVector(
      dx: (smoothedPosition.x - previousSmoothed.x) / CGFloat(max(dt, 0.0001)),
      dy: (smoothedPosition.y - previousSmoothed.y) / CGFloat(max(dt, 0.0001))
    )

    stateByJoint[measurement.name] = JointTrackState(
      smoothedPosition: smoothedPosition,
      rawPosition: measurement.point,
      velocity: smoothedVelocity,
      renderConfidence: renderConfidence,
      logicConfidence: logicConfidence,
      visibility: measurement.visibility,
      presence: measurement.presence,
      inFrame: measurement.inFrame,
      sourceType: sourceType,
      lastUpdateTime: now,
      lastMeasuredTime: now,
      lastMeasuredPosition: measurement.point
    )

    return TrackedJoint(
      name: measurement.name,
      rawPosition: measurement.point,
      smoothedPosition: smoothedPosition,
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
    dt: TimeInterval,
    pushupFloorModeActive: Bool
  ) -> TrackedJoint? {
    guard let previous = stateByJoint[name] else {
      return nil
    }

    let ageSinceMeasured = now - previous.lastMeasuredTime
    let predictionMaxAge = config.tracker.missingJointPredictionMaxAge
      * (pushupFloorModeActive ? config.tracker.pushupMissingJointPredictionMaxAgeScale : 1)
    guard ageSinceMeasured <= predictionMaxAge else {
      return nil
    }

    let dtClamped = max(1.0 / 120.0, min(dt, 1.0 / 8.0))
    let decayRateScale = pushupFloorModeActive ? config.tracker.pushupMissingJointPredictionDecayRateScale : 1
    let velocityDampingRateScale = (pushupFloorModeActive && isPushupDistalJoint(name))
      ? config.tracker.pushupMissingJointPredictionVelocityDampingRateScale
      : 1
    let renderStepDecay = Float(exp(-(config.tracker.missingJointPredictionConfidenceDecayPerSecond * decayRateScale) * dtClamped))
    let visibilityStepDecay = Float(exp(-(config.tracker.missingJointPredictionVisibilityDecayPerSecond * decayRateScale) * dtClamped))
    let velocityStepDecay = CGFloat(exp(-(config.tracker.missingJointPredictionVelocityDampingPerSecond * velocityDampingRateScale) * dtClamped))

    let predictedStep = CGPoint(
      x: previous.smoothedPosition.x + previous.velocity.dx * CGFloat(dtClamped),
      y: previous.smoothedPosition.y + previous.velocity.dy * CGFloat(dtClamped)
    )
    let clampedPrediction = clampExtrapolation(
      point: predictedStep,
      around: previous.lastMeasuredPosition,
      maxDistance: config.tracker.missingJointPredictionMaxExtrapolation
        * (pushupFloorModeActive ? config.tracker.pushupMissingJointPredictionMaxExtrapolationScale : 1)
    )
    let dampedVelocity = previous.velocity * velocityStepDecay
    let renderConfidence = max(0.04, previous.renderConfidence * renderStepDecay)

    let nextState = JointTrackState(
      smoothedPosition: clampedPrediction,
      rawPosition: clampedPrediction,
      velocity: dampedVelocity,
      renderConfidence: renderConfidence,
      logicConfidence: 0,
      visibility: previous.visibility * visibilityStepDecay,
      presence: previous.presence * visibilityStepDecay,
      inFrame: previous.inFrame,
      sourceType: .predicted,
      lastUpdateTime: now,
      lastMeasuredTime: previous.lastMeasuredTime,
      lastMeasuredPosition: previous.lastMeasuredPosition
    )
    stateByJoint[name] = nextState

    return TrackedJoint(
      name: name,
      rawPosition: fallbackPoint ?? clampedPrediction,
      smoothedPosition: clampedPrediction,
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

  private func oneEuroParameters(
    joint: PushlyJointName,
    sourceType: PushlyJointSourceType,
    confidence: Float,
    lowLightDetected: Bool
  ) -> OneEuroParameters {
    var minCutoff: CGFloat
    var beta: CGFloat
    let dCutoff: CGFloat = config.smoothing.logicDCutoff

    switch joint {
    case .nose, .head, .leftShoulder, .rightShoulder, .leftHip, .rightHip:
      minCutoff = config.smoothing.logicCore.minCutoff
      beta = config.smoothing.logicCore.beta
    case .leftElbow, .rightElbow, .leftKnee, .rightKnee:
      minCutoff = config.smoothing.logicMid.minCutoff
      beta = config.smoothing.logicMid.beta
    case .leftWrist, .rightWrist, .leftHand, .rightHand, .leftAnkle, .rightAnkle, .leftFoot, .rightFoot:
      minCutoff = config.smoothing.logicExtremity.minCutoff
      beta = config.smoothing.logicExtremity.beta
    }

    if lowLightDetected {
      minCutoff *= config.smoothing.logicLowLightMinCutoffMultiplier
    }

    if confidence < 0.35 {
      minCutoff *= config.smoothing.logicLowConfidenceMinCutoffMultiplier
    }

    if sourceType == .inferred || sourceType == .predicted {
      minCutoff *= config.smoothing.logicInferredMinCutoffMultiplier
    }

    let minBand = min(config.smoothing.logicCore.minCutoff, min(config.smoothing.logicMid.minCutoff, config.smoothing.logicExtremity.minCutoff))
    let maxBand = max(config.smoothing.logicCore.minCutoff, max(config.smoothing.logicMid.minCutoff, config.smoothing.logicExtremity.minCutoff))
    let minBetaBand = min(config.smoothing.logicCore.beta, min(config.smoothing.logicMid.beta, config.smoothing.logicExtremity.beta))
    return OneEuroParameters(
      minCutoff: min(0.03, max(minBand, minCutoff)),
      beta: min(6.0, max(minBetaBand, beta)),
      dCutoff: dCutoff,
      predictionLeadSeconds: config.smoothing.logicPredictionLeadSeconds
    )
  }

  private func predictedMeasurementPoint(
    measurement: PoseJointMeasurement,
    previousRaw: CGPoint?,
    dt: TimeInterval,
    leadSeconds: TimeInterval
  ) -> CGPoint {
    guard leadSeconds > 0, let previousRaw, dt > 0 else {
      return measurement.point
    }
    let velocity = CGVector(
      dx: (measurement.point.x - previousRaw.x) / CGFloat(dt),
      dy: (measurement.point.y - previousRaw.y) / CGFloat(dt)
    )
    let projected = CGPoint(
      x: measurement.point.x + velocity.dx * CGFloat(leadSeconds),
      y: measurement.point.y + velocity.dy * CGFloat(leadSeconds)
    )
    return clamp01(projected)
  }

  private func applyKinematicInference(
    joints: inout [PushlyJointName: TrackedJoint],
    now: TimeInterval,
    pushupFloorModeActive: Bool
  ) {
    for link in lowerBodyLinks {
      inferLinkedJoint(link, joints: &joints, now: now, pushupFloorModeActive: pushupFloorModeActive)
    }
    inferArmJoint(
      shoulder: .leftShoulder,
      elbow: .leftElbow,
      wrist: .leftWrist,
      joints: &joints,
      now: now,
      pushupFloorModeActive: pushupFloorModeActive
    )
    inferArmJoint(
      shoulder: .rightShoulder,
      elbow: .rightElbow,
      wrist: .rightWrist,
      joints: &joints,
      now: now,
      pushupFloorModeActive: pushupFloorModeActive
    )
  }

  private func inferArmJoint(
    shoulder: PushlyJointName,
    elbow: PushlyJointName,
    wrist: PushlyJointName,
    joints: inout [PushlyJointName: TrackedJoint],
    now: TimeInterval,
    pushupFloorModeActive: Bool
  ) {
    guard let shoulderJoint = joints[shoulder], shoulderJoint.isRenderable,
          let elbowJoint = joints[elbow], elbowJoint.isRenderable else {
      return
    }
    if pushupFloorModeActive,
       let existing = joints[wrist],
       existing.sourceType == .inferred,
       existing.renderConfidence >= config.tracker.pushupTorsoInferencePreserveConfidenceMin {
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
    wristJoint.logicConfidence = pushupFloorModeActive
      ? min(0.17, max(0.12, wristJoint.renderConfidence * 0.3))
      : max(0.18, wristJoint.renderConfidence * 0.42)
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

  private func updateStableTorsoOffsets(from joints: [PushlyJointName: TrackedJoint], now: TimeInterval) {
    guard let torsoFrame else { return }

    for (name, joint) in joints {
      guard isStableMeasuredJoint(joint) else { continue }
      let delta = CGVector(
        dx: joint.smoothedPosition.x - torsoFrame.shoulderMid.x,
        dy: joint.smoothedPosition.y - torsoFrame.shoulderMid.y
      )
      let measuredLocalX = dot(delta, torsoFrame.shoulderAxis)
      let measuredLocalY = dot(delta, torsoFrame.longitudinalAxis)

      if let previous = torsoOffsetsByJoint[name], now - previous.timestamp <= config.tracker.torsoOffsetMaxAge {
        let alpha: CGFloat = 0.34
        torsoOffsetsByJoint[name] = TorsoOffsetState(
          localX: previous.localX + (measuredLocalX - previous.localX) * alpha,
          localY: previous.localY + (measuredLocalY - previous.localY) * alpha,
          timestamp: now,
          confidence: min(1, previous.confidence * 0.6 + joint.renderConfidence * 0.4)
        )
      } else {
        torsoOffsetsByJoint[name] = TorsoOffsetState(
          localX: measuredLocalX,
          localY: measuredLocalY,
          timestamp: now,
          confidence: joint.renderConfidence
        )
      }
    }
  }

  private func applyTorsoInference(
    joints: inout [PushlyJointName: TrackedJoint],
    now: TimeInterval,
    pushupFloorModeActive: Bool
  ) {
    guard let torsoFrame else { return }
    let torsoOffsetMaxAge = config.tracker.torsoOffsetMaxAge
      * (pushupFloorModeActive ? config.tracker.pushupTorsoOffsetMaxAgeScale : 1)

    let candidates: [PushlyJointName] = [
      .leftHip, .rightHip,
      .leftElbow, .rightElbow,
      .leftWrist, .rightWrist,
      .leftKnee, .rightKnee,
      .leftAnkle, .rightAnkle
    ]

    for name in candidates {
      guard needsKinematicLock(for: joints[name]) else { continue }
      guard let offset = torsoOffsetsByJoint[name],
            now - offset.timestamp <= torsoOffsetMaxAge else {
        continue
      }

      let estimated = clamp01(
        CGPoint(
          x: torsoFrame.shoulderMid.x
            + torsoFrame.shoulderAxis.dx * offset.localX
            + torsoFrame.longitudinalAxis.dx * offset.localY,
          y: torsoFrame.shoulderMid.y
            + torsoFrame.shoulderAxis.dy * offset.localX
            + torsoFrame.longitudinalAxis.dy * offset.localY
        )
      )
      let inferredConfidence = max(
        config.tracker.inferenceConfidenceFloor,
        min(0.86, offset.confidence * config.tracker.torsoInferenceConfidenceScale)
      )

      joints[name] = TrackedJoint(
        name: name,
        rawPosition: estimated,
        smoothedPosition: estimated,
        velocity: .zero,
        rawConfidence: 0,
        renderConfidence: inferredConfidence,
        logicConfidence: pushupFloorModeActive && isPushupDistalJoint(name)
          ? min(0.17, max(0.12, inferredConfidence * 0.3))
          : max(0.18, inferredConfidence * 0.38),
        visibility: inferredConfidence * 0.62,
        presence: inferredConfidence * 0.62,
        inFrame: true,
        sourceType: .inferred,
        timestamp: now
      )
    }
  }

  private func updateTorsoFrame(from joints: [PushlyJointName: TrackedJoint], now: TimeInterval) {
    let leftShoulder = joints[.leftShoulder]?.smoothedPosition
    let rightShoulder = joints[.rightShoulder]?.smoothedPosition
    let shoulderMid = midpoint(leftShoulder, rightShoulder)
    guard let shoulderMid else { return }

    let leftHip = joints[.leftHip]?.smoothedPosition
    let rightHip = joints[.rightHip]?.smoothedPosition
    let measuredHipMid = midpoint(leftHip, rightHip)

    let measuredShoulderAxis: CGVector = {
      if let leftShoulder, let rightShoulder {
        return normalize(
          CGVector(
            dx: rightShoulder.x - leftShoulder.x,
            dy: rightShoulder.y - leftShoulder.y
          )
        )
      }
      return torsoFrame?.shoulderAxis ?? CGVector(dx: 1, dy: 0)
    }()

    var measuredLongitudinalAxis: CGVector
    if let measuredHipMid {
      measuredLongitudinalAxis = normalize(
        CGVector(
          dx: measuredHipMid.x - shoulderMid.x,
          dy: measuredHipMid.y - shoulderMid.y
        )
      )
    } else {
      let orthogonal = normalize(CGVector(dx: -measuredShoulderAxis.dy, dy: measuredShoulderAxis.dx))
      if let previous = torsoFrame {
        measuredLongitudinalAxis = dot(previous.longitudinalAxis, orthogonal) >= 0 ? orthogonal : orthogonal * -1
      } else {
        measuredLongitudinalAxis = orthogonal.dy <= 0 ? orthogonal : orthogonal * -1
      }
    }

    let measuredShoulderSpan: CGFloat = {
      if let leftShoulder, let rightShoulder {
        return min(0.52, max(0.05, distance(leftShoulder, rightShoulder)))
      }
      return torsoFrame?.shoulderSpan ?? 0.14
    }()

    let measuredTorsoLength: CGFloat = {
      if let measuredHipMid {
        return min(0.64, max(0.06, distance(shoulderMid, measuredHipMid)))
      }
      return torsoFrame?.torsoLength ?? max(0.08, measuredShoulderSpan * 1.04)
    }()

    let hipMid: CGPoint = {
      if let measuredHipMid {
        return measuredHipMid
      }
      return clamp01(
        CGPoint(
          x: shoulderMid.x + measuredLongitudinalAxis.dx * measuredTorsoLength,
          y: shoulderMid.y + measuredLongitudinalAxis.dy * measuredTorsoLength
        )
      )
    }()

    if let previous = torsoFrame {
      let alpha = min(0.8, max(0.12, config.tracker.torsoFrameSmoothingAlpha))
      let blendedShoulderAxis = normalize(blend(previous.shoulderAxis, measuredShoulderAxis, alpha: alpha))
      let longitudinalCandidate = normalize(blend(previous.longitudinalAxis, measuredLongitudinalAxis, alpha: alpha))
      let blendedLongitudinalAxis = dot(longitudinalCandidate, blendedShoulderAxis) > 0.92
        ? previous.longitudinalAxis
        : longitudinalCandidate
      torsoFrame = TorsoFrameState(
        shoulderMid: blend(previous.shoulderMid, shoulderMid, alpha: alpha),
        hipMid: blend(previous.hipMid, hipMid, alpha: alpha),
        shoulderAxis: blendedShoulderAxis,
        longitudinalAxis: blendedLongitudinalAxis,
        shoulderSpan: previous.shoulderSpan + (measuredShoulderSpan - previous.shoulderSpan) * alpha,
        torsoLength: previous.torsoLength + (measuredTorsoLength - previous.torsoLength) * alpha,
        timestamp: now
      )
      return
    }

    torsoFrame = TorsoFrameState(
      shoulderMid: shoulderMid,
      hipMid: hipMid,
      shoulderAxis: measuredShoulderAxis,
      longitudinalAxis: measuredLongitudinalAxis,
      shoulderSpan: measuredShoulderSpan,
      torsoLength: measuredTorsoLength,
      timestamp: now
    )
  }

  private func inferLinkedJoint(
    _ link: KinematicLink,
    joints: inout [PushlyJointName: TrackedJoint],
    now: TimeInterval,
    pushupFloorModeActive: Bool
  ) {
    if pushupFloorModeActive,
       let existing = joints[link.child],
       existing.sourceType == .inferred,
       existing.renderConfidence >= config.tracker.pushupTorsoInferencePreserveConfidenceMin {
      return
    }
    guard needsKinematicLock(for: joints[link.child]) else {
      return
    }
    guard let parentJoint = joints[link.parent],
          parentJoint.isRenderable,
          parentJoint.renderConfidence >= config.tracker.kinematicParentConfidenceMin else {
      return
    }
    guard let offset = lockedOffsetsByJoint[link.child],
          now - offset.timestamp <= config.tracker.kinematicLowerBodyMaxAge
            * (pushupFloorModeActive ? config.tracker.pushupKinematicLowerBodyMaxAgeScale : 1)
    else {
      return
    }

    let estimated = clamp01(
      CGPoint(
        x: parentJoint.smoothedPosition.x + offset.vector.dx,
        y: parentJoint.smoothedPosition.y + offset.vector.dy
      )
    )

    let inferredConfidence = min(parentJoint.renderConfidence, offset.confidence) * link.confidenceMultiplier
    let inferredLogicConfidence: Float = {
      if pushupFloorModeActive && isPushupDistalJoint(link.child) {
        return min(0.17, max(0.12, inferredConfidence * 0.3))
      }
      return max(0.2, inferredConfidence * 0.42)
    }()

    joints[link.child] = TrackedJoint(
      name: link.child,
      rawPosition: estimated,
      smoothedPosition: estimated,
      velocity: .zero,
      rawConfidence: 0,
      renderConfidence: max(config.tracker.inferenceConfidenceFloor, inferredConfidence),
      logicConfidence: inferredLogicConfidence,
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

  private func isPushupDistalJoint(_ name: PushlyJointName) -> Bool {
    switch name {
    case .leftWrist, .rightWrist, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle, .leftFoot, .rightFoot:
      return true
    default:
      return false
    }
  }

  private func clamp01(_ point: CGPoint) -> CGPoint {
    CGPoint(x: min(1, max(0, point.x)), y: min(1, max(0, point.y)))
  }

  private func clampExtrapolation(
    point: CGPoint,
    around anchor: CGPoint,
    maxDistance: CGFloat
  ) -> CGPoint {
    let dx = point.x - anchor.x
    let dy = point.y - anchor.y
    let distance = sqrt(dx * dx + dy * dy)
    guard distance > maxDistance, distance > 0.0001 else {
      return clamp01(point)
    }
    let scale = maxDistance / distance
    return clamp01(
      CGPoint(
        x: anchor.x + dx * scale,
        y: anchor.y + dy * scale
      )
    )
  }

  private func relockBlendedMeasurementPoint(
    measurementPoint: CGPoint,
    previous: JointTrackState?
  ) -> CGPoint {
    guard let previous, previous.sourceType == .predicted else {
      return measurementPoint
    }
    let alpha = min(1, max(0, config.tracker.missingJointRelockMeasurementAlpha))
    return clamp01(
      CGPoint(
        x: previous.smoothedPosition.x + (measurementPoint.x - previous.smoothedPosition.x) * alpha,
        y: previous.smoothedPosition.y + (measurementPoint.y - previous.smoothedPosition.y) * alpha
      )
    )
  }

  private func applySideIdentityLock(
    to measured: [PushlyJointName: PoseJointMeasurement],
    now: TimeInterval
  ) -> [PushlyJointName: PoseJointMeasurement] {
    let wasSwapped = sideIdentityLockedAsSwapped
    guard !measured.isEmpty else {
      sideSwapEvidenceStreak = max(0, sideSwapEvidenceStreak - 1)
      sideKeepEvidenceStreak = max(0, sideKeepEvidenceStreak - 1)
      swapAppliedThisFrame = false
      return measured
    }

    if isSideSwapBlocked(now: now) {
      sideSwapEvidenceStreak = max(0, sideSwapEvidenceStreak - 1)
      sideKeepEvidenceStreak = max(0, sideKeepEvidenceStreak - 1)
      swapAppliedThisFrame = false
      return sideIdentityLockedAsSwapped ? swapBilateralMeasurements(in: measured) : measured
    }

    let evidence = sideEvidenceDirection(measured: measured, now: now)
    switch evidence.direction {
    case .swap:
      sideSwapEvidenceStreak += 1
      sideKeepEvidenceStreak = max(0, sideKeepEvidenceStreak - 1)
    case .keep:
      sideKeepEvidenceStreak += 1
      sideSwapEvidenceStreak = max(0, sideSwapEvidenceStreak - 1)
    case .neutral:
      sideSwapEvidenceStreak = max(0, sideSwapEvidenceStreak - 1)
      sideKeepEvidenceStreak = max(0, sideKeepEvidenceStreak - 1)
    }

    if sideIdentityLockedAsSwapped {
      if sideKeepEvidenceStreak >= max(3, config.tracker.sideSwapConsistencyFrames)
        && evidence.torsoKeepSupport >= config.tracker.sideSwapTorsoSupportMinScore {
        sideIdentityLockedAsSwapped = false
        sideSwapEvidenceStreak = 0
      }
    } else if sideSwapEvidenceStreak >= max(3, config.tracker.sideSwapConsistencyFrames)
      && evidence.torsoSwapSupport >= config.tracker.sideSwapTorsoSupportMinScore {
      sideIdentityLockedAsSwapped = true
      sideKeepEvidenceStreak = 0
    }

    swapAppliedThisFrame = sideIdentityLockedAsSwapped != wasSwapped
    return sideIdentityLockedAsSwapped ? swapBilateralMeasurements(in: measured) : measured
  }

  private func sideEvidenceDirection(
    measured: [PushlyJointName: PoseJointMeasurement],
    now: TimeInterval
  ) -> SideEvidenceResult {
    var keepWeight = 0.0
    var swapWeight = 0.0
    var torsoKeepSupport = 0.0
    var torsoSwapSupport = 0.0
    var torsoSupportTotal = 0.0

    for pair in sideEvidencePairs {
      guard let leftMeasurement = measured[pair.left],
            let rightMeasurement = measured[pair.right],
            leftMeasurement.inFrame,
            rightMeasurement.inFrame,
            leftMeasurement.confidence >= sideEvidenceConfidenceMin,
            rightMeasurement.confidence >= sideEvidenceConfidenceMin,
            let leftHistory = stateByJoint[pair.left],
            let rightHistory = stateByJoint[pair.right],
            now - leftHistory.lastUpdateTime <= sideEvidenceHistoryMaxAge,
            now - rightHistory.lastUpdateTime <= sideEvidenceHistoryMaxAge else {
        continue
      }

      let keepCost = distance(leftMeasurement.point, leftHistory.smoothedPosition) + distance(rightMeasurement.point, rightHistory.smoothedPosition)
      let swapCost = distance(leftMeasurement.point, rightHistory.smoothedPosition) + distance(rightMeasurement.point, leftHistory.smoothedPosition)

      let confidenceWeight = Double(min(
        min(leftMeasurement.confidence, rightMeasurement.confidence),
        min(leftHistory.renderConfidence, rightHistory.renderConfidence)
      ))
      let weight = pair.weight * max(0.2, confidenceWeight)

      if swapCost + sideCostMargin < keepCost {
        swapWeight += weight
      } else if keepCost + sideCostMargin < swapCost {
        keepWeight += weight
      }

      if let leftLateral = torsoLateralPosition(of: leftMeasurement.point),
         let rightLateral = torsoLateralPosition(of: rightMeasurement.point) {
        let torsoWeight = pair.weight * config.tracker.torsoSideEvidenceWeight
        torsoSupportTotal += torsoWeight
        if leftLateral + config.tracker.torsoSideLateralMargin < rightLateral {
          keepWeight += torsoWeight
          torsoKeepSupport += torsoWeight
        } else if rightLateral + config.tracker.torsoSideLateralMargin < leftLateral {
          swapWeight += torsoWeight
          torsoSwapSupport += torsoWeight
        }
      }
    }

    for chain in sideChainEvidence {
      guard let leftCenter = chainCenter(for: chain.left, in: measured),
            let rightCenter = chainCenter(for: chain.right, in: measured),
            let leftHistoryCenter = chainCenter(for: chain.left, in: stateByJoint, now: now),
            let rightHistoryCenter = chainCenter(for: chain.right, in: stateByJoint, now: now) else {
        continue
      }

      let keepCost = distance(leftCenter, leftHistoryCenter) + distance(rightCenter, rightHistoryCenter)
      let swapCost = distance(leftCenter, rightHistoryCenter) + distance(rightCenter, leftHistoryCenter)
      let chainWeight = chain.weight * config.tracker.sideChainEvidenceWeight

      if swapCost + sideCostMargin < keepCost {
        swapWeight += chainWeight
      } else if keepCost + sideCostMargin < swapCost {
        keepWeight += chainWeight
      }

      if let leftLateral = torsoLateralPosition(of: leftCenter),
         let rightLateral = torsoLateralPosition(of: rightCenter) {
        let torsoWeight = chain.weight * config.tracker.torsoSideEvidenceWeight
        torsoSupportTotal += torsoWeight
        if leftLateral + config.tracker.torsoSideLateralMargin < rightLateral {
          keepWeight += torsoWeight
          torsoKeepSupport += torsoWeight
        } else if rightLateral + config.tracker.torsoSideLateralMargin < leftLateral {
          swapWeight += torsoWeight
          torsoSwapSupport += torsoWeight
        }
      }
    }

    let direction: SideEvidenceDirection
    if swapWeight >= sideEvidenceMinWeight, swapWeight > keepWeight * 1.12 {
      direction = .swap
    } else if keepWeight >= sideEvidenceMinWeight, keepWeight > swapWeight * 1.12 {
      direction = .keep
    } else {
      direction = .neutral
    }

    let normalizedSwap = torsoSupportTotal > 0 ? torsoSwapSupport / torsoSupportTotal : 0.5
    let normalizedKeep = torsoSupportTotal > 0 ? torsoKeepSupport / torsoSupportTotal : 0.5
    return SideEvidenceResult(
      direction: direction,
      torsoSwapSupport: normalizedSwap,
      torsoKeepSupport: normalizedKeep
    )
  }

  private func updateSideSwapBlockers(
    measured: [PushlyJointName: PoseJointMeasurement],
    now: TimeInterval,
    tooCloseFallbackActive: Bool,
    reacquireActive: Bool
  ) {
    if tooCloseFallbackActive {
      sideSwapBlockedUntil = max(sideSwapBlockedUntil, now + config.tracker.sideSwapTooCloseBlockSeconds)
    }
    if reacquireActive {
      sideSwapBlockedUntil = max(sideSwapBlockedUntil, now + config.tracker.sideSwapReacquireBlockSeconds)
    }

    let measuredCount = measured.values.reduce(0) { partial, joint in
      if joint.sourceType == .missing {
        return partial
      }
      if joint.inFrame || joint.confidence >= sideEvidenceConfidenceMin {
        return partial + 1
      }
      return partial
    }
    if measuredCount < config.tracker.sideSwapOcclusionMinMeasuredJoints {
      sideSwapBlockedUntil = max(sideSwapBlockedUntil, now + config.tracker.sideSwapOcclusionBlockSeconds)
    }
  }

  private func isSideSwapBlocked(now: TimeInterval) -> Bool {
    now <= sideSwapBlockedUntil
  }

  private func chainCenter(
    for chain: [PushlyJointName],
    in measured: [PushlyJointName: PoseJointMeasurement]
  ) -> CGPoint? {
    var points: [CGPoint] = []
    for name in chain {
      guard let m = measured[name],
            m.inFrame,
            m.confidence >= sideEvidenceConfidenceMin else {
        continue
      }
      points.append(m.point)
    }
    guard !points.isEmpty else { return nil }
    let sx = points.reduce(CGFloat(0)) { $0 + $1.x }
    let sy = points.reduce(CGFloat(0)) { $0 + $1.y }
    return CGPoint(x: sx / CGFloat(points.count), y: sy / CGFloat(points.count))
  }

  private func chainCenter(
    for chain: [PushlyJointName],
    in state: [PushlyJointName: JointTrackState],
    now: TimeInterval
  ) -> CGPoint? {
    var points: [CGPoint] = []
    for name in chain {
      guard let s = state[name],
            now - s.lastUpdateTime <= sideEvidenceHistoryMaxAge,
            s.renderConfidence >= sideEvidenceConfidenceMin else {
        continue
      }
      points.append(s.smoothedPosition)
    }
    guard !points.isEmpty else { return nil }
    let sx = points.reduce(CGFloat(0)) { $0 + $1.x }
    let sy = points.reduce(CGFloat(0)) { $0 + $1.y }
    return CGPoint(x: sx / CGFloat(points.count), y: sy / CGFloat(points.count))
  }

  private func swapBilateralMeasurements(
    in measured: [PushlyJointName: PoseJointMeasurement]
  ) -> [PushlyJointName: PoseJointMeasurement] {
    var swapped = measured
    for (left, right) in sideSwapPairs {
      guard let leftMeasurement = measured[left], let rightMeasurement = measured[right] else {
        continue
      }
      swapped[left] = renamed(rightMeasurement, to: left)
      swapped[right] = renamed(leftMeasurement, to: right)
    }
    return swapped
  }

  private func renamed(_ measurement: PoseJointMeasurement, to name: PushlyJointName) -> PoseJointMeasurement {
    PoseJointMeasurement(
      name: name,
      point: measurement.point,
      worldPoint: measurement.worldPoint,
      confidence: measurement.confidence,
      visibility: measurement.visibility,
      presence: measurement.presence,
      sourceType: measurement.sourceType,
      inFrame: measurement.inFrame,
      backend: measurement.backend,
      measuredAt: measurement.measuredAt
    )
  }

  private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
  }

  private func midpoint(_ a: CGPoint?, _ b: CGPoint?) -> CGPoint? {
    switch (a, b) {
    case let (.some(pa), .some(pb)):
      return CGPoint(x: (pa.x + pb.x) * 0.5, y: (pa.y + pb.y) * 0.5)
    case let (.some(pa), .none):
      return pa
    case let (.none, .some(pb)):
      return pb
    default:
      return nil
    }
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
    let magnitude = hypot(vector.dx, vector.dy)
    guard magnitude > 0.0001 else { return CGVector(dx: 0, dy: -1) }
    return CGVector(dx: vector.dx / magnitude, dy: vector.dy / magnitude)
  }

  private func dot(_ a: CGVector, _ b: CGVector) -> CGFloat {
    a.dx * b.dx + a.dy * b.dy
  }

  private func torsoLateralPosition(of point: CGPoint) -> CGFloat? {
    guard let torsoFrame else { return nil }
    let delta = CGVector(dx: point.x - torsoFrame.shoulderMid.x, dy: point.y - torsoFrame.shoulderMid.y)
    return dot(delta, torsoFrame.shoulderAxis)
  }
}
#endif
