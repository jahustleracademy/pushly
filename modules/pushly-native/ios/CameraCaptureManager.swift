import Foundation

#if os(iOS)
import AVFoundation

struct CameraTelemetry {
  let captureFPS: Double
  let dropRate: Double
  let droppedFrames: Int
  let droppedLateFrames: Int
  let droppedOutOfBuffers: Int
  let processingBacklog: Double
  let averageProcessingMs: Double
  let lowLightBoostSupported: Bool
  let lowLightBoostEnabled: Bool
  let exposureDurationSeconds: Double
}

final class CameraCaptureManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  let session = AVCaptureSession()
  let previewLayer = AVCaptureVideoPreviewLayer()

  var onFrame: ((CMSampleBuffer) -> Void)?
  var onAuthorizationIssue: ((String) -> Void)?
  var onTelemetry: ((CameraTelemetry) -> Void)?
  var onFrameRateChanged: ((Int32, Int32, String) -> Void)?
  var cameraPosition: AVCaptureDevice.Position = .front
  var isActive = true

  private let config: PushlyPoseConfig
  private let diagnostics: PoseDiagnostics?
  private let queue: DispatchQueue
  private let outputQueue: DispatchQueue
  private(set) var isConfigured = false

  private var activeDevice: AVCaptureDevice?
  private var frameCount = 0
  private var droppedFrames = 0
  private var droppedLateFrames = 0
  private var droppedOutOfBuffers = 0
  private var lastTelemetryAt = CACurrentMediaTime()
  private var targetCaptureFPS: Int32 = 30
  private var lastDropRate: Double = 0
  private var processingSampleCount = 0
  private var processingDurationTotalMs: Double = 0

  init(queue: DispatchQueue, outputQueue: DispatchQueue, config: PushlyPoseConfig, diagnostics: PoseDiagnostics? = nil) {
    self.queue = queue
    self.outputQueue = outputQueue
    self.config = config
    self.diagnostics = diagnostics
    super.init()
    previewLayer.session = session
    previewLayer.videoGravity = .resizeAspectFill
  }

  func setActive(_ active: Bool) {
    isActive = active
    updateCaptureState()
  }

  func rebuildForCameraPosition(_ position: AVCaptureDevice.Position) {
    cameraPosition = position
    isConfigured = false
    queue.async {
      self.session.stopRunning()
      self.configureIfNeeded()
      self.updateCaptureState()
    }
  }

  func adaptFrameRateForPipeline(processingFPS: Double, lowLightDetected: Bool) {
    queue.async {
      guard let activeDevice = self.activeDevice else { return }
      let target = self.computeTargetFPS(processingFPS: processingFPS, lowLightDetected: lowLightDetected)
      guard target != self.targetCaptureFPS else { return }
      let previous = self.targetCaptureFPS
      self.targetCaptureFPS = target
      self.applyFrameRate(target, device: activeDevice)
      let reason = self.frameRateChangeReason(processingFPS: processingFPS, lowLightDetected: lowLightDetected)
      self.onFrameRateChanged?(previous, target, reason)
    }
  }

  func configureIfNeeded() {
    guard !isConfigured else { return }

    session.beginConfiguration()
    session.sessionPreset = .high
    session.inputs.forEach { session.removeInput($0) }
    session.outputs.forEach { session.removeOutput($0) }

    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition) else {
      session.commitConfiguration()
      onAuthorizationIssue?("Keine passende Kamera gefunden.")
      return
    }

    activeDevice = device

    do {
      try device.lockForConfiguration()
      if device.isLowLightBoostSupported {
        device.automaticallyEnablesLowLightBoostWhenAvailable = true
      }
      if device.isFocusModeSupported(.continuousAutoFocus) {
        device.focusMode = .continuousAutoFocus
      }
      if device.isExposureModeSupported(.continuousAutoExposure) {
        device.exposureMode = .continuousAutoExposure
      }
      if device.isSmoothAutoFocusSupported {
        device.isSmoothAutoFocusEnabled = true
      }
      targetCaptureFPS = config.camera.maxCaptureFPS
      applyFrameRate(targetCaptureFPS, device: device)
      device.unlockForConfiguration()
    } catch {
      // Keep session alive even if advanced camera config fails.
    }

    do {
      let input = try AVCaptureDeviceInput(device: device)
      if session.canAddInput(input) {
        session.addInput(input)
      }
    } catch {
      session.commitConfiguration()
      onAuthorizationIssue?("Kamera konnte nicht initialisiert werden.")
      return
    }

    let output = AVCaptureVideoDataOutput()
    output.alwaysDiscardsLateVideoFrames = true
    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    output.setSampleBufferDelegate(self, queue: outputQueue)
    if session.canAddOutput(output) {
      session.addOutput(output)
    }

    if let connection = output.connection(with: .video) {
      configureVideoConnection(connection, isFrontCamera: cameraPosition == .front)
    }
    if let previewConnection = previewLayer.connection {
      configureVideoConnection(previewConnection, isFrontCamera: cameraPosition == .front)
    }

    session.commitConfiguration()
    isConfigured = true
  }

  func reportProcessingDuration(ms: Double) {
    queue.async {
      self.processingSampleCount += 1
      self.processingDurationTotalMs += ms
    }
  }

  func updateCaptureState() {
    guard AVCaptureDevice.authorizationStatus(for: .video) != .denied else {
      onAuthorizationIssue?("Kamera verweigert. Erlaube Zugriff für den Test.")
      return
    }

    queue.async {
      if !self.isConfigured {
        self.configureIfNeeded()
      }

      if self.isActive {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
          if !self.session.isRunning {
            self.session.startRunning()
          }
        case .notDetermined:
          AVCaptureDevice.requestAccess(for: .video) { granted in
            if granted {
              self.session.startRunning()
            } else {
              self.onAuthorizationIssue?("Pushly braucht Kamera, um echte Reps zu erkennen.")
            }
          }
        default:
          self.onAuthorizationIssue?("Kamera verweigert. Erlaube Zugriff für den Test.")
        }
      } else if self.session.isRunning {
        self.session.stopRunning()
      }
    }
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    frameCount += 1
    diagnostics?.recordFrameReceived()
    emitTelemetryIfNeeded()
    onFrame?(sampleBuffer)
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didDrop sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    droppedFrames += 1

    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
       let firstAttachment = attachments.first,
       let reason = firstAttachment[kCMSampleBufferAttachmentKey_DroppedFrameReason] as? String {
      diagnostics?.recordDroppedFrame(reason: reason)
      if reason == (kCMSampleBufferDroppedFrameReason_FrameWasLate as String) {
        droppedLateFrames += 1
      } else if reason == (kCMSampleBufferDroppedFrameReason_OutOfBuffers as String) {
        droppedOutOfBuffers += 1
      }
    } else {
      diagnostics?.recordDroppedFrame(reason: nil)
    }

    emitTelemetryIfNeeded()
  }

  private func emitTelemetryIfNeeded() {
    let now = CACurrentMediaTime()
    let dt = now - lastTelemetryAt
    guard dt >= 1.0 else { return }

    let produced = frameCount + droppedFrames
    let dropRate = produced > 0 ? Double(droppedFrames) / Double(produced) : 0
    lastDropRate = dropRate

    let telemetry = CameraTelemetry(
      captureFPS: Double(frameCount) / dt,
      dropRate: dropRate,
      droppedFrames: droppedFrames,
      droppedLateFrames: droppedLateFrames,
      droppedOutOfBuffers: droppedOutOfBuffers,
      processingBacklog: processingBacklog(),
      averageProcessingMs: averageProcessingDurationMs(),
      lowLightBoostSupported: activeDevice?.isLowLightBoostSupported ?? false,
      lowLightBoostEnabled: activeDevice?.isLowLightBoostEnabled ?? false,
      exposureDurationSeconds: activeDevice?.exposureDuration.seconds ?? 0
    )

    onTelemetry?(telemetry)
    diagnostics?.recordCameraTelemetry(telemetry)

    frameCount = 0
    droppedFrames = 0
    droppedLateFrames = 0
    droppedOutOfBuffers = 0
    processingSampleCount = 0
    processingDurationTotalMs = 0
    lastTelemetryAt = now
  }

  private func computeTargetFPS(processingFPS: Double, lowLightDetected: Bool) -> Int32 {
    let minFPS = configuredMinFPS()
    let maxFPS = configuredMaxFPS()

    var target = Int32(max(Double(minFPS), min(Double(maxFPS), processingFPS.rounded())))

    if lowLightDetected {
      target = min(target, config.camera.lowLightCaptureFPS)
    }

    if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
      target = min(target, config.camera.thermalThrottleFPS)
    }

    if lastDropRate >= config.camera.frameDropRateForThrottle {
      target = max(minFPS, target - 6)
    } else if lastDropRate <= config.camera.recoverFrameDropRate,
              !lowLightDetected,
              ProcessInfo.processInfo.thermalState != .serious,
              ProcessInfo.processInfo.thermalState != .critical {
      target = min(maxFPS, max(target, targetCaptureFPS + 1))
    }

    return max(minFPS, min(maxFPS, target))
  }

  private func frameRateChangeReason(processingFPS: Double, lowLightDetected: Bool) -> String {
    if lowLightDetected {
      return "lowLight"
    }
    if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
      return "thermal"
    }
    if lastDropRate >= config.camera.frameDropRateForThrottle {
      return "dropRateThrottle"
    }
    if processingFPS < Double(targetCaptureFPS) - 1 {
      return "processingPressure"
    }
    return "recovery"
  }

  private func applyFrameRate(_ fps: Int32, device: AVCaptureDevice) {
    do {
      try device.lockForConfiguration()
      let frameDuration = CMTime(value: 1, timescale: fps)
      device.activeVideoMinFrameDuration = frameDuration
      device.activeVideoMaxFrameDuration = frameDuration
      device.unlockForConfiguration()
    } catch {
      // Ignore frame-rate adaptation failures.
    }
  }

  private func configuredMinFPS() -> Int32 {
    config.camera.minCaptureFPS
  }

  private func configuredMaxFPS() -> Int32 {
    config.camera.maxCaptureFPS
  }

  private func configureVideoConnection(_ connection: AVCaptureConnection, isFrontCamera: Bool) {
    if connection.isVideoOrientationSupported {
      connection.videoOrientation = .portrait
    }
    if connection.isVideoMirroringSupported {
      connection.automaticallyAdjustsVideoMirroring = false
      connection.isVideoMirrored = isFrontCamera
    }
  }

  private func averageProcessingDurationMs() -> Double {
    guard processingSampleCount > 0 else { return 0 }
    return processingDurationTotalMs / Double(processingSampleCount)
  }

  private func processingBacklog() -> Double {
    let budgetMs = 1000.0 / Double(max(configuredMinFPS(), targetCaptureFPS))
    guard budgetMs > 0 else { return 0 }
    let overload = (averageProcessingDurationMs() - budgetMs) / budgetMs
    return min(1, max(0, overload))
  }
}
#endif
