import ExpoModulesCore
#if os(iOS)
import AVFoundation
import UIKit

final class PushlyNativeCameraView: ExpoView {
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
        diagnostics.beginSession(
          cameraPosition: cameraPosition,
          mirrored: cameraPosition == .front,
          activeBackend: poseCoordinator.activeBackend,
          fallbackAvailable: poseCoordinator.isFallbackAvailable
        )
      } else {
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

    skeletonRenderer = SkeletonRenderer(containerLayer: layer)

    feedbackLabel.textColor = .white
    feedbackLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    feedbackLabel.numberOfLines = 2
    feedbackLabel.textAlignment = .center
    feedbackLabel.text = "Kalibriere dich im Frame"
    addSubview(feedbackLabel)

    debugLabel.textColor = UIColor(red: 186 / 255, green: 250 / 255, blue: 32 / 255, alpha: 0.95)
    debugLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
    debugLabel.numberOfLines = 12
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
        temporalTracker.hardReset()
      }

      let now = Date().timeIntervalSince1970
      let smoothingSignpost = diagnostics.beginSignpost(.smoothingUpdate)
      let tracked = temporalTracker.update(
        measured: processed.measured,
        lowLightDetected: processed.lowLightDetected,
        roiHint: continuityTracker.lastStableROI,
        frameTimestamp: now
      )
      diagnostics.endSignpost(smoothingSignpost)

      let allowsRendering = continuityTracker.poseState.allowsRendering
      let jointsForOutput = (allowsRendering && tracked.count >= 3) ? tracked : [:]

      let avgConfidence = averageConfidence(of: jointsForOutput)
      let avgVelocity = averageVelocityMagnitude(of: jointsForOutput)
      let qualitySignpost = diagnostics.beginSignpost(.qualityEvaluation)
      let quality = qualityEvaluator.evaluate(
        joints: jointsForOutput,
        lowLightDetected: processed.lowLightDetected,
        trackingState: continuityTracker.state,
        poseState: continuityTracker.poseState,
        poseMode: continuityTracker.bodyMode,
        modeConfidence: continuityTracker.modeConfidence,
        roiCoverage: continuityTracker.roiCoverage,
        coverageHint: continuityTracker.coverage
      )
      diagnostics.endSignpost(qualitySignpost)

      let rep = repDetector.update(joints: jointsForOutput, quality: quality, repTarget: repTarget)
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
        self.renderJoints = jointsForOutput
        self.renderState = self.continuityTracker.poseState
        self.renderMode = self.continuityTracker.bodyMode
        self.renderAvgVelocity = avgVelocity
        self.renderJointCount = jointsForOutput.count
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
        renderedJointCount: jointsForOutput.count,
        inferredJointRatio: quality.inferredJointRatio
      )

      emitPoseFrame(
        joints: jointsForOutput,
        quality: quality,
        rep: rep,
        instruction: latestInstructionText,
        lowLightDetected: processed.lowLightDetected,
        backend: processed.backend
      )
    } catch {
      diagnostics.recordBackendUnavailable(kind: renderBackend, reason: "process_frame_failed")
      emitFallbackFrame()
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
    case "mediapipe", "mlkit":
      poseCoordinator.setPreferenceOverride(.mediapipe)
    default:
      poseCoordinator.setPreferenceOverride(nil)
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

  private func emitFallbackFrame() {
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
    }

    let fallbackInstruction = latestLowLight
      ? "Licht ist niedrig. Dreh dich leicht zur Lichtquelle."
      : "Erkennung wird vorbereitet."
    latestInstructionText = fallbackInstruction

    let now = Date()
    guard now.timeIntervalSince(lastEmit) >= config.pipeline.minEmitInterval else { return }
    lastEmit = now
    updateFeedbackLabel(fallbackInstruction)

    onPoseFrame([
      "bodyDetected": false,
      "confidence": 0,
      "formScore": 0,
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
      "poseBackend": renderBackend.rawValue,
      "reacquireSource": ReacquireSource.none.rawValue,
      "visibleJointCount": 0,
      "mirrored": latestMirrored,
      "orientation": latestOrientation.rawValue,
      "debugSessionID": diagnostics.sessionIdentifier,
      "upperBodyCoverage": 0,
      "fullBodyCoverage": 0,
      "handCoverage": 0,
      "cameraFPS": latestCameraTelemetry?.captureFPS,
      "cameraProcessingBacklog": latestCameraTelemetry?.processingBacklog,
      "cameraAverageProcessingMs": latestCameraTelemetry?.averageProcessingMs,
      "processingFPS": currentPoseFPS
    ])
  }

  private func emitPoseFrame(
    joints: [PushlyJointName: TrackedJoint],
    quality: TrackingQuality,
    rep: RepDetectionOutput,
    instruction: String,
    lowLightDetected: Bool,
    backend: PoseBackendKind
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
      visibleJointCount: joints.count
    )

    updateFeedbackLabel(instruction)
    onPoseFrame(payload)
  }

  private func updateFeedbackLabel(_ text: String) {
    DispatchQueue.main.async {
      self.feedbackLabel.text = text
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
    let canRender = showSkeleton && state.allowsRendering && joints.count >= 3
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
    debugLabel.text = """
    state: \(state.rawValue) mode:\(mode.rawValue)
    backend: \(renderBackend.rawValue) reacq:\(continuityTracker.lastReacquireSource.rawValue)
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

  private func averageVelocityMagnitude(of joints: [PushlyJointName: TrackedJoint]) -> Double {
    guard !joints.isEmpty else { return 0 }
    let total = joints.values.map { sqrt(Double($0.velocity.dx * $0.velocity.dx + $0.velocity.dy * $0.velocity.dy)) }.reduce(0, +)
    return total / Double(joints.count)
  }
}
#else
final class PushlyNativeCameraView: ExpoView {}
#endif
