import Foundation

#if os(iOS)
enum InstructionState {
  case stable
  case warning
  case critical
}

final class InstructionEngine {
  private let framingEnterThreshold = 0.22
  private let framingExitThreshold = 0.28
  private let framingConfirmationFrames = 5
  private let noBodyEnterFrames = 10
  private let noBodyExitFrames = 6
  private let noBodyGraceWindow: TimeInterval = 0.35
  private let repeatCooldown: TimeInterval = 2.8
  private let minWarningHold: TimeInterval = 1.2
  private let pushupCloseUpperBodyThreshold = 0.52

  private var framingTightCounter = 0
  private var framingTightActive = false
  private var noBodyCounter = 0
  private var noBodyStableCounter = 0
  private var noBodyActive = false
  private var lastBodySeenAt: TimeInterval = 0
  private var lastInstruction: String?
  private var lastInstructionTimestamp: TimeInterval = 0
  private var lastState: InstructionState = .stable

  private(set) var currentInstructionState: InstructionState = .stable

  func makeInstruction(
    quality: TrackingQuality,
    repState: PushupState,
    blockedReasons: [String],
    lowLightDetected: Bool,
    requiresFullBody: Bool,
    now: TimeInterval
  ) -> String? {
    updateFramingState(quality: quality)
    updateNoBodyState(quality: quality, poseState: quality.poseTrackingState, now: now)

    let noBodyDetected = noBodyActive && quality.poseTrackingState == .lost
    let bodyUnstable = blockedReasons.contains("logic_quality_low") || quality.trackingQuality < 0.28
    let occlusion = quality.reasonCodes.contains("upper_body_missing") || quality.reasonCodes.contains("torso_weak") || quality.reasonCodes.contains("arm_weak")
    let lowerBodyMissingForRequiredFullBody = requiresFullBody && quality.poseTrackingState == .trackingUpperBody
    let lowLight = lowLightDetected && quality.logicQuality < 0.5
    let tooCloseForPushups =
      (framingTightActive && quality.upperBodyCoverage >= pushupCloseUpperBodyThreshold && quality.upperBodyRenderableCount >= 4) ||
      (quality.reasonCodes.contains("lower_body_missing") && quality.upperBodyCoverage >= 0.62)

    let candidate = chooseInstruction(
      noBodyDetected: noBodyDetected,
      bodyUnstable: bodyUnstable,
      occlusion: occlusion,
      lowerBodyMissingForRequiredFullBody: lowerBodyMissingForRequiredFullBody,
      lowLight: lowLight,
      tooCloseForPushups: tooCloseForPushups,
      quality: quality,
      repState: repState,
      blockedReasons: blockedReasons
    )

    currentInstructionState = candidate?.state ?? .stable
    guard let next = candidate?.text else {
      lastInstruction = nil
      lastInstructionTimestamp = 0
      lastState = .stable
      return nil
    }

    if lastState == .warning,
       currentInstructionState == .warning,
       lastInstruction != nil,
       now - lastInstructionTimestamp < minWarningHold {
      return nil
    }
    if next == lastInstruction,
       now - lastInstructionTimestamp < repeatCooldown {
      return nil
    }

    lastInstruction = next
    lastInstructionTimestamp = now
    lastState = currentInstructionState
    return next
  }

  private func chooseInstruction(
    noBodyDetected: Bool,
    bodyUnstable: Bool,
    occlusion: Bool,
    lowerBodyMissingForRequiredFullBody: Bool,
    lowLight: Bool,
    tooCloseForPushups: Bool,
    quality: TrackingQuality,
    repState: PushupState,
    blockedReasons: [String]
  ) -> (state: InstructionState, text: String)? {
    if noBodyDetected {
      return (.critical, "Get your upper body into frame.")
    }

    if lowerBodyMissingForRequiredFullBody {
      return (.warning, "Upper body is tracked. Step back to include your full body.")
    }

    if tooCloseForPushups {
      return (.warning, "Zu nah dran. Geh 20 bis 30 cm weiter weg für stabile Push-up-Erkennung.")
    }

    if bodyUnstable {
      return (.warning, "Hold still for a second so tracking can lock.")
    }

    if occlusion {
      if quality.upperBodyRenderableCount >= 4, quality.reasonCodes.contains("arm_weak") {
        return (.warning, "Show more of your arms.")
      }
      return (.warning, "Keep your upper body and arms visible.")
    }

    if framingTightActive {
      if quality.upperBodyRenderableCount >= 4, quality.reasonCodes.contains("arm_weak") {
        return (.warning, "Show more of your arms.")
      }
      return (.warning, "Move slightly farther back.")
    }

    if lowLight {
      return (.warning, "Licht ist etwas dunkel. Dreh dich leicht zur Lichtquelle.")
    }

    if repState == .repCounted {
      return (.stable, "Stark. Rep erkannt.")
    }
    if blockedReasons.contains("measured_evidence_low") {
      return (.warning, "Bewegung erkannt. Halt Schulter, Ellbogen und Hüfte etwas klarer im Bild.")
    }
    if quality.bodyVisibilityState == .partial {
      return (.warning, "Wir können dich sehen. Position noch leicht anpassen.")
    }
    if repState == .plankLocked {
      return (.stable, "Perfekt. Jetzt kontrolliert tief gehen.")
    }
    if repState == .descending {
      return (.stable, "Sauber. Noch etwas tiefer.")
    }
    if repState == .bottomReached {
      return (.stable, "Bottom erreicht. Drück explosiv hoch.")
    }
    if repState == .ascending {
      return (.stable, "Stark. Hochdrücken.")
    }

    return (.stable, "Halte deinen Körper lang und stabil.")
  }

  private func updateFramingState(quality: TrackingQuality) {
    if quality.visibleJointCount < 4 {
      framingTightCounter = 0
      framingTightActive = false
      return
    }

    if framingTightActive {
      if quality.smoothedSpread > framingExitThreshold {
        framingTightActive = false
        framingTightCounter = 0
      }
      return
    }

    if quality.smoothedSpread < framingEnterThreshold {
      framingTightCounter += 1
      if framingTightCounter >= framingConfirmationFrames {
        framingTightActive = true
      }
    } else {
      framingTightCounter = 0
    }
  }

  private func updateNoBodyState(quality: TrackingQuality, poseState: BodyState, now: TimeInterval) {
    if lastBodySeenAt == 0 {
      lastBodySeenAt = now
    }

    if poseState == .trackingUpperBody || poseState == .trackingFullBody || quality.upperBodyCoverage >= 0.35 || quality.visibleJointCount >= 3 {
      lastBodySeenAt = now
      noBodyCounter = 0
      noBodyStableCounter += 1
      if noBodyStableCounter >= noBodyExitFrames {
        noBodyActive = false
      }
      return
    }

    noBodyStableCounter = 0
    guard now - lastBodySeenAt > noBodyGraceWindow else {
      return
    }
    noBodyCounter += 1
    if noBodyCounter >= noBodyEnterFrames {
      noBodyActive = true
    }
  }
}
#endif
