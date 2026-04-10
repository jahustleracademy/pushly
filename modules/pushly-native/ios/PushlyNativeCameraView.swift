import ExpoModulesCore
#if os(iOS)
import AVFoundation
import UIKit

final class PushlyNativeCameraView: ExpoView {
  private struct TorsoReferenceFrame {
    let shoulderMid: CGPoint
    let hipMid: CGPoint
    let longitudinal: CGVector
    let lateral: CGVector
    let shoulderSpan: CGFloat
    let torsoLength: CGFloat
  }

  private weak static var latestInstance: PushlyNativeCameraView?

  static func exportLatestDebugSession(completion: @escaping (Result<String, Error>) -> Void) {
    DispatchQueue.main.async {
      guard let instance = latestInstance else {
        completion(.failure(NSError(domain: "PushlyNativeCameraView", code: 404, userInfo: [NSLocalizedDescriptionKey: "No active camera view instance"])))
        return
      }
      instance.exportDebugSession(completion: completion)
    }
  }

  let onPoseFrame = EventDispatcher()

  var isActive = true {
    didSet {
      cameraManager.setActive(isActive)
      if isActive {
        resetPushupSessionState()
        diagnostics.beginSession(
          cameraPosition: cameraPosition,
          mirrored: cameraPosition == .front,
          activeBackend: poseCoordinator.activeBackend,
          fallbackAvailable: poseCoordinator.isFallbackAvailable
        )
      } else {
        resetPushupSessionState()
        diagnostics.endSession(reason: "inactive")
      }
    }
  }

  var showSkeleton = true {
    didSet { setNeedsLayout() }
  }

  var cameraPosition: AVCaptureDevice.Position = .front {
    didSet { cameraManager.rebuildForCameraPosition(cameraPosition) }
  }

  var repTarget = 3
  var debugMode = false
  var forceFullFrameProcessing = false
  var forceROIProcessing = false
  var poseBackendMode: String = "auto"

  private let config = PushlyPoseConfig()
  private lazy var diagnostics = PoseDiagnostics(config: config)
  private let sessionQueue = DispatchQueue(label: "com.pushly.camera.session")
  private let poseQueue = DispatchQueue(label: "com.pushly.camera.pose")

  private lazy var cameraManager = CameraCaptureManager(queue: sessionQueue, outputQueue: poseQueue, config: config, diagnostics: diagnostics)
  private lazy var mediaPipeBackend = MediaPipePoseBackend(config: config, diagnostics: diagnostics)
  private lazy var visionBackend = VisionPoseBackend(config: config, diagnostics: diagnostics)
  private lazy var poseCoordinator = PoseBackendCoordinator(config: config, mediaPipeBackend: mediaPipeBackend, visionFallbackBackend: visionBackend, diagnostics: diagnostics)
  private lazy var reacquireDetector = ReacquireDetector(config: config)
  private lazy var temporalTracker = TemporalJointTracker(config: config)
  private lazy var continuityTracker = TrackContinuityManager(config: config)
  private lazy var qualityEvaluator = TrackingQualityEvaluator(config: config)
  private lazy var repDetector = PushupRepDetector(config: config)
  private lazy var instructionEngine = InstructionEngine()
  private lazy var payloadMapper = JSBridgePayloadMapper()
  private var skeletonRenderer: SkeletonRenderer?

  private let glowLayer = CAGradientLayer()
  private let feedbackLabel = UILabel()
  private let debugLabel = UILabel()
  private var displayLink: CADisplayLink?

  private var isProcessingFrame = false
  private var lastEmit = Date.distantPast
  private var lastProcessedAt: CFTimeInterval = 0
  private var latestLowLight = false
  private var latestCameraTelemetry: CameraTelemetry?
  private var latestROIMetadata: PoseROIMetadata?
  private var latestOrientation: CGImagePropertyOrientation = .up
  private var latestMirrored = false
  private var latestPixelBufferSize: CGSize = .zero
  private var frameIndex = 0
  private var currentPoseFPS: Double = 0
  private var lastPoseFrameAt: CFTimeInterval = 0
  private var previousBodyState: BodyState = .lost
  private var previousBodyMode: BodyTrackingMode = .unknown
  private var previousBackend: PoseBackendKind?
  private var previousLowLight = false
  private var consecutiveEmptyResults = 0
  private var previousReacquireSource: ReacquireSource = .none
  private var latestBackendDebugState: PoseBackendDebugState?

  private var renderJoints: [PushlyJointName: TrackedJoint] = [:]
  private var renderState: BodyState = .lost
  private var renderMode: BodyTrackingMode = .unknown
  private var renderAvgVelocity: Double = 0
  private var renderJointCount: Int = 0
  private var renderAvgConfidence: Double = 0
  private var renderRoiCoverage: Double = 0
  private var renderReliability: Double = 0
  private var renderUpperCoverage: Double = 0
  private var renderFullCoverage: Double = 0
  private var renderHandCoverage: Double = 0
  private var renderInferredRatio: Double = 0
  private var renderRawTrackedRms: Double = 0
  private var renderTrackedSpringRms: Double = 0
  private var renderRelockMs: Double = 0
  private var renderBackend: PoseBackendKind = .visionFallback
  private var renderGraceUntil: TimeInterval = 0
  private var pushupBottomRenderGraceUntil: TimeInterval = 0
  private var deferredTemporalResetUntil: TimeInterval = 0
  private var renderGraceActive = false
  private var lastRenderableJoints: [PushlyJointName: TrackedJoint] = [:]
  private var lastBottomTorsoFrame: TorsoReferenceFrame?
  private var latestInstructionText = "Halte deinen Körper lang und stabil."

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    Self.latestInstance = self
    debugMode = config.pipeline.debugOverlayEnabled
    clipsToBounds = true
    layer.cornerRadius = 28
    backgroundColor = UIColor(red: 6 / 255, green: 7 / 255, blue: 6 / 255, alpha: 1)

    glowLayer.colors = [
      UIColor(red: 186 / 255, green: 250 / 255, blue: 32 / 255, alpha: 0.44).cgColor,
      UIColor.clear.cgColor
    ]
    glowLayer.startPoint = CGPoint(x: 0.2, y: 0.1)
    glowLayer.endPoint = CGPoint(x: 0.8, y: 1)
    layer.addSublayer(glowLayer)
    layer.addSublayer(cameraManager.previewLayer)

    skeletonRenderer = SkeletonRenderer(
      containerLayer: layer,
      lineEndpointAlpha: config.smoothing.renderLineEndpointAlpha
    )

    feedbackLabel.textColor = .white
    feedbackLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    feedbackLabel.numberOfLines = 2
    feedbackLabel.textAlignment = .center
    feedbackLabel.text = "Kalibriere dich im Frame"
    feedbackLabel.isHidden = true
    addSubview(feedbackLabel)

    debugLabel.textColor = UIColor(red: 186 / 255, green: 250 / 255, blue: 32 / 255, alpha: 0.95)
    debugLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
    debugLabel.numberOfLines = 16
    debugLabel.textAlignment = .left
    debugLabel.backgroundColor = UIColor.black.withAlphaComponent(0.38)
    debugLabel.layer.cornerRadius = 8
    debugLabel.layer.masksToBounds = true
    debugLabel.isHidden = !debugMode
    addSubview(debugLabel)

    wirePipeline()
    setupDisplayLink()
    cameraManager.setActive(isActive)
    diagnostics.beginSession(
      cameraPosition: cameraPosition,
      mirrored: cameraPosition == .front,
      activeBackend: poseCoordinator.activeBackend,
      fallbackAvailable: poseCoordinator.isFallbackAvailable
    )
  }

  deinit {
    displayLink?.invalidate()
    diagnostics.endSession(reason: "deinit")
    if Self.latestInstance === self {
      Self.latestInstance = nil
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    glowLayer.frame = bounds.insetBy(dx: -40, dy: -60)
    cameraManager.previewLayer.frame = bounds
    skeletonRenderer?.updateFrame(bounds)
    updateRendererProjectionContext()
    feedbackLabel.frame = CGRect(x: 20, y: bounds.height - 74, width: bounds.width - 40, height: 48)
    debugLabel.frame = CGRect(x: 12, y: 14, width: min(320, bounds.width - 24), height: 196)
  }

  private func wirePipeline() {
    cameraManager.onAuthorizationIssue = { [weak self] text in
      self?.updateFeedbackLabel(text)
    }

    cameraManager.onTelemetry = { [weak self] telemetry in
      self?.latestCameraTelemetry = telemetry
      self?.diagnostics.recordCameraTelemetry(telemetry)
    }

    cameraManager.onFrameRateChanged = { [weak self] oldFPS, newFPS, reason in
      self?.diagnostics.recordCameraFrameRateChanged(from: oldFPS, to: newFPS, reason: reason)
    }

    cameraManager.onFrame = { [weak self] sampleBuffer in
      self?.handleFrame(sampleBuffer)
    }
  }

  private func resetPushupSessionState() {
    repDetector.reset(repCount: 0)
    continuityTracker.reset()
    temporalTracker.hardReset()
    renderJoints = [:]
    renderState = .lost
    renderMode = .unknown
    renderGraceUntil = 0
    pushupBottomRenderGraceUntil = 0
    deferredTemporalResetUntil = 0
    renderGraceActive = false
    lastRenderableJoints = [:]
    lastBottomTorsoFrame = nil
    previousBodyState = .lost
    previousBodyMode = .unknown
    previousBackend = nil
    previousReacquireSource = .none
    consecutiveEmptyResults = 0
    frameIndex = 0
  }

  private func handleFrame(_ sampleBuffer: CMSampleBuffer) {
    guard isActive else { return }
    if isProcessingFrame { return }
    let cameraFrameSignpost = diagnostics.beginSignpost(.cameraFrame)
    defer { diagnostics.endSignpost(cameraFrameSignpost) }

    let pipelineSignpost = diagnostics.beginSignpost(.framePipeline)
    defer { diagnostics.endSignpost(pipelineSignpost) }

    let nowClock = CACurrentMediaTime()
    let minDelta = 1.0 / desiredPoseFPS()
    guard nowClock - lastProcessedAt >= minDelta else { return }
    lastProcessedAt = nowClock
    isProcessingFrame = true
    let processingStarted = CACurrentMediaTime()

    defer {
      isProcessingFrame = false
      cameraManager.reportProcessingDuration(ms: (CACurrentMediaTime() - processingStarted) * 1000)
    }

    do {
      frameIndex += 1
      let previewMirrored = cameraPosition == .front
      let analysisMirrored = false
      let bufferSize = pixelBufferSize(from: sampleBuffer)
      let orientation = imageOrientation(bufferSize: bufferSize, mirrored: analysisMirrored)
      latestPixelBufferSize = bufferSize
      latestOrientation = orientation
      latestMirrored = previewMirrored

      diagnostics.recordOrientationAndMirror(
        orientation: orientation,
        mirrored: previewMirrored,
        previewSize: bounds.size,
        bufferSize: bufferSize
      )

      let reacquireSignpost = diagnostics.beginSignpost(.reacquirePass)
      let reacquireObservation = shouldRunReacquire()
        ? reacquireDetector.detect(sampleBuffer: sampleBuffer, orientation: orientation, mirrored: analysisMirrored)
        : nil
      diagnostics.endSignpost(reacquireSignpost)
      if let reacquireObservation {
        diagnostics.recordReacquireAttempt(source: reacquireObservation.source)
      }

      let roiHintPayload = continuityTracker.nextROIHint(
        frameIndex: frameIndex,
        roiDebugMode: effectiveROIDebugMode(),
        latestReacquire: reacquireObservation
      )
      let clampedROI = roiHintPayload.roi.map { PoseCoordinateConverter.clampNormalizedROI($0, minSize: config.reacquire.roiMinSize) }
      let wasClamped = clampedROI != roiHintPayload.roi
      diagnostics.recordROI(clampedROI, source: roiHintPayload.source, wasClamped: wasClamped)

      applyBackendPreferenceOverride()

      let inferenceSignpost = diagnostics.beginSignpost(.backendInference)
      let processed = try poseCoordinator.process(
        frame: PoseFrameInput(
          sampleBuffer: sampleBuffer,
          orientation: orientation,
          mirrored: analysisMirrored,
          roiHint: roiHintPayload.roi,
          timestamp: nowClock,
          targetMode: continuityTracker.bodyMode,
          reacquireSource: roiHintPayload.source,
          relockSuccessCount: continuityTracker.relockSuccessCount,
          relockFailureCount: continuityTracker.relockFailureCount
        )
      )
      diagnostics.endSignpost(inferenceSignpost)
      latestBackendDebugState = poseCoordinator.lastBackendDebugState
      if processed.detectedJointCount == 0 {
        consecutiveEmptyResults += 1
        diagnostics.recordBackendResultEmpty(processed.backend, consecutive: consecutiveEmptyResults)
      } else {
        consecutiveEmptyResults = 0
      }
      if let previousBackend, previousBackend != processed.backend {
        diagnostics.recordBackendSwitch(from: previousBackend, to: processed.backend, reason: "runtime_selection")
      }
      previousBackend = processed.backend

      latestLowLight = processed.lowLightDetected
      if previousLowLight != processed.lowLightDetected {
        diagnostics.recordLowLightChanged(active: processed.lowLightDetected)
        previousLowLight = processed.lowLightDetected
      }
      cameraManager.adaptFrameRateForPipeline(processingFPS: currentPoseFPS, lowLightDetected: processed.lowLightDetected)

      let continuitySignpost = diagnostics.beginSignpost(.continuityUpdate)
      continuityTracker.update(
        measured: processed.measured,
        modeHint: processed.mode == .unknown ? nil : processed.mode,
        modeHintConfidence: processed.modeConfidence,
        coverage: processed.coverage,
        segmentationBottomAssistActive: processed.backendDiagnostics.segmentationBottomAssistActive,
        now: nowClock,
        reacquire: reacquireObservation
      )
      diagnostics.endSignpost(continuitySignpost)
      if previousBodyMode != continuityTracker.bodyMode {
        diagnostics.recordModeTransition(from: previousBodyMode, to: continuityTracker.bodyMode)
        previousBodyMode = continuityTracker.bodyMode
      }
      if previousBodyState != continuityTracker.poseState {
        diagnostics.recordTrackingStateTransition(from: previousBodyState, to: continuityTracker.poseState)
        previousBodyState = continuityTracker.poseState
      }
      if previousReacquireSource != continuityTracker.lastReacquireSource {
        diagnostics.recordReacquireEnd(success: continuityTracker.state == .tracking, source: continuityTracker.lastReacquireSource)
        previousReacquireSource = continuityTracker.lastReacquireSource
      }

      if continuityTracker.poseState == .lost {
        if continuityTracker.pushupFloorModeActive {
          deferredTemporalResetUntil = max(
            deferredTemporalResetUntil,
            nowClock + config.smoothing.pushupBottomTemporalResetGraceSeconds
          )
          if nowClock > deferredTemporalResetUntil {
            temporalTracker.hardReset()
            deferredTemporalResetUntil = 0
          }
        } else {
          temporalTracker.hardReset()
          deferredTemporalResetUntil = 0
        }
      } else {
        deferredTemporalResetUntil = 0
      }

      let now = Date().timeIntervalSince1970
      let smoothingSignpost = diagnostics.beginSignpost(.smoothingUpdate)
      let tracked = temporalTracker.update(
        measured: processed.measured,
        lowLightDetected: processed.lowLightDetected,
        roiHint: continuityTracker.lastStableROI,
        frameTimestamp: now,
        tooCloseFallbackActive: processed.backendDiagnostics.tooCloseFallbackActive,
        reacquireActive: continuityTracker.state != .tracking,
        pushupFloorModeActive: continuityTracker.pushupFloorModeActive
      )
      let fallbackDiagnostics = temporalTracker.fallbackDiagnostics
      diagnostics.endSignpost(smoothingSignpost)

      let allowsRendering = continuityTracker.poseState.allowsRendering
      let jointsForLogic = (allowsRendering && tracked.count >= config.pipeline.logicMinJointCount) ? tracked : [:]
      let pushupBottomOcclusionCandidate = continuityTracker.pushupFloorModeActive
      let segmentationBottomAssist = pushupBottomOcclusionCandidate
        && processed.backendDiagnostics.segmentationBottomAssistActive
      let floorRenderJoints = pushupBottomOcclusionCandidate
        ? buildPushupBottomRenderJoints(current: tracked, fallback: lastRenderableJoints)
        : [:]
      if !pushupBottomOcclusionCandidate {
        lastBottomTorsoFrame = nil
      }
      let floorCoreCount = countPushupBottomCoreJoints(in: floorRenderJoints)
      let pushupBottomCoreRequired = segmentationBottomAssist
        ? max(3, config.pipeline.pushupBottomRenderCoreMinJointCount - 1)
        : config.pipeline.pushupBottomRenderCoreMinJointCount
      let hasPushupBottomRenderableCore = floorCoreCount >= pushupBottomCoreRequired
      let jointsForRender: [PushlyJointName: TrackedJoint]
      let isRenderGraceActive: Bool
      let bottomRenderDisappearReason: String?
      if !jointsForLogic.isEmpty {
        jointsForRender = jointsForLogic
        renderGraceUntil = now + config.smoothing.renderPersistenceGraceSeconds
        if pushupBottomOcclusionCandidate {
          let baseBottomGrace = now + config.smoothing.pushupBottomRenderGraceSeconds
          let assistBottomGrace = segmentationBottomAssist
            ? now + config.smoothing.pushupBottomRenderGraceSeconds + config.smoothing.segmentationBottomAssistRenderGraceSeconds
            : baseBottomGrace
          pushupBottomRenderGraceUntil = max(pushupBottomRenderGraceUntil, assistBottomGrace)
        }
        lastRenderableJoints = jointsForLogic
        isRenderGraceActive = false
        bottomRenderDisappearReason = nil
      } else if pushupBottomOcclusionCandidate && hasPushupBottomRenderableCore {
        jointsForRender = floorRenderJoints
        renderGraceUntil = max(renderGraceUntil, now + config.smoothing.renderPersistenceGraceSeconds)
        let baseBottomGrace = now + config.smoothing.pushupBottomRenderGraceSeconds
        let assistBottomGrace = segmentationBottomAssist
          ? now + config.smoothing.pushupBottomRenderGraceSeconds + config.smoothing.segmentationBottomAssistRenderGraceSeconds
          : baseBottomGrace
        pushupBottomRenderGraceUntil = max(pushupBottomRenderGraceUntil, assistBottomGrace)
        lastRenderableJoints = floorRenderJoints
        isRenderGraceActive = true
        bottomRenderDisappearReason = nil
      } else if now <= max(renderGraceUntil, pushupBottomRenderGraceUntil) {
        if pushupBottomOcclusionCandidate && now <= pushupBottomRenderGraceUntil {
          let pushupBottomMinJointCount = segmentationBottomAssist
            ? max(3, config.pipeline.pushupBottomRenderMinJointCount - 1)
            : config.pipeline.pushupBottomRenderMinJointCount
          if floorRenderJoints.count >= pushupBottomMinJointCount {
            jointsForRender = floorRenderJoints
            lastRenderableJoints = floorRenderJoints
          } else if lastRenderableJoints.count >= pushupBottomMinJointCount {
            jointsForRender = buildPushupBottomRenderJoints(current: [:], fallback: lastRenderableJoints)
          } else {
            jointsForRender = [:]
          }
        } else if tracked.count >= config.pipeline.renderPersistenceMinJointCount {
          jointsForRender = tracked
          lastRenderableJoints = tracked
        } else if lastRenderableJoints.count >= config.pipeline.renderPersistenceMinJointCount {
          jointsForRender = lastRenderableJoints
        } else {
          jointsForRender = [:]
        }
        isRenderGraceActive = !jointsForRender.isEmpty
        if pushupBottomOcclusionCandidate && jointsForRender.isEmpty {
          let pushupBottomMinJointCount = segmentationBottomAssist
            ? max(3, config.pipeline.pushupBottomRenderMinJointCount - 1)
            : config.pipeline.pushupBottomRenderMinJointCount
          if floorCoreCount < pushupBottomCoreRequired {
            bottomRenderDisappearReason = "bottom_core_insufficient"
          } else if floorRenderJoints.count < pushupBottomMinJointCount {
            bottomRenderDisappearReason = "bottom_min_joints_unmet"
          } else if lastRenderableJoints.count < pushupBottomMinJointCount {
            bottomRenderDisappearReason = "bottom_fallback_unavailable"
          } else {
            bottomRenderDisappearReason = "bottom_grace_branch_no_render"
          }
        } else {
          bottomRenderDisappearReason = nil
        }
      } else {
        jointsForRender = [:]
        renderGraceUntil = 0
        pushupBottomRenderGraceUntil = 0
        lastRenderableJoints = [:]
        lastBottomTorsoFrame = nil
        isRenderGraceActive = false
        bottomRenderDisappearReason = pushupBottomOcclusionCandidate ? "bottom_grace_expired" : nil
      }

      let avgConfidence = averageConfidence(of: jointsForRender)
      let avgVelocity = averageVelocityMagnitude(of: jointsForRender)
      let qualitySignpost = diagnostics.beginSignpost(.qualityEvaluation)
      let veryLowLightDetected = processed.brightnessLuma < config.quality.veryLowLightLumaThreshold
      let quality = qualityEvaluator.evaluate(
        joints: jointsForLogic,
        lowLightDetected: processed.lowLightDetected,
        veryLowLightDetected: veryLowLightDetected,
        trackingState: continuityTracker.state,
        poseState: continuityTracker.poseState,
        poseMode: continuityTracker.bodyMode,
        pushupFloorModeActive: continuityTracker.pushupFloorModeActive,
        modeConfidence: continuityTracker.modeConfidence,
        roiCoverage: continuityTracker.roiCoverage,
        coverageHint: continuityTracker.coverage
      )
      diagnostics.endSignpost(qualitySignpost)

      let rep = repDetector.update(
        joints: jointsForLogic,
        quality: quality,
        repTarget: repTarget,
        frameIndex: frameIndex,
        timestamp: nowClock
      )
      let bottomPhaseActive = rep.state == .bottomReached || rep.state == .ascending || rep.state == .descending
      let bottomRenderPersistenceActive = pushupBottomOcclusionCandidate && isRenderGraceActive
      let torsoAnchorAvailable = hasTorsoAnchor(in: floorRenderJoints.isEmpty ? jointsForRender : floorRenderJoints)
      let armAnchorAvailable = hasArmAnchor(in: floorRenderJoints.isEmpty ? jointsForRender : floorRenderJoints)
      let bottomRepNotCountedReason: String? = {
        guard bottomPhaseActive, rep.state != .repCounted else { return nil }
        if let gateReason = rep.repDebug?.countGateBlockReason, !gateReason.isEmpty {
          return gateReason
        }
        if !rep.blockedReasons.isEmpty {
          return rep.blockedReasons.joined(separator: ",")
        }
        switch rep.state {
        case .descending:
          return "bottom_not_confirmed"
        case .bottomReached:
          return "ascent_not_confirmed"
        case .ascending:
          return "cycle_not_completed"
        default:
          return "count_gate_not_met"
        }
      }()
      let instruction = instructionEngine.makeInstruction(
        quality: quality,
        repState: rep.state,
        blockedReasons: rep.blockedReasons,
        lowLightDetected: processed.lowLightDetected,
        requiresFullBody: config.instructions.requiresFullBodyForCurrentSession,
        now: now
      )
      if let instruction {
        latestInstructionText = instruction
      }

      updatePoseFPS(nowClock)
      diagnostics.recordProcessingFPS(currentPoseFPS)
      latestROIMetadata = PoseROIMetadata(
        bufferSize: bufferSize,
        orientation: orientation,
        mirrored: previewMirrored,
        roi: roiHintPayload.roi,
        roiSource: roiHintPayload.source
      )

      DispatchQueue.main.async {
        self.updateRendererProjectionContext()
        self.renderJoints = jointsForRender
        self.renderState = self.continuityTracker.poseState
        self.renderMode = self.continuityTracker.bodyMode
        self.renderGraceActive = isRenderGraceActive
        self.renderAvgVelocity = avgVelocity
        self.renderJointCount = jointsForRender.count
        self.renderAvgConfidence = avgConfidence
        self.renderRoiCoverage = quality.roiCoverage
        self.renderReliability = quality.reliability
        self.renderUpperCoverage = quality.upperBodyCoverage
        self.renderFullCoverage = quality.fullBodyCoverage
        self.renderHandCoverage = quality.handCoverage
        self.renderRelockMs = self.continuityTracker.lastRelockDuration * 1000
        self.renderBackend = processed.backend
      }

      diagnostics.recordProcessedFrame(
        frameIndex: frameIndex,
        timestamp: nowClock,
        backend: processed.backend,
        mode: continuityTracker.bodyMode,
        trackingState: continuityTracker.poseState,
        visibleJointCount: quality.visibleJointCount,
        upperBodyCoverage: quality.upperBodyCoverage,
        fullBodyCoverage: quality.fullBodyCoverage,
        handCoverage: quality.handCoverage,
        averageJointConfidence: avgConfidence,
        reliability: quality.reliability,
        roi: roiHintPayload.roi,
        mirrored: previewMirrored,
        orientation: orientation,
        inferenceDurationMs: processed.backendDiagnostics.durationMs,
        pipelineDurationMs: (CACurrentMediaTime() - processingStarted) * 1000,
        renderedJointCount: jointsForRender.count,
        inferredJointRatio: quality.inferredJointRatio,
        measuredJointCount: sourceTypeCount(in: jointsForRender, type: .measured),
        lowConfidenceMeasuredJointCount: sourceTypeCount(in: jointsForRender, type: .lowConfidenceMeasured),
        inferredJointCount: sourceTypeCount(in: jointsForRender, type: .inferred),
        predictedJointCount: sourceTypeCount(in: jointsForRender, type: .predicted),
        missingJointCount: sourceTypeCount(in: jointsForRender, type: .missing),
        pushupBlockedReasons: rep.blockedReasons,
        sideLockSwapped: temporalTracker.sideIdentityDiagnostics.lockSwapped,
        sideSwapEvidenceStreak: temporalTracker.sideIdentityDiagnostics.swapEvidenceStreak,
        sideKeepEvidenceStreak: temporalTracker.sideIdentityDiagnostics.keepEvidenceStreak,
        sideSwapAppliedThisFrame: temporalTracker.sideIdentityDiagnostics.swapAppliedThisFrame,
        tooCloseFallbackActive: processed.backendDiagnostics.tooCloseFallbackActive,
        tooCloseInferredHipCount: processed.backendDiagnostics.tooCloseInferredHipCount,
        cameraProcessingBacklog: latestCameraTelemetry?.processingBacklog ?? 0,
        cameraAverageProcessingMs: latestCameraTelemetry?.averageProcessingMs ?? 0,
        bottomPhaseActive: bottomPhaseActive,
        pushupFloorModeActive: continuityTracker.pushupFloorModeActive,
        segmentationAssistActive: processed.backendDiagnostics.segmentationBottomAssistActive,
        bottomRenderPersistenceActive: bottomRenderPersistenceActive,
        torsoAnchorAvailable: torsoAnchorAvailable,
        armAnchorAvailable: armAnchorAvailable,
        bottomRenderDisappearReason: bottomRenderDisappearReason,
        bottomRepNotCountedReason: bottomRepNotCountedReason
      )

      emitPoseFrame(
        joints: jointsForRender,
        quality: quality,
        rep: rep,
        instruction: latestInstructionText,
        lowLightDetected: processed.lowLightDetected,
        backend: processed.backend,
        backendDebug: latestBackendDebugState,
        fallbackDiagnostics: fallbackDiagnostics
      )
    } catch {
      latestBackendDebugState = poseCoordinator.lastBackendDebugState
      diagnostics.recordBackendUnavailable(kind: renderBackend, reason: "process_frame_failed")
      emitFallbackFrame(backendDebug: latestBackendDebugState)
    }
  }

  private func shouldRunReacquire() -> Bool {
    if continuityTracker.state != .tracking {
      return frameIndex % max(1, config.reacquire.detectorCadenceFrames) == 0
    }
    return false
  }

  private func applyBackendPreferenceOverride() {
    switch poseBackendMode {
    case "vision":
      poseCoordinator.setPreferenceOverride(.vision)
      poseCoordinator.setFallbackAllowedOverride(nil)
    case "mediapipe", "mlkit":
      poseCoordinator.setPreferenceOverride(.mediapipe)
      // Prefer MediaPipe, but keep automatic fallback enabled so sessions remain usable.
      poseCoordinator.setFallbackAllowedOverride(nil)
    default:
      poseCoordinator.setPreferenceOverride(nil)
      poseCoordinator.setFallbackAllowedOverride(nil)
    }
  }

  private func effectiveROIDebugMode() -> PushlyPoseConfig.ROIDebugMode {
    if forceFullFrameProcessing {
      return .fullFrameOnly
    }
    if forceROIProcessing {
      return .roiOnly
    }
    return config.pipeline.roiDebugMode
  }

  private func emitFallbackFrame(backendDebug: PoseBackendDebugState? = nil) {
    continuityTracker.reset()
    temporalTracker.hardReset()

    DispatchQueue.main.async {
      self.renderJoints = [:]
      self.renderState = .lost
      self.renderMode = .unknown
      self.renderAvgVelocity = 0
      self.renderJointCount = 0
      self.renderAvgConfidence = 0
      self.renderRoiCoverage = 0
      self.renderReliability = 0
      self.renderUpperCoverage = 0
      self.renderFullCoverage = 0
      self.renderHandCoverage = 0
      self.renderInferredRatio = 0
      self.renderRawTrackedRms = 0
      self.renderTrackedSpringRms = 0
      self.renderRelockMs = 0
      self.renderGraceUntil = 0
      self.pushupBottomRenderGraceUntil = 0
      self.deferredTemporalResetUntil = 0
      self.renderGraceActive = false
      self.lastRenderableJoints = [:]
      self.lastBottomTorsoFrame = nil
    }

    let resolvedBackendDebug = backendDebug ?? poseCoordinator.lastBackendDebugState
    let mediaPipeDiagnostics = resolvedBackendDebug.mediaPipeDiagnostics
    let mediapipeInitReason = mediaPipeDiagnostics.mediapipeInitReason
    let fallbackInstruction: String
    if resolvedBackendDebug.requestedBackend == .mediapipe, !resolvedBackendDebug.mediapipeAvailable {
      fallbackInstruction = mediaPipeUnavailableInstruction(reason: mediapipeInitReason)
    } else if resolvedBackendDebug.requestedBackend == .mediapipe, resolvedBackendDebug.fallbackReason == "primary_error" {
      fallbackInstruction = "MediaPipe ist fehlgeschlagen. Bitte Kamera neu ausrichten oder App neu starten."
    } else {
      fallbackInstruction = latestLowLight
        ? "Licht ist niedrig. Dreh dich leicht zur Lichtquelle."
        : "Erkennung wird vorbereitet."
    }
    latestInstructionText = fallbackInstruction

    let now = Date()
    guard now.timeIntervalSince(lastEmit) >= config.pipeline.minEmitInterval else { return }
    lastEmit = now
    updateFeedbackLabel(fallbackInstruction)

    onPoseFrame([
      "bodyDetected": false,
      "confidence": 0,
      "formEvidenceScore": 0,
      "instruction": fallbackInstruction,
      "joints": [],
      "repCount": repDetector.repCount,
      "state": PushupState.lostTracking.rawValue,
      "trackingState": TrackingContinuityState.lost.rawValue,
      "trackingContinuityState": TrackingContinuityState.lost.rawValue,
      "poseTrackingState": BodyState.lost.rawValue,
      "poseMode": BodyTrackingMode.unknown.rawValue,
      "bodyMode": BodyTrackingMode.unknown.rawValue,
      "trackingQuality": 0.0,
      "renderQuality": 0.0,
      "logicQuality": 0.0,
      "bodyVisibilityState": BodyVisibilityState.notFound.rawValue,
      "lowLightDetected": latestLowLight,
      "poseBackend": resolvedBackendDebug.activeBackend.rawValue,
      "requestedBackend": resolvedBackendDebug.requestedBackend.rawValue,
      "activeBackend": resolvedBackendDebug.activeBackend.rawValue,
      "fallbackAllowed": resolvedBackendDebug.fallbackAllowed,
      "fallbackUsed": resolvedBackendDebug.fallbackUsed,
      "fallbackReason": resolvedBackendDebug.fallbackReason as Any,
      "mediapipeAvailable": resolvedBackendDebug.mediapipeAvailable,
      "compiledWithMediaPipe": mediaPipeDiagnostics.compiledWithMediaPipe,
      "poseModelFound": mediaPipeDiagnostics.poseModelFound,
      "poseModelName": mediaPipeDiagnostics.poseModelName as Any,
      "poseModelPath": mediaPipeDiagnostics.poseModelPath as Any,
      "poseLandmarkerInitStatus": mediaPipeDiagnostics.poseLandmarkerInitStatus,
      "mediapipeInitReason": mediapipeInitReason as Any,
      "reacquireSource": ReacquireSource.none.rawValue,
      "visibleJointCount": 0,
      "mirrored": latestMirrored,
      "orientation": latestOrientation.rawValue,
      "debugSessionID": diagnostics.sessionIdentifier,
      "upperBodyCoverage": 0,
      "fullBodyCoverage": 0,
      "handCoverage": 0,
      "cameraFPS": latestCameraTelemetry?.captureFPS as Any,
      "cameraProcessingBacklog": latestCameraTelemetry?.processingBacklog as Any,
      "cameraAverageProcessingMs": latestCameraTelemetry?.averageProcessingMs as Any,
      "processingFPS": currentPoseFPS
    ])
  }

  private func mediaPipeUnavailableInstruction(reason: String?) -> String {
    switch reason {
    case "pose_model_missing":
      return "MediaPipe-Modell fehlt. Bitte App neu bauen und pose_landmarker_*.task im iOS-Bundle mitliefern."
    case "mediapipe_tasks_vision_not_compiled":
      return "MediaPipe-Framework fehlt im iOS-Build. Bitte Pods/Dependencies installieren und die App neu bauen."
    default:
      return "MediaPipe-Landmarker konnte nicht starten (\(reason ?? "unknown")). Bitte App neu starten oder iOS-Build neu erstellen."
    }
  }

  private func emitPoseFrame(
    joints: [PushlyJointName: TrackedJoint],
    quality: TrackingQuality,
    rep: RepDetectionOutput,
    instruction: String,
    lowLightDetected: Bool,
    backend: PoseBackendKind,
    backendDebug: PoseBackendDebugState? = nil,
    fallbackDiagnostics: TemporalJointTracker.FallbackTrackingDiagnostics
  ) {
    let now = Date()
    guard now.timeIntervalSince(lastEmit) >= config.pipeline.minEmitInterval else { return }
    lastEmit = now

    let payload = payloadMapper.makePayload(
      joints: joints,
      quality: quality,
      rep: rep,
      instruction: instruction,
      lowLightDetected: lowLightDetected,
      poseBackend: backend,
      poseFPS: currentPoseFPS,
      cameraTelemetry: latestCameraTelemetry,
      bounds: bounds,
      debugEnabled: debugMode,
      reacquireSource: continuityTracker.lastReacquireSource,
      orientation: latestOrientation,
      mirrored: latestMirrored,
      debugSessionID: diagnostics.sessionIdentifier,
      visibleJointCount: joints.count,
      backendDebug: backendDebug,
      fallbackDiagnostics: fallbackDiagnostics
    )

    updateFeedbackLabel(instruction)
    onPoseFrame(payload)
  }

  private func updateFeedbackLabel(_ text: String) {
    _ = text
    DispatchQueue.main.async {
      self.feedbackLabel.isHidden = true
    }
  }

  private func imageOrientation(bufferSize: CGSize, mirrored: Bool) -> CGImagePropertyOrientation {
    let isPortraitBuffer = bufferSize.height >= bufferSize.width
    if isPortraitBuffer {
      return mirrored ? .upMirrored : .up
    }
    return mirrored ? .leftMirrored : .right
  }

  private func pixelBufferSize(from sampleBuffer: CMSampleBuffer) -> CGSize {
    guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return .zero
    }
    return CGSize(width: CVPixelBufferGetWidth(imageBuffer), height: CVPixelBufferGetHeight(imageBuffer))
  }

  private func updatePoseFPS(_ nowClock: CFTimeInterval) {
    defer { lastPoseFrameAt = nowClock }
    guard lastPoseFrameAt > 0 else { return }
    let dt = nowClock - lastPoseFrameAt
    guard dt > 0 else { return }
    currentPoseFPS = 1.0 / dt
  }

  @objc
  private func onDisplayLinkTick() {
    let signpost = diagnostics.beginSignpost(.renderUpdate)
    let diagnostics = renderSkeleton(
      joints: renderJoints,
      state: renderState,
      debugMode: debugMode,
      avgBodyVelocity: renderAvgVelocity
    )
    self.diagnostics.endSignpost(signpost)
    renderInferredRatio = diagnostics.inferredRatio
    renderRawTrackedRms = diagnostics.rawToTrackedRmsPx
    renderTrackedSpringRms = diagnostics.trackedToSpringRmsPx
    updateDebugOverlay(
      state: renderState,
      mode: renderMode,
      jointCount: renderJointCount,
      avgConfidence: renderAvgConfidence,
      avgVelocity: renderAvgVelocity
    )
  }

  private func setupDisplayLink() {
    let link = CADisplayLink(target: self, selector: #selector(onDisplayLinkTick))
    if #available(iOS 15.0, *) {
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 45, maximum: 120, preferred: 60)
    } else {
      link.preferredFramesPerSecond = 60
    }
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  private func exportDebugSession(completion: @escaping (Result<String, Error>) -> Void) {
    let snapshot: [String: String] = [
      "backendPreference": poseBackendMode,
      "cameraPosition": cameraPosition == .front ? "front" : "back",
      "debugMode": "\(debugMode)",
      "forceFullFrameProcessing": "\(forceFullFrameProcessing)",
      "forceROIProcessing": "\(forceROIProcessing)",
      "pipelineVerboseFrameLogs": "\(config.pipeline.verboseFrameLoggingEnabled)",
      "pipelineStructuredLogs": "\(config.pipeline.structuredLoggingEnabled)",
      "pipelineSignposts": "\(config.pipeline.signpostsEnabled)"
    ]

    diagnostics.exportToDisk(configSnapshot: snapshot) { result in
      switch result {
      case .success(let url):
        completion(.success(url.path))
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  private func renderSkeleton(joints: [PushlyJointName: TrackedJoint], state: BodyState, debugMode: Bool, avgBodyVelocity: Double) -> SkeletonRenderDiagnostics {
    let canRender = showSkeleton
      && joints.count >= config.pipeline.renderPersistenceMinJointCount
      && (state.allowsRendering || renderGraceActive)
    return skeletonRenderer?.render(
      joints: joints,
      in: bounds,
      showSkeleton: canRender,
      debugMode: debugMode,
      avgBodyVelocity: avgBodyVelocity,
      trackingState: continuityTracker.state
    ) ?? SkeletonRenderDiagnostics(rawToTrackedRmsPx: 0, trackedToSpringRmsPx: 0, inferredRatio: 0, measuredJointCount: 0, inferredJointCount: 0)
  }

  private func updateDebugOverlay(
    state: BodyState,
    mode: BodyTrackingMode,
    jointCount: Int,
    avgConfidence: Double,
    avgVelocity: Double
  ) {
    guard debugMode else {
      debugLabel.isHidden = true
      return
    }
    debugLabel.isHidden = false
    let roiSummary = latestROIMetadata?.summary ?? "roi:n/a"
    let orientationSummary = "ori:\(latestOrientation.rawValue) mir:\(latestMirrored ? 1 : 0)"
    let camFPS = latestCameraTelemetry?.captureFPS ?? 0
    let dropRate = latestCameraTelemetry?.dropRate ?? 0
    let backlog = latestCameraTelemetry?.processingBacklog ?? 0
    let avgProcessing = latestCameraTelemetry?.averageProcessingMs ?? 0
    let backendDebug = latestBackendDebugState ?? poseCoordinator.lastBackendDebugState
    let mediaPipeDiagnostics = backendDebug.mediaPipeDiagnostics
    let mediaPipeCompiled = mediaPipeDiagnostics.compiledWithMediaPipe ? "yes" : "no"
    let mediaPipeAvailable = backendDebug.mediapipeAvailable ? "yes" : "no"
    let fallbackUsed = backendDebug.fallbackUsed ? "yes" : "no"
    let fallbackReason = backendDebug.fallbackReason ?? "-"
    let mediapipeInitReason = mediaPipeDiagnostics.mediapipeInitReason ?? "-"
    debugLabel.text = """
    state: \(state.rawValue) mode:\(mode.rawValue)
    backend req/act: \(backendDebug.requestedBackend.rawValue)/\(backendDebug.activeBackend.rawValue)
    backend render/reacq: \(renderBackend.rawValue)/\(continuityTracker.lastReacquireSource.rawValue)
    mediapipe avail/compiled: \(mediaPipeAvailable)/\(mediaPipeCompiled)
    fallback used/reason: \(fallbackUsed)/\(fallbackReason)
    mediapipe init reason: \(mediapipeInitReason)
    joints: \(jointCount) conf:\(String(format: "%.2f", avgConfidence)) vel:\(String(format: "%.3f", avgVelocity))
    rel:\(String(format: "%.2f", renderReliability)) roi:\(String(format: "%.2f", renderRoiCoverage)) low:\(latestLowLight ? 1 : 0)
    cov u/f/h: \(String(format: "%.2f", renderUpperCoverage))/\(String(format: "%.2f", renderFullCoverage))/\(String(format: "%.2f", renderHandCoverage))
    cam/pose fps: \(String(format: "%.1f", camFPS))/\(String(format: "%.1f", currentPoseFPS)) drop:\(String(format: "%.2f", dropRate))
    backlog/ms: \(String(format: "%.2f", backlog))/\(String(format: "%.1f", avgProcessing))
    rms(rt/ts): \(String(format: "%.1f", renderRawTrackedRms))/\(String(format: "%.1f", renderTrackedSpringRms))
    inf/relock: \(String(format: "%.2f", renderInferredRatio))/\(Int(renderRelockMs))ms
    \(orientationSummary)
    \(roiSummary)
    """
  }

  private func updateRendererProjectionContext() {
    guard bounds.width > 0,
          bounds.height > 0,
          latestPixelBufferSize.width > 0,
          latestPixelBufferSize.height > 0 else {
      skeletonRenderer?.updateProjectionContext(nil)
      return
    }

    skeletonRenderer?.updateProjectionContext(
      PoseCoordinateConverter.ProjectionContext(
        previewBounds: bounds,
        pixelBufferSize: latestPixelBufferSize,
        videoGravity: cameraManager.previewLayer.videoGravity,
        orientation: latestOrientation,
        isMirrored: latestMirrored
      )
    )
  }

  private func desiredPoseFPS() -> Double {
    if ProcessInfo.processInfo.isLowPowerModeEnabled {
      return 24
    }
    switch ProcessInfo.processInfo.thermalState {
    case .serious, .critical:
      return 24
    default:
      return config.pipeline.maxPoseFps
    }
  }

  private func averageConfidence(of joints: [PushlyJointName: TrackedJoint]) -> Double {
    guard !joints.isEmpty else { return 0 }
    let total = joints.values.map { Double($0.renderConfidence) }.reduce(0, +)
    return total / Double(joints.count)
  }

  private func sourceTypeCount(in joints: [PushlyJointName: TrackedJoint], type: PushlyJointSourceType) -> Int {
    PushlyJointName.allCases.reduce(0) { partial, jointName in
      if joints[jointName]?.sourceType == type {
        return partial + 1
      }
      if joints[jointName] == nil, type == .missing {
        return partial + 1
      }
      return partial
    }
  }

  private func averageVelocityMagnitude(of joints: [PushlyJointName: TrackedJoint]) -> Double {
    guard !joints.isEmpty else { return 0 }
    let total = joints.values.map { sqrt(Double($0.velocity.dx * $0.velocity.dx + $0.velocity.dy * $0.velocity.dy)) }.reduce(0, +)
    return total / Double(joints.count)
  }

  private func buildPushupBottomRenderJoints(
    current: [PushlyJointName: TrackedJoint],
    fallback: [PushlyJointName: TrackedJoint]
  ) -> [PushlyJointName: TrackedJoint] {
    let fallbackFrame = torsoReferenceFrame(from: fallback, fallbackFrame: lastBottomTorsoFrame)
    let targetFrame = torsoReferenceFrame(from: current, fallbackFrame: fallbackFrame ?? lastBottomTorsoFrame)

    let priority: [PushlyJointName] = [
      .leftShoulder, .rightShoulder,
      .leftElbow, .rightElbow,
      .leftWrist, .rightWrist,
      .leftHip, .rightHip,
      .nose, .head
    ]
    var result: [PushlyJointName: TrackedJoint] = [:]
    for name in priority {
      if let joint = current[name], joint.sourceType != .missing {
        result[name] = joint
        continue
      }
      if var joint = fallback[name], joint.sourceType != .missing {
        if let sourceFrame = fallbackFrame,
           let targetFrame,
           let reprojected = reprojectBottomJoint(
             fallbackJoint: joint,
             sourceFrame: sourceFrame,
             targetFrame: targetFrame
           ) {
          joint.rawPosition = reprojected
          joint.smoothedPosition = reprojected
          joint.velocity = CGVector(dx: joint.velocity.dx * 0.5, dy: joint.velocity.dy * 0.5)
          joint.renderConfidence = max(0.12, min(joint.renderConfidence, joint.renderConfidence * 0.95))
          joint.logicConfidence = min(joint.logicConfidence, joint.renderConfidence)
        }
        result[name] = joint
      }
    }

    if !result.isEmpty {
      lastBottomTorsoFrame = targetFrame ?? fallbackFrame ?? lastBottomTorsoFrame
    }
    return result
  }

  private func torsoReferenceFrame(
    from joints: [PushlyJointName: TrackedJoint],
    fallbackFrame: TorsoReferenceFrame?
  ) -> TorsoReferenceFrame? {
    let leftShoulder = joints[.leftShoulder]?.smoothedPosition
    let rightShoulder = joints[.rightShoulder]?.smoothedPosition
    let leftHip = joints[.leftHip]?.smoothedPosition
    let rightHip = joints[.rightHip]?.smoothedPosition

    let shoulderMid = midpoint(leftShoulder, rightShoulder)
      ?? leftShoulder
      ?? rightShoulder
      ?? fallbackFrame?.shoulderMid
    guard let shoulderMid else { return nil }

    let shoulderSpanRaw = distance(leftShoulder, rightShoulder)
    let shoulderSpan = clamp(
      shoulderSpanRaw ?? fallbackFrame?.shoulderSpan ?? 0.12,
      min: 0.05,
      max: 0.5
    )

    let hipMid = midpoint(leftHip, rightHip)
      ?? leftHip
      ?? rightHip
      ?? fallbackFrame?.hipMid
      ?? clampPoint(shoulderMid + (fallbackFrame?.longitudinal ?? CGVector(dx: 0, dy: -1)) * shoulderSpan)

    var longitudinal = normalizedVector(from: shoulderMid, to: hipMid)
    if vectorMagnitude(longitudinal) <= 0.0001 {
      longitudinal = fallbackFrame?.longitudinal ?? CGVector(dx: 0, dy: -1)
    }
    longitudinal = normalize(longitudinal)

    var lateral: CGVector
    if let leftShoulder, let rightShoulder {
      lateral = normalize(CGVector(dx: rightShoulder.x - leftShoulder.x, dy: rightShoulder.y - leftShoulder.y))
    } else {
      lateral = normalize(CGVector(dx: -longitudinal.dy, dy: longitudinal.dx))
      if let fallbackLateral = fallbackFrame?.lateral, dot(lateral, fallbackLateral) < 0 {
        lateral = lateral * -1
      }
    }

    let torsoLength = clamp(
      distance(shoulderMid, hipMid),
      min: shoulderSpan * 0.7,
      max: shoulderSpan * 1.8
    )

    return TorsoReferenceFrame(
      shoulderMid: clampPoint(shoulderMid),
      hipMid: clampPoint(hipMid),
      longitudinal: longitudinal,
      lateral: lateral,
      shoulderSpan: shoulderSpan,
      torsoLength: torsoLength
    )
  }

  private func reprojectBottomJoint(
    fallbackJoint: TrackedJoint,
    sourceFrame: TorsoReferenceFrame,
    targetFrame: TorsoReferenceFrame
  ) -> CGPoint? {
    let source = fallbackJoint.smoothedPosition
    guard source.x.isFinite, source.y.isFinite else { return nil }
    let delta = CGVector(dx: source.x - sourceFrame.shoulderMid.x, dy: source.y - sourceFrame.shoulderMid.y)
    let latComponent = dot(delta, sourceFrame.lateral)
    let longComponent = dot(delta, sourceFrame.longitudinal)

    // Depth-like stabilization via torso-scale ratios; clamped to short plausible persistence.
    let lateralScale = clamp(targetFrame.shoulderSpan / max(0.0001, sourceFrame.shoulderSpan), min: 0.82, max: 1.22)
    let longitudinalScale = clamp(targetFrame.torsoLength / max(0.0001, sourceFrame.torsoLength), min: 0.84, max: 1.26)

    let projected = clampPoint(
      targetFrame.shoulderMid
        + targetFrame.lateral * (latComponent * lateralScale)
        + targetFrame.longitudinal * (longComponent * longitudinalScale)
    )
    guard projected.x.isFinite, projected.y.isFinite else { return nil }
    return projected
  }

  private func midpoint(_ a: CGPoint?, _ b: CGPoint?) -> CGPoint? {
    guard let a, let b else { return nil }
    return CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
  }

  private func distance(_ a: CGPoint?, _ b: CGPoint?) -> CGFloat? {
    guard let a, let b else { return nil }
    return hypot(a.x - b.x, a.y - b.y)
  }

  private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
  }

  private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
    Swift.min(maxValue, Swift.max(minValue, value))
  }

  private func clampPoint(_ point: CGPoint) -> CGPoint {
    CGPoint(x: clamp(point.x, min: 0, max: 1), y: clamp(point.y, min: 0, max: 1))
  }

  private func normalizedVector(from a: CGPoint, to b: CGPoint) -> CGVector {
    normalize(CGVector(dx: b.x - a.x, dy: b.y - a.y))
  }

  private func normalize(_ vector: CGVector) -> CGVector {
    let magnitude = vectorMagnitude(vector)
    guard magnitude > 0.0001 else { return CGVector(dx: 0, dy: -1) }
    return CGVector(dx: vector.dx / magnitude, dy: vector.dy / magnitude)
  }

  private func vectorMagnitude(_ vector: CGVector) -> CGFloat {
    hypot(vector.dx, vector.dy)
  }

  private func dot(_ a: CGVector, _ b: CGVector) -> CGFloat {
    a.dx * b.dx + a.dy * b.dy
  }

  private func countPushupBottomCoreJoints(in joints: [PushlyJointName: TrackedJoint]) -> Int {
    let core: [PushlyJointName] = [
      .leftShoulder, .rightShoulder,
      .leftElbow, .rightElbow,
      .leftWrist, .rightWrist,
      .leftHip, .rightHip
    ]
    return core.reduce(0) { partial, name in
      if joints[name]?.isRenderable == true {
        return partial + 1
      }
      return partial
    }
  }

  private func hasTorsoAnchor(in joints: [PushlyJointName: TrackedJoint]) -> Bool {
    let hasShoulders = joints[.leftShoulder]?.isRenderable == true || joints[.rightShoulder]?.isRenderable == true
    let hasHips = joints[.leftHip]?.isRenderable == true || joints[.rightHip]?.isRenderable == true
    return hasShoulders && (hasHips || lastBottomTorsoFrame != nil)
  }

  private func hasArmAnchor(in joints: [PushlyJointName: TrackedJoint]) -> Bool {
    let leftArm = joints[.leftShoulder]?.isRenderable == true
      && joints[.leftElbow]?.isRenderable == true
      && joints[.leftWrist]?.isRenderable == true
    let rightArm = joints[.rightShoulder]?.isRenderable == true
      && joints[.rightElbow]?.isRenderable == true
      && joints[.rightWrist]?.isRenderable == true
    return leftArm || rightArm
  }
}
#else
final class PushlyNativeCameraView: ExpoView {}
#endif
