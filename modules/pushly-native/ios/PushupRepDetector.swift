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
  private var repRearmPending = false
  private var topRecoveryFrames = 0
  private var ascendingSignalGapFrames = 0
  private var topRecoveryGateGapFrames = 0
  private var smoothedTorsoStability: Double = 0.4
  private var torsoUnstableFrames = 0
  private var previousStateForDebugEvent: PushupState = .idle

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
    repRearmPending = false
    topRecoveryFrames = 0
    ascendingSignalGapFrames = 0
    topRecoveryGateGapFrames = 0
    smoothedTorsoStability = 0.4
    torsoUnstableFrames = 0
    previousStateForDebugEvent = .idle
  }

  func update(
    joints: [PushlyJointName: TrackedJoint],
    quality: TrackingQuality,
    repTarget: Int
  ) -> RepDetectionOutput {
    _ = repTarget
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
      repRearmPending = false
      topRecoveryFrames = 0
      ascendingSignalGapFrames = 0
      topRecoveryGateGapFrames = 0
      smoothedTorsoStability = 0.4
      torsoUnstableFrames = 0
      let resolvedBlockedReasons = ["body_not_found"]
      return RepDetectionOutput(
        state: state,
        repCount: repCount,
        formEvidenceScore: signal.formEvidenceScore,
        blockedReasons: resolvedBlockedReasons,
        repDebug: PushupRepDebug(
          smoothedElbowAngle: Double(smoothedElbowAngle),
          repMinElbowAngle: Double(repMinElbowAngle),
          smoothedTorsoY: Double(smoothedTorsoY),
          smoothedShoulderY: Double(smoothedShoulderY),
          topReferenceTorsoY: Double(hasFloorBaselineTorsoY ? floorBaselineTorsoY : repStartTorsoY),
          topReferenceShoulderY: Double(repStartShoulderY),
          shoulderVelocity: 0,
          torsoVelocity: 0,
          descendingSignal: false,
          ascendingSignal: false,
          shoulderDownTravel: 0,
          shoulderRecoveryToTop: 0,
          torsoDownTravel: 0,
          torsoRecoveryToTop: 0,
          descendingFrames: descendingFrames,
          bottomFrames: bottomFrames,
          ascendingFrames: ascendingFrames,
          bottomReached: bottomReached,
          dominantEvidence: dominantEvidence,
          measuredEvidence: signal.measuredEvidence,
          structuralEvidence: signal.structuralEvidence,
          upperBodyEvidence: signal.upperBodyEvidence,
          blockedReasons: resolvedBlockedReasons,
          canProgress: false,
          logicBlockedFrames: logicBlockedFrames,
          startupReady: false,
          startupTopEvidence: plankFrames,
          startupDescendBridgeUsed: false,
          startBlockedReason: repCount == 0 ? "body_not_found" : nil,
          repRearmPending: repRearmPending,
          topRecoveryFrames: topRecoveryFrames,
          cycleCoreReady: false,
          strictCycleReady: false,
          floorFallbackCycleReady: false,
          motionTravelGate: false,
          topRecoveryGate: false,
          torsoSupportReady: false,
          shoulderSupportReady: false,
          countGatePassed: false,
          countGateBlocked: true,
          countGateBlockReason: "body_not_found",
          stateTransitionEvent: consumeStateTransitionEvent(currentState: state)
        )
      )
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
    let torsoVelocity = smoothedTorsoY - previousTorsoY
    // Coordinates are normalized in a Cartesian-like frame where larger Y is visually higher.
    // So a visible downward push-up descent moves shoulders/torso toward smaller Y values.
    let torsoTopReference = hasFloorBaselineTorsoY ? floorBaselineTorsoY : repStartTorsoY
    let shoulderTopReference = repStartShoulderY
    var descendingSignal = false
    var ascendingSignal = false
    var torsoDownTravel = max(0, torsoTopReference - repMaxTorsoY)
    var torsoRecoveryToTop = max(0, smoothedTorsoY - repMaxTorsoY)
    var shoulderDownTravel = max(0, shoulderTopReference - repMaxShoulderY)
    var shoulderRecoveryToTop = max(0, smoothedShoulderY - repMaxShoulderY)
    var cycleCoreReady = false
    var strictCycleReady = false
    var floorFallbackCycleReady = false
    var motionTravelGate = false
    var topRecoveryGate = false
    var torsoSupportReady = false
    var shoulderSupportReady = false
    var countGatePassed = false
    var countGateBlocked = false
    var countGateBlockReason: String?

    let activeRepCycle =
      bottomReached ||
      descendingFrames > 0 ||
      bottomFrames > 0 ||
      ascendingFrames > 0 ||
      state == .descending ||
      state == .ascending
    var blockedReasons: [String] = []
    // Keep three distinct quality levels:
    // 1) renderable enough to maintain an active cycle,
    // 2) progression-quality for cycle continuity,
    // 3) strict count-quality (kept unchanged below in strictCycleReady/floorFallbackCycleReady).
    let isLowLightQualityDip = quality.reasonCodes.contains("low_light") || quality.reasonCodes.contains("very_low_light")
    let isTrackingQualityDip =
      quality.trackingState != .tracking
      || quality.bodyVisibilityState == .assisted
      || quality.bodyVisibilityState == .partial
    let isRenderableForProgression =
      quality.renderQuality >= config.quality.renderMin
      && quality.visibleJointCount >= config.pipeline.logicMinJointCount
    let progressionLogicQualityGate: Double = {
      guard activeRepCycle && isRenderableForProgression else { return config.rep.minLogicQualityToProgress }
      var gate = config.rep.minLogicQualityToProgress - 0.02
      if isLowLightQualityDip { gate -= 0.02 }
      if isTrackingQualityDip { gate -= 0.01 }
      return max(0.2, gate)
    }()
    if quality.logicQuality < progressionLogicQualityGate {
      blockedReasons.append("logic_quality_low")
    }
    if dominantEvidence < minMeasuredEvidence {
      blockedReasons.append("measured_evidence_low")
    }
    let torsoStabilityAlpha = floorState ? 0.24 : 0.2
    smoothedTorsoStability = smoothedTorsoStability * (1 - torsoStabilityAlpha) + signal.torsoStability * torsoStabilityAlpha
    let torsoStabilityForGate = max(signal.torsoStability, smoothedTorsoStability - 0.02)
    let torsoCycleGateRelief = (activeRepCycle && isRenderableForProgression && isLowLightQualityDip) ? 0.005 : 0
    let torsoStabilityGate = (floorState && activeRepCycle)
      ? max(0.2, minTorsoStability - 0.015 - torsoCycleGateRelief)
      : minTorsoStability
    let torsoStabilityGraceFrames = activeRepCycle
      ? max(2, config.rep.ascendingConfirmFrames + 1) + (((isLowLightQualityDip || isTrackingQualityDip) && isRenderableForProgression) ? 1 : 0)
      : 1
    if torsoStabilityForGate < torsoStabilityGate {
      torsoUnstableFrames += 1
    } else {
      torsoUnstableFrames = 0
    }
    let allowFloorCycleTorsoStabilityGrace =
      floorState &&
      activeRepCycle &&
      isRenderableForProgression &&
      quality.logicQuality >= progressionLogicQualityGate
    if torsoUnstableFrames > torsoStabilityGraceFrames && !allowFloorCycleTorsoStabilityGrace {
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
    if floorState && blockedReasons.contains("shoulder_hip_line_weak") && signal.shoulderHipLineQuality >= 0.32 {
      blockedReasons.removeAll { $0 == "shoulder_hip_line_weak" }
    }
    let logicReady = blockedReasons.isEmpty
    if logicReady {
      logicBlockedFrames = 0
    } else {
      logicBlockedFrames += 1
    }
    let progressionGraceBoostFrames = (activeRepCycle && isRenderableForProgression && (isLowLightQualityDip || isTrackingQualityDip)) ? 2 : 0
    let progressionLogicGraceFrames = config.rep.logicGateGraceFrames + progressionGraceBoostFrames
    let canProgress = logicReady || logicBlockedFrames <= progressionLogicGraceFrames
    let ascendingSignalGraceFrames = max(1, config.rep.ascendingConfirmFrames - 1)
    let topRecoveryGateGraceFrames = max(1, config.rep.repRearmConfirmFrames)
    var startupDescendBridgeUsed = false

    if !canProgress {
      if quality.renderQuality >= config.quality.renderMin {
        state = .trackingAssisted
      } else {
        state = .lostTracking
      }

      // Avoid destroying an already valid cycle on short logic dips.
      // Keep only a tiny hold window, then decay aggressively to prevent stale/noise-driven counts.
      let blockedOverrun = max(0, logicBlockedFrames - progressionLogicGraceFrames)
      let shortHoldWindow = max(1, config.rep.ascendingConfirmFrames)
      let severeDecayStep = state == .lostTracking ? 3 : 2
      let mildDecayStep = 1
      let decayStep = blockedOverrun <= shortHoldWindow ? mildDecayStep : severeDecayStep

      descendingFrames = max(0, descendingFrames - decayStep)
      bottomFrames = max(0, bottomFrames - decayStep)
      if bottomReached && ascendingFrames > 0 && blockedOverrun <= shortHoldWindow {
        ascendingSignalGapFrames = min(ascendingSignalGapFrames + 1, ascendingSignalGraceFrames)
      } else {
        ascendingFrames = max(0, ascendingFrames - decayStep)
        if ascendingFrames == 0 {
          ascendingSignalGapFrames = 0
        }
      }

      if repRearmPending {
        topRecoveryGateGapFrames += 1
        if topRecoveryGateGapFrames > topRecoveryGateGraceFrames {
          topRecoveryFrames = max(0, topRecoveryFrames - 1)
        }
      } else {
        topRecoveryFrames = 0
        topRecoveryGateGapFrames = 0
      }

      if bottomReached {
        bottomOcclusionFrames += 1
        let noProgressFramesLeft = descendingFrames == 0 && bottomFrames == 0 && ascendingFrames == 0
        let occlusionExpired = bottomOcclusionFrames > config.rep.bottomOcclusionGraceFrames
        if noProgressFramesLeft || occlusionExpired {
          bottomReached = false
          bottomOcclusionFrames = 0
        }
      } else {
        bottomOcclusionFrames = 0
      }

      return RepDetectionOutput(
        state: state,
        repCount: repCount,
        formEvidenceScore: signal.formEvidenceScore,
        blockedReasons: blockedReasons,
        repDebug: makeRepDebug(
          blockedReasons: blockedReasons,
          dominantEvidence: dominantEvidence,
          measuredEvidence: signal.measuredEvidence,
          structuralEvidence: signal.structuralEvidence,
          upperBodyEvidence: signal.upperBodyEvidence,
          shoulderVelocity: shoulderVelocity,
          torsoVelocity: torsoVelocity,
          topReferenceTorsoY: torsoTopReference,
          topReferenceShoulderY: shoulderTopReference,
          descendingSignal: descendingSignal,
          ascendingSignal: ascendingSignal,
          shoulderDownTravel: shoulderDownTravel,
          shoulderRecoveryToTop: shoulderRecoveryToTop,
          torsoDownTravel: torsoDownTravel,
          torsoRecoveryToTop: torsoRecoveryToTop,
          canProgress: canProgress,
          logicBlockedFrames: logicBlockedFrames,
          startupReady: isStartupReady(),
          startupTopEvidence: plankFrames,
          startupDescendBridgeUsed: startupDescendBridgeUsed,
          startBlockedReason: startupBlockedReason(),
          repRearmPending: repRearmPending,
          topRecoveryFrames: topRecoveryFrames,
          cycleCoreReady: cycleCoreReady,
          strictCycleReady: strictCycleReady,
          floorFallbackCycleReady: floorFallbackCycleReady,
          motionTravelGate: motionTravelGate,
          topRecoveryGate: topRecoveryGate,
          torsoSupportReady: torsoSupportReady,
          shoulderSupportReady: shoulderSupportReady,
          countGatePassed: false,
          countGateBlocked: true,
          countGateBlockReason: "logic_gate_blocked"
        )
      )
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
      if repRearmPending {
        topRecoveryFrames += 1
        if topRecoveryFrames >= config.rep.repRearmConfirmFrames {
          repRearmPending = false
          topRecoveryFrames = 0
        }
      } else {
        topRecoveryFrames = 0
      }
      if plankFrames >= config.rep.plankLockFrames {
        state = .plankLocked
      } else {
        state = .bodyFound
      }
    } else if state == .plankLocked
      || state == .descending
      || state == .ascending
      || bottomReached
      || (repCount == 0 && state == .bodyFound && plankFrames >= config.rep.startupDescendBridgeMinTopFrames)
    {
      if repCount == 0 && state == .bodyFound && plankFrames >= config.rep.startupDescendBridgeMinTopFrames {
        startupDescendBridgeUsed = true
      }
      let descendingByShoulder = shoulderVelocity < -config.rep.shoulderVelocityMinForDescent
      let ascendingByShoulder = shoulderVelocity > config.rep.shoulderVelocityMinForAscent
      let descendingByTorso = torsoVelocity < -config.rep.torsoVelocityMinForDescent
      let ascendingByTorso = torsoVelocity > config.rep.torsoVelocityMinForAscent
      // Primary progression depends on torso/shoulder motion for frontal stability.
      descendingSignal = descendingByTorso || descendingByShoulder
      ascendingSignal = ascendingByTorso || ascendingByShoulder
      let elbowAtBottom = signal.hasElbowMeasurement && smoothedElbowAngle < config.rep.bottomAngleMax
      let allowBottomOcclusion = bottomReached && bottomOcclusionFrames <= config.rep.bottomOcclusionGraceFrames

      if descendingSignal {
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
        // Historical names kept for compatibility: repMax* now track the deepest point,
        // which is the minimum Y reached during descent in this coordinate space.
        repMaxShoulderY = min(repMaxShoulderY, smoothedShoulderY)
        repMaxTorsoY = min(repMaxTorsoY, smoothedTorsoY)
        if descendingFrames >= config.rep.descentConfirmFrames {
          state = .descending
        }
      } else {
        descendingFrames = max(0, descendingFrames - 1)
      }

      torsoDownTravel = max(0, torsoTopReference - repMaxTorsoY)
      torsoRecoveryToTop = max(0, smoothedTorsoY - repMaxTorsoY)
      shoulderDownTravel = max(0, shoulderTopReference - repMaxShoulderY)
      shoulderRecoveryToTop = max(0, smoothedShoulderY - repMaxShoulderY)
      let bottomTravelReached =
        (
          torsoDownTravel >= config.rep.minTorsoDownTravelForBottom
            || shoulderDownTravel >= config.rep.minShoulderDownTravelForBottom
        )
      let descentConfirmed = state == .descending || descendingFrames >= config.rep.descentConfirmFrames
      let motionBottomCandidate = descentConfirmed && bottomTravelReached

      if elbowAtBottom || allowBottomOcclusion || motionBottomCandidate {
        if descendingSignal || state == .descending || bottomReached {
          bottomFrames += 1
        }
        if signal.hasElbowMeasurement {
          repMinElbowAngle = min(repMinElbowAngle, smoothedElbowAngle)
        }
        repMaxShoulderY = min(repMaxShoulderY, smoothedShoulderY)
        repMaxTorsoY = min(repMaxTorsoY, smoothedTorsoY)
        if bottomFrames >= config.rep.bottomConfirmFrames && bottomTravelReached {
          state = .bottomReached
          bottomReached = true
        }
      } else if !bottomReached {
        bottomFrames = max(0, bottomFrames - 1)
      }

      if bottomReached && ascendingSignal {
        ascendingSignalGapFrames = 0
        ascendingFrames += 1
        if ascendingFrames >= config.rep.ascendingConfirmFrames {
          state = .ascending
        }
      } else if bottomReached {
        ascendingSignalGapFrames += 1
        if ascendingSignalGapFrames > ascendingSignalGraceFrames {
          ascendingFrames = max(0, ascendingFrames - 1)
        }
      } else {
        ascendingSignalGapFrames = 0
      }

      let repTravel = max(0, repStartElbowAngle - repMinElbowAngle)
      let elbowComplete = signal.hasElbowMeasurement && smoothedElbowAngle > config.rep.repCompleteAngleMin
      let elbowSecondaryReady =
        !signal.hasElbowMeasurement ||
        elbowComplete ||
        repTravel >= config.rep.minRepAngleTravel * 0.55 ||
        repMinElbowAngle < config.rep.bottomAngleMax + 8
      cycleCoreReady =
        bottomReached &&
        ascendingFrames >= config.rep.ascendingConfirmFrames &&
        (
          torsoDownTravel >= config.rep.minTorsoDownTravelForBottom
            || shoulderDownTravel >= config.rep.minShoulderDownTravelForBottom
        )
      let trackingQualityGate = floorState ? config.rep.floorMinTrackingQualityToCount : config.rep.minTrackingQualityToCount
      let evidenceGate = floorState ? config.rep.floorMinMeasuredEvidence : config.rep.minMeasuredEvidence
      let torsoCycleReady =
        torsoDownTravel >= config.rep.minTorsoCycleTravel &&
        torsoRecoveryToTop >= config.rep.minTorsoRecoveryTravel
      let shoulderCycleReady =
        shoulderDownTravel >= config.rep.minShoulderCycleTravel &&
        shoulderRecoveryToTop >= config.rep.minShoulderRecoveryTravel
      torsoSupportReady =
        shoulderDownTravel >= config.rep.minShoulderCycleTravel * 0.6 &&
        shoulderRecoveryToTop >= config.rep.minShoulderRecoveryTravel * 0.6
      shoulderSupportReady =
        torsoDownTravel >= config.rep.minTorsoCycleTravel * 0.6 &&
        torsoRecoveryToTop >= config.rep.minTorsoRecoveryTravel * 0.6
      motionTravelGate =
        (torsoCycleReady && torsoSupportReady) ||
        (shoulderCycleReady && shoulderSupportReady)
      topRecoveryGate = smoothedTorsoY >= torsoTopReference - config.rep.maxTorsoTopRecoveryOffset
      let qualityGate = quality.logicQuality >= config.rep.minLogicQualityToCount
      let trackingGate = quality.trackingQuality >= trackingQualityGate
      let evidenceReady = dominantEvidence >= evidenceGate && signal.measuredEvidence >= evidenceGate * 0.85
      strictCycleReady =
        cycleCoreReady &&
        motionTravelGate &&
        topRecoveryGate &&
        qualityGate &&
        trackingGate &&
        evidenceReady &&
        signal.torsoStability >= minTorsoStability &&
        signal.shoulderHipLineQuality >= minShoulderHipLineQuality
      floorFallbackCycleReady =
        floorState &&
        cycleCoreReady &&
        descendingFrames >= config.rep.descentConfirmFrames &&
        quality.logicQuality >= config.rep.minLogicQualityToProgress &&
        quality.trackingQuality >= trackingQualityGate * 0.9 &&
        dominantEvidence >= config.rep.floorMinMeasuredEvidence * 0.85 &&
        signal.measuredEvidence >= config.rep.floorMinMeasuredEvidence * 0.8 &&
        signal.torsoStability >= config.rep.floorMinTorsoStability * 0.9 &&
        signal.shoulderHipLineQuality >= config.rep.floorMinShoulderHipLineQuality * 0.85 &&
        (
          torsoCycleReady ||
          shoulderCycleReady ||
          (torsoSupportReady && shoulderSupportReady)
        )

      if repRearmPending {
        if topRecoveryGate && !descendingSignal {
          topRecoveryGateGapFrames = 0
          topRecoveryFrames += 1
          if topRecoveryFrames >= config.rep.repRearmConfirmFrames {
            repRearmPending = false
            topRecoveryFrames = 0
            topRecoveryGateGapFrames = 0
          }
        } else {
          topRecoveryGateGapFrames += 1
          if topRecoveryGateGapFrames > topRecoveryGateGraceFrames {
            topRecoveryFrames = max(0, topRecoveryFrames - 1)
          }
        }
      } else {
        topRecoveryFrames = 0
        topRecoveryGateGapFrames = 0
      }

      countGatePassed = !repRearmPending && (strictCycleReady || floorFallbackCycleReady)
      if countGatePassed {
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
        repRearmPending = true
        topRecoveryFrames = 0
        ascendingSignalGapFrames = 0
        topRecoveryGateGapFrames = 0
        if floorState {
          if hasFloorBaselineTorsoY {
            floorBaselineTorsoY = floorBaselineTorsoY * 0.8 + smoothedTorsoY * 0.2
          } else {
            floorBaselineTorsoY = smoothedTorsoY
            hasFloorBaselineTorsoY = true
          }
        }
      } else if strictCycleReady && !elbowSecondaryReady {
        blockedReasons.append("elbow_secondary_unconfirmed")
      }

      if !countGatePassed {
        let gateReason = makeCountGateBlockReason(
          repRearmPending: repRearmPending,
          bottomReached: bottomReached,
          ascendingFrames: ascendingFrames,
          torsoDownTravel: torsoDownTravel,
          torsoRecoveryToTop: torsoRecoveryToTop,
          shoulderDownTravel: shoulderDownTravel,
          shoulderRecoveryToTop: shoulderRecoveryToTop,
          logicQuality: quality.logicQuality,
          trackingQuality: quality.trackingQuality,
          dominantEvidence: dominantEvidence,
          measuredEvidence: signal.measuredEvidence,
          evidenceGate: evidenceGate,
          trackingQualityGate: trackingQualityGate,
          cycleCoreReady: cycleCoreReady,
          strictCycleReady: strictCycleReady,
          floorFallbackCycleReady: floorFallbackCycleReady,
          motionTravelGate: motionTravelGate,
          topRecoveryGate: topRecoveryGate
        )
        if gateReason != "gate_not_applicable" {
          countGateBlocked = true
          countGateBlockReason = gateReason
          if !blockedReasons.contains(gateReason) {
            blockedReasons.append(gateReason)
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
      if repRearmPending {
        topRecoveryGateGapFrames += 1
        if topRecoveryGateGapFrames > topRecoveryGateGraceFrames {
          topRecoveryFrames = max(0, topRecoveryFrames - 1)
        }
      } else {
        topRecoveryFrames = 0
        topRecoveryGateGapFrames = 0
      }
      ascendingSignalGapFrames = 0
      state = .bodyFound
    }

    return RepDetectionOutput(
      state: state,
      repCount: repCount,
      formEvidenceScore: signal.formEvidenceScore,
      blockedReasons: blockedReasons,
      repDebug: makeRepDebug(
        blockedReasons: blockedReasons,
        dominantEvidence: dominantEvidence,
        measuredEvidence: signal.measuredEvidence,
        structuralEvidence: signal.structuralEvidence,
        upperBodyEvidence: signal.upperBodyEvidence,
        shoulderVelocity: shoulderVelocity,
        torsoVelocity: torsoVelocity,
        topReferenceTorsoY: torsoTopReference,
        topReferenceShoulderY: shoulderTopReference,
        descendingSignal: descendingSignal,
        ascendingSignal: ascendingSignal,
        shoulderDownTravel: shoulderDownTravel,
        shoulderRecoveryToTop: shoulderRecoveryToTop,
        torsoDownTravel: torsoDownTravel,
        torsoRecoveryToTop: torsoRecoveryToTop,
        canProgress: canProgress,
        logicBlockedFrames: logicBlockedFrames,
        startupReady: isStartupReady(),
        startupTopEvidence: plankFrames,
        startupDescendBridgeUsed: startupDescendBridgeUsed,
        startBlockedReason: startupBlockedReason(),
        repRearmPending: repRearmPending,
        topRecoveryFrames: topRecoveryFrames,
        cycleCoreReady: cycleCoreReady,
        strictCycleReady: strictCycleReady,
        floorFallbackCycleReady: floorFallbackCycleReady,
        motionTravelGate: motionTravelGate,
        topRecoveryGate: topRecoveryGate,
        torsoSupportReady: torsoSupportReady,
        shoulderSupportReady: shoulderSupportReady,
        countGatePassed: countGatePassed,
        countGateBlocked: countGateBlocked,
        countGateBlockReason: countGateBlockReason
      )
    )
  }

  private func makeRepDebug(
    blockedReasons: [String],
    dominantEvidence: Double,
    measuredEvidence: Double,
    structuralEvidence: Double,
    upperBodyEvidence: Double,
    shoulderVelocity: CGFloat,
    torsoVelocity: CGFloat,
    topReferenceTorsoY: CGFloat,
    topReferenceShoulderY: CGFloat,
    descendingSignal: Bool,
    ascendingSignal: Bool,
    shoulderDownTravel: CGFloat,
    shoulderRecoveryToTop: CGFloat,
    torsoDownTravel: CGFloat,
    torsoRecoveryToTop: CGFloat,
    canProgress: Bool,
    logicBlockedFrames: Int,
    startupReady: Bool,
    startupTopEvidence: Int,
    startupDescendBridgeUsed: Bool,
    startBlockedReason: String?,
    repRearmPending: Bool,
    topRecoveryFrames: Int,
    cycleCoreReady: Bool,
    strictCycleReady: Bool,
    floorFallbackCycleReady: Bool,
    motionTravelGate: Bool,
    topRecoveryGate: Bool,
    torsoSupportReady: Bool,
    shoulderSupportReady: Bool,
    countGatePassed: Bool,
    countGateBlocked: Bool,
    countGateBlockReason: String?
  ) -> PushupRepDebug {
    PushupRepDebug(
      smoothedElbowAngle: Double(smoothedElbowAngle),
      repMinElbowAngle: Double(repMinElbowAngle),
      smoothedTorsoY: Double(smoothedTorsoY),
      smoothedShoulderY: Double(smoothedShoulderY),
      topReferenceTorsoY: Double(topReferenceTorsoY),
      topReferenceShoulderY: Double(topReferenceShoulderY),
      shoulderVelocity: Double(shoulderVelocity),
      torsoVelocity: Double(torsoVelocity),
      descendingSignal: descendingSignal,
      ascendingSignal: ascendingSignal,
      shoulderDownTravel: Double(shoulderDownTravel),
      shoulderRecoveryToTop: Double(shoulderRecoveryToTop),
      torsoDownTravel: Double(torsoDownTravel),
      torsoRecoveryToTop: Double(torsoRecoveryToTop),
      descendingFrames: descendingFrames,
      bottomFrames: bottomFrames,
      ascendingFrames: ascendingFrames,
      bottomReached: bottomReached,
      dominantEvidence: dominantEvidence,
      measuredEvidence: measuredEvidence,
      structuralEvidence: structuralEvidence,
      upperBodyEvidence: upperBodyEvidence,
      blockedReasons: blockedReasons,
      canProgress: canProgress,
      logicBlockedFrames: logicBlockedFrames,
      startupReady: startupReady,
      startupTopEvidence: startupTopEvidence,
      startupDescendBridgeUsed: startupDescendBridgeUsed,
      startBlockedReason: startBlockedReason,
      repRearmPending: repRearmPending,
      topRecoveryFrames: topRecoveryFrames,
      cycleCoreReady: cycleCoreReady,
      strictCycleReady: strictCycleReady,
      floorFallbackCycleReady: floorFallbackCycleReady,
      motionTravelGate: motionTravelGate,
      topRecoveryGate: topRecoveryGate,
      torsoSupportReady: torsoSupportReady,
      shoulderSupportReady: shoulderSupportReady,
      countGatePassed: countGatePassed,
      countGateBlocked: countGateBlocked,
      countGateBlockReason: countGateBlockReason,
      stateTransitionEvent: consumeStateTransitionEvent(currentState: state)
    )
  }

  private func consumeStateTransitionEvent(currentState: PushupState) -> String? {
    let previousState = previousStateForDebugEvent
    previousStateForDebugEvent = currentState
    guard currentState != previousState else { return nil }

    switch currentState {
    case .bodyFound, .trackingAssisted, .bottomReached, .ascending, .repCounted:
      return currentState.rawValue
    default:
      return nil
    }
  }

  // Keep this ordering aligned with operational debugging:
  // first phase-state blockers, then cycle/travel/top-recovery, then quality/evidence.
  private func makeCountGateBlockReason(
    repRearmPending: Bool,
    bottomReached: Bool,
    ascendingFrames: Int,
    torsoDownTravel: CGFloat,
    torsoRecoveryToTop: CGFloat,
    shoulderDownTravel: CGFloat,
    shoulderRecoveryToTop: CGFloat,
    logicQuality: Double,
    trackingQuality: Double,
    dominantEvidence: Double,
    measuredEvidence: Double,
    evidenceGate: Double,
    trackingQualityGate: Double,
    cycleCoreReady: Bool,
    strictCycleReady: Bool,
    floorFallbackCycleReady: Bool,
    motionTravelGate: Bool,
    topRecoveryGate: Bool
  ) -> String {
    if repRearmPending { return "rearm_pending" }
    if !bottomReached { return "bottom_not_reached" }
    if ascendingFrames < config.rep.ascendingConfirmFrames { return "ascending_not_confirmed" }
    if !cycleCoreReady { return "cycle_core_incomplete" }
    if strictCycleReady || floorFallbackCycleReady { return "gate_not_applicable" }
    if !motionTravelGate { return "travel_cycle_incomplete" }
    if !topRecoveryGate { return "top_recovery_incomplete" }
    if torsoDownTravel < config.rep.minTorsoCycleTravel { return "torso_down_insufficient" }
    if shoulderDownTravel < config.rep.minShoulderCycleTravel { return "shoulder_down_insufficient" }
    if torsoRecoveryToTop < config.rep.minTorsoRecoveryTravel { return "torso_recovery_insufficient" }
    if shoulderRecoveryToTop < config.rep.minShoulderRecoveryTravel { return "shoulder_recovery_insufficient" }
    if logicQuality < config.rep.minLogicQualityToCount { return "logic_quality_low" }
    if trackingQuality < trackingQualityGate { return "tracking_quality_low" }
    if dominantEvidence < evidenceGate { return "dominant_evidence_low" }
    if measuredEvidence < evidenceGate * 0.85 { return "measured_evidence_low" }
    return "gate_not_applicable"
  }

  private func isStartupReady() -> Bool {
    state == .plankLocked
      || (repCount == 0 && state == .bodyFound && plankFrames >= config.rep.startupDescendBridgeMinTopFrames)
  }

  private func startupBlockedReason() -> String? {
    guard repCount == 0, !isStartupReady() else { return nil }
    return "startup_top_evidence_insufficient"
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
    let hasRenderableBody =
      joints.values.filter(\.isRenderable).count >= 4 ||
      (pushupFloorState && shoulderPair != nil && (bestRenderableArm != nil || hipPair != nil))

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

    if let nose = joints[.nose], nose.isRenderable {
      return abs(Double(nose.smoothedPosition.y - shoulderMid.y)) < config.rep.floorStateNoseShoulderDeltaMax &&
        shoulderHipDelta < config.rep.floorStateShoulderHipDeltaMax
    }

    let shoulderPairVisible = bestPair(joints[.leftShoulder], joints[.rightShoulder]) != nil
    let hipPairVisible = bestPair(joints[.leftHip], joints[.rightHip]) != nil
    let armVisible = arm(shoulder: .leftShoulder, elbow: .leftElbow, wrist: .leftWrist, joints: joints) != nil ||
      arm(shoulder: .rightShoulder, elbow: .rightElbow, wrist: .rightWrist, joints: joints) != nil
    let shoulderHipAligned =
      hipPairVisible
      ? shoulderHipDelta < config.rep.floorStateShoulderHipDeltaMax * 1.15
      : shoulderPairVisible

    return shoulderPairVisible && armVisible && shoulderHipAligned
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
