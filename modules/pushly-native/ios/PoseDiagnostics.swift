import Foundation

#if os(iOS)
import AVFoundation
import os
import UIKit

enum PoseLogCategory: String {
  case camera
  case poseBackend
  case continuity
  case reacquire
  case renderer
  case bridge
  case diagnostics
  case performance
}

enum PoseSignpostStep {
  case cameraFrame
  case framePipeline
  case backendInference
  case reacquirePass
  case continuityUpdate
  case smoothingUpdate
  case qualityEvaluation
  case renderUpdate
}

struct PoseDiagnosticsFlags {
  let structuredLoggingEnabled: Bool
  let verboseFrameLoggingEnabled: Bool
  let verboseFrameSampleInterval: Int
  let debugOverlayEnabled: Bool
  let sessionExportEnabled: Bool
  let signpostsEnabled: Bool
  let cameraTelemetryEnabled: Bool
  let backendTelemetryEnabled: Bool
}

struct PoseEventRecord: Codable {
  let timestampISO8601: String
  let category: String
  let name: String
  let level: String
  let fields: [String: String]
}

struct PoseFrameSampleRecord: Codable {
  let frameIndex: Int
  let timestampSeconds: Double
  let backend: String
  let mode: String
  let trackingState: String
  let visibleJointCount: Int
  let upperBodyCoverage: Double
  let fullBodyCoverage: Double
  let handCoverage: Double
  let averageJointConfidence: Double
  let roi: String?
  let mirrored: Bool
  let orientation: UInt32
  let inferenceDurationMs: Double
  let pipelineDurationMs: Double
  let renderedJointCount: Int
  let inferredJointRatio: Double
}

private struct PoseRuntimeDistribution {
  var trackingUpperBodyDuration: Double = 0
  var trackingFullBodyDuration: Double = 0
  var reacquiringDuration: Double = 0
  var lostDuration: Double = 0

  var upperBodyModeDuration: Double = 0
  var fullBodyModeDuration: Double = 0
  var unknownModeDuration: Double = 0
}

struct PoseSessionSummary: Codable {
  let sessionID: String
  let appVersion: String
  let appBuild: String
  let deviceModel: String
  let iOSVersion: String
  let sessionStartISO8601: String
  let sessionEndISO8601: String
  let cameraPosition: String
  let mirrored: Bool
  let orientationValuesSeen: [UInt32]
  let activePoseBackend: String
  let fallbackAvailable: Bool
  let averageCameraFPS: Double
  let averageProcessingFPS: Double
  let frameCount: Int
  let processedFrameCount: Int
  let droppedFrameCount: Int
  let droppedFrameRate: Double
  let averageInferenceDurationMs: Double
  let averagePipelineDurationMs: Double
  let trackingUpperBodyDuration: Double
  let trackingFullBodyDuration: Double
  let reacquiringDuration: Double
  let lostDuration: Double
  let upperBodyModeDuration: Double
  let fullBodyModeDuration: Double
  let unknownModeDuration: Double
  let averageUpperBodyCoverage: Double
  let averageFullBodyCoverage: Double
  let averageHandCoverage: Double
  let averageReliability: Double
  let reacquireAttempts: Int
  let reacquireSourceCounts: [String: Int]
  let backendEmptyResultCount: Int
  let fallbackActivationCount: Int
  let lowLightActiveDuration: Double
  let lowLightActiveCount: Int
  let averageROIArea: Double
  let roiResetCount: Int
  let roiClampCount: Int
  let roiWidenCount: Int
}

struct PoseDebugExport: Codable {
  let summary: PoseSessionSummary
  let configSnapshot: [String: String]
  let recentEvents: [PoseEventRecord]
  let sampledFrames: [PoseFrameSampleRecord]
}

private struct RingBuffer<T> {
  private var items: [T] = []
  private let capacity: Int

  init(capacity: Int) {
    self.capacity = max(1, capacity)
  }

  mutating func append(_ item: T) {
    if items.count >= capacity {
      items.removeFirst(items.count - capacity + 1)
    }
    items.append(item)
  }

  func all() -> [T] { items }
}

private struct PoseSignpostToken {
  let state: OSSignpostIntervalState
  let step: PoseSignpostStep
}

final class PoseDiagnostics {
  private let flags: PoseDiagnosticsFlags
  private let queue = DispatchQueue(label: "com.pushly.pose.diagnostics", qos: .utility)
  private let subsystem = "com.pushly.pose"
  private let signposter = OSSignposter(logger: Logger(subsystem: "com.pushly.pose", category: PoseLogCategory.performance.rawValue))
  private let isoFormatter = ISO8601DateFormatter()
  private var events: RingBuffer<PoseEventRecord>
  private var sampledFrames: RingBuffer<PoseFrameSampleRecord>

  private let sessionID = UUID().uuidString
  private let sessionStart = Date()
  private var sessionEnd = Date()
  private var orientationValuesSeen = Set<UInt32>()

  private var activeBackend: PoseBackendKind = .visionFallback
  private var fallbackAvailable = false
  private var cameraPosition = "front"
  private var mirrored = true

  private var frameCount = 0
  private var processedFrameCount = 0
  private var droppedFrameCount = 0
  private var totalCameraFPS = 0.0
  private var cameraFPSSamples = 0
  private var totalProcessingFPS = 0.0
  private var processingFPSSamples = 0

  private var totalInferenceMs = 0.0
  private var inferenceSamples = 0
  private var totalPipelineMs = 0.0
  private var pipelineSamples = 0

  private var totalUpperCoverage = 0.0
  private var totalFullCoverage = 0.0
  private var totalHandCoverage = 0.0
  private var totalReliability = 0.0
  private var coverageSamples = 0

  private var reacquireAttempts = 0
  private var reacquireSourceCounts: [String: Int] = [:]
  private var backendEmptyResultCount = 0
  private var fallbackActivationCount = 0

  private var lowLightActiveCount = 0
  private var lowLightActiveDuration = 0.0
  private var wasLowLight = false
  private var lowLightSegmentStartedAt: CFTimeInterval?

  private var totalROIArea = 0.0
  private var roiSamples = 0
  private var roiResetCount = 0
  private var roiClampCount = 0
  private var roiWidenCount = 0
  private var lastROI: CGRect?

  private var distribution = PoseRuntimeDistribution()
  private var lastState: BodyState = .lost
  private var lastMode: BodyTrackingMode = .unknown
  private var lastRuntimeSampleAt: CFTimeInterval?

  init(config: PushlyPoseConfig) {
    flags = PoseDiagnosticsFlags(
      structuredLoggingEnabled: config.pipeline.structuredLoggingEnabled,
      verboseFrameLoggingEnabled: config.pipeline.verboseFrameLoggingEnabled,
      verboseFrameSampleInterval: config.pipeline.verboseFrameSampleInterval,
      debugOverlayEnabled: config.pipeline.debugOverlayEnabled,
      sessionExportEnabled: config.pipeline.sessionExportEnabled,
      signpostsEnabled: config.pipeline.signpostsEnabled,
      cameraTelemetryEnabled: config.pipeline.cameraTelemetryEnabled,
      backendTelemetryEnabled: config.pipeline.backendTelemetryEnabled
    )
    events = RingBuffer(capacity: config.pipeline.maxDiagnosticEventBuffer)
    sampledFrames = RingBuffer(capacity: config.pipeline.maxDiagnosticFrameBuffer)
  }

  var overlayEnabledByDefault: Bool { flags.debugOverlayEnabled }
  var sessionIdentifier: String { sessionID }

  func beginSession(cameraPosition: AVCaptureDevice.Position, mirrored: Bool, activeBackend: PoseBackendKind, fallbackAvailable: Bool) {
    queue.async {
      self.cameraPosition = cameraPosition == .front ? "front" : "back"
      self.mirrored = mirrored
      self.activeBackend = activeBackend
      self.fallbackAvailable = fallbackAvailable
      self.log(category: .diagnostics, level: "info", name: "tracking_start", fields: [
        "sessionID": self.sessionID,
        "cameraPosition": self.cameraPosition,
        "mirrored": "\(mirrored)",
        "backend": activeBackend.rawValue
      ])
    }
  }

  func endSession(reason: String) {
    queue.async {
      self.sessionEnd = Date()
      self.flushRuntimeDurations(now: CACurrentMediaTime())
      self.closeLowLightSegment(now: CACurrentMediaTime())
      self.log(category: .diagnostics, level: "info", name: "tracking_stop", fields: ["reason": reason, "sessionID": self.sessionID])
    }
  }

  func recordFrameReceived() {
    queue.async { self.frameCount += 1 }
  }

  func recordDroppedFrame(reason: String?) {
    queue.async {
      self.droppedFrameCount += 1
      if self.droppedFrameCount % 24 == 0 {
        self.log(category: .camera, level: "warning", name: "camera_dropped_frames", fields: [
          "droppedFrames": "\(self.droppedFrameCount)",
          "reason": reason ?? "unknown"
        ])
      }
    }
  }

  func recordCameraTelemetry(_ telemetry: CameraTelemetry) {
    guard flags.cameraTelemetryEnabled else { return }
    queue.async {
      self.totalCameraFPS += telemetry.captureFPS
      self.cameraFPSSamples += 1
      let dropRate = telemetry.dropRate
      if dropRate >= 0.2 {
        self.log(category: .camera, level: "warning", name: "camera_drop_rate_warning", fields: [
          "dropRate": Self.f2(dropRate),
          "captureFPS": Self.f2(telemetry.captureFPS),
          "processingBacklog": Self.f2(telemetry.processingBacklog)
        ])
      }
      if telemetry.processingBacklog >= 0.35 {
        self.log(category: .performance, level: "warning", name: "processing_overload_warning", fields: [
          "processingBacklog": Self.f2(telemetry.processingBacklog),
          "avgProcessingMs": Self.f2(telemetry.averageProcessingMs)
        ])
      }
    }
  }

  func recordCameraFrameRateChanged(from oldFPS: Int32, to newFPS: Int32, reason: String) {
    queue.async {
      self.log(category: .camera, level: "info", name: "camera_fps_changed", fields: [
        "fromFPS": "\(oldFPS)",
        "toFPS": "\(newFPS)",
        "reason": reason
      ])
    }
  }

  func recordProcessingFPS(_ fps: Double) {
    queue.async {
      self.totalProcessingFPS += fps
      self.processingFPSSamples += 1
    }
  }

  func recordBackendInitialized(kind: PoseBackendKind, available: Bool, details: [String: String] = [:]) {
    queue.async {
      var fields = details
      fields["backend"] = kind.rawValue
      fields["available"] = "\(available)"
      self.log(category: .poseBackend, level: "info", name: "backend_initialized", fields: fields)
    }
  }

  func recordBackendUnavailable(kind: PoseBackendKind, reason: String) {
    queue.async {
      self.log(category: .poseBackend, level: "error", name: "backend_unavailable", fields: [
        "backend": kind.rawValue,
        "reason": reason
      ])
    }
  }

  func recordBackendSwitch(from: PoseBackendKind, to: PoseBackendKind, reason: String) {
    queue.async {
      self.activeBackend = to
      self.fallbackActivationCount += 1
      self.log(category: .poseBackend, level: "warning", name: "backend_switched", fields: [
        "from": from.rawValue,
        "to": to.rawValue,
        "reason": reason
      ])
    }
  }

  func recordOrientationAndMirror(orientation: CGImagePropertyOrientation, mirrored: Bool, previewSize: CGSize, bufferSize: CGSize) {
    queue.async {
      self.orientationValuesSeen.insert(orientation.rawValue)
      if self.mirrored != mirrored {
        self.log(category: .diagnostics, level: "info", name: "mirroring_changed", fields: [
          "mirrored": "\(mirrored)"
        ])
      }
      self.mirrored = mirrored
      self.log(category: .diagnostics, level: "debug", name: "geometry_state", fields: [
        "orientation": "\(orientation.rawValue)",
        "mirrored": "\(mirrored)",
        "preview": "\(Int(previewSize.width))x\(Int(previewSize.height))",
        "buffer": "\(Int(bufferSize.width))x\(Int(bufferSize.height))"
      ])
    }
  }

  func recordReacquireAttempt(source: ReacquireSource) {
    queue.async {
      self.reacquireAttempts += 1
      self.reacquireSourceCounts[source.rawValue, default: 0] += 1
      self.log(category: .reacquire, level: "info", name: "reacquire_begin", fields: [
        "source": source.rawValue
      ])
    }
  }

  func recordReacquireEnd(success: Bool, source: ReacquireSource) {
    queue.async {
      self.log(category: .reacquire, level: success ? "info" : "warning", name: "reacquire_end", fields: [
        "source": source.rawValue,
        "success": "\(success)"
      ])
    }
  }

  func recordROI(_ roi: CGRect?, source: ReacquireSource, wasClamped: Bool) {
    queue.async {
      defer { self.lastROI = roi }
      guard let roi else {
        if self.lastROI != nil {
          self.roiResetCount += 1
          self.log(category: .reacquire, level: "info", name: "roi_reset", fields: [:])
        }
        return
      }
      let area = max(0, min(1, Double(roi.width * roi.height)))
      self.totalROIArea += area
      self.roiSamples += 1

      if wasClamped {
        self.roiClampCount += 1
        self.log(category: .reacquire, level: "warning", name: "roi_clamped", fields: [
          "roi": Self.roiString(roi),
          "source": source.rawValue
        ])
      }

      if let lastROI = self.lastROI {
        let lastArea = max(0.0001, Double(lastROI.width * lastROI.height))
        if area / lastArea > 1.25 {
          self.roiWidenCount += 1
        }
      }
    }
  }

  func recordModeTransition(from: BodyTrackingMode, to: BodyTrackingMode) {
    guard from != to else { return }
    queue.async {
      self.log(category: .continuity, level: "info", name: "mode_transition", fields: [
        "from": from.rawValue,
        "to": to.rawValue
      ])
    }
  }

  func recordTrackingStateTransition(from: BodyState, to: BodyState) {
    guard from != to else { return }
    queue.async {
      self.log(category: .continuity, level: "info", name: "tracking_state_transition", fields: [
        "from": from.rawValue,
        "to": to.rawValue
      ])
    }
  }

  func recordLowLightChanged(active: Bool) {
    queue.async {
      let now = CACurrentMediaTime()
      if active && !self.wasLowLight {
        self.lowLightActiveCount += 1
        self.lowLightSegmentStartedAt = now
      } else if !active && self.wasLowLight {
        self.closeLowLightSegment(now: now)
      }
      self.wasLowLight = active
      self.log(category: .camera, level: "info", name: "low_light_state_changed", fields: ["active": "\(active)"])
    }
  }

  func recordBackendResultEmpty(_ backend: PoseBackendKind, consecutive: Int) {
    queue.async {
      self.backendEmptyResultCount += 1
      if consecutive >= 6 {
        self.log(category: .poseBackend, level: "warning", name: "backend_empty_repeated", fields: [
          "backend": backend.rawValue,
          "consecutive": "\(consecutive)"
        ])
      }
    }
  }

  func recordProcessedFrame(
    frameIndex: Int,
    timestamp: TimeInterval,
    backend: PoseBackendKind,
    mode: BodyTrackingMode,
    trackingState: BodyState,
    visibleJointCount: Int,
    upperBodyCoverage: Double,
    fullBodyCoverage: Double,
    handCoverage: Double,
    averageJointConfidence: Double,
    reliability: Double,
    roi: CGRect?,
    mirrored: Bool,
    orientation: CGImagePropertyOrientation,
    inferenceDurationMs: Double,
    pipelineDurationMs: Double,
    renderedJointCount: Int,
    inferredJointRatio: Double
  ) {
    queue.async {
      self.processedFrameCount += 1
      self.totalInferenceMs += inferenceDurationMs
      self.inferenceSamples += 1
      self.totalPipelineMs += pipelineDurationMs
      self.pipelineSamples += 1
      self.totalUpperCoverage += upperBodyCoverage
      self.totalFullCoverage += fullBodyCoverage
      self.totalHandCoverage += handCoverage
      self.totalReliability += reliability
      self.coverageSamples += 1
      self.orientationValuesSeen.insert(orientation.rawValue)

      self.updateRuntimeDistribution(mode: mode, trackingState: trackingState, now: timestamp)

      if self.flags.verboseFrameLoggingEnabled,
         frameIndex % max(1, self.flags.verboseFrameSampleInterval) == 0 {
        self.sampledFrames.append(
          PoseFrameSampleRecord(
            frameIndex: frameIndex,
            timestampSeconds: timestamp,
            backend: backend.rawValue,
            mode: mode.rawValue,
            trackingState: trackingState.rawValue,
            visibleJointCount: visibleJointCount,
            upperBodyCoverage: upperBodyCoverage,
            fullBodyCoverage: fullBodyCoverage,
            handCoverage: handCoverage,
            averageJointConfidence: averageJointConfidence,
            roi: roi.map(Self.roiString),
            mirrored: mirrored,
            orientation: orientation.rawValue,
            inferenceDurationMs: inferenceDurationMs,
            pipelineDurationMs: pipelineDurationMs,
            renderedJointCount: renderedJointCount,
            inferredJointRatio: inferredJointRatio
          )
        )
      }
    }
  }

  func beginSignpost(_ step: PoseSignpostStep) -> Any? {
    guard flags.signpostsEnabled else { return nil }
    if #available(iOS 15.0, *) {
      let state = signposter.beginInterval(name(for: step))
      return PoseSignpostToken(state: state, step: step)
    }
    return nil
  }

  func endSignpost(_ token: Any?) {
    guard flags.signpostsEnabled else { return }
    guard #available(iOS 15.0, *) else { return }
    guard let token = token as? PoseSignpostToken else { return }
    signposter.endInterval(name(for: token.step), token.state)
  }

  func exportToDisk(configSnapshot: [String: String], completion: @escaping (Result<URL, Error>) -> Void) {
    guard flags.sessionExportEnabled else {
      completion(.failure(NSError(domain: "PushlyPoseDiagnostics", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Session export disabled by config"])))
      return
    }

    queue.async {
      self.sessionEnd = Date()
      self.flushRuntimeDurations(now: CACurrentMediaTime())
      self.closeLowLightSegment(now: CACurrentMediaTime())

      let exportPayload = PoseDebugExport(
        summary: self.makeSummary(),
        configSnapshot: configSnapshot,
        recentEvents: self.events.all(),
        sampledFrames: self.sampledFrames.all()
      )

      do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(exportPayload)

        let root = try self.ensureExportDirectory()
        let fileURL = root.appendingPathComponent("pose-debug-\(self.sessionID).json")
        try data.write(to: fileURL, options: .atomic)

        self.log(category: .diagnostics, level: "info", name: "session_exported", fields: ["path": fileURL.path])
        completion(.success(fileURL))
      } catch {
        completion(.failure(error))
      }
    }
  }

  private func ensureExportDirectory() throws -> URL {
    let manager = FileManager.default
    let root = manager.temporaryDirectory
      .appendingPathComponent("pushly-debug", isDirectory: true)
      .appendingPathComponent("pose-sessions", isDirectory: true)
    if !manager.fileExists(atPath: root.path) {
      try manager.createDirectory(at: root, withIntermediateDirectories: true)
    }
    return root
  }

  private func closeLowLightSegment(now: CFTimeInterval) {
    guard let start = lowLightSegmentStartedAt else { return }
    lowLightActiveDuration += max(0, now - start)
    lowLightSegmentStartedAt = nil
  }

  private func updateRuntimeDistribution(mode: BodyTrackingMode, trackingState: BodyState, now: TimeInterval) {
    let current = now > 0 ? now : CACurrentMediaTime()
    defer {
      lastRuntimeSampleAt = current
      lastState = trackingState
      lastMode = mode
    }
    guard let lastAt = lastRuntimeSampleAt else { return }
    let dt = max(0, current - lastAt)

    switch lastState {
    case .trackingUpperBody:
      distribution.trackingUpperBodyDuration += dt
    case .trackingFullBody:
      distribution.trackingFullBodyDuration += dt
    case .reacquiring:
      distribution.reacquiringDuration += dt
    case .lost:
      distribution.lostDuration += dt
    }

    switch lastMode {
    case .upperBody:
      distribution.upperBodyModeDuration += dt
    case .fullBody:
      distribution.fullBodyModeDuration += dt
    case .unknown:
      distribution.unknownModeDuration += dt
    }
  }

  private func flushRuntimeDurations(now: CFTimeInterval) {
    let time = now > 0 ? now : CACurrentMediaTime()
    if let lastAt = lastRuntimeSampleAt {
      updateRuntimeDistribution(mode: lastMode, trackingState: lastState, now: time)
      lastRuntimeSampleAt = lastAt
    }
  }

  private func makeSummary() -> PoseSessionSummary {
    let dropRate = frameCount > 0 ? Double(droppedFrameCount) / Double(frameCount + droppedFrameCount) : 0
    return PoseSessionSummary(
      sessionID: sessionID,
      appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
      appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
      deviceModel: Self.deviceModel(),
      iOSVersion: UIDevice.current.systemVersion,
      sessionStartISO8601: isoFormatter.string(from: sessionStart),
      sessionEndISO8601: isoFormatter.string(from: sessionEnd),
      cameraPosition: cameraPosition,
      mirrored: mirrored,
      orientationValuesSeen: orientationValuesSeen.sorted(),
      activePoseBackend: activeBackend.rawValue,
      fallbackAvailable: fallbackAvailable,
      averageCameraFPS: cameraFPSSamples > 0 ? totalCameraFPS / Double(cameraFPSSamples) : 0,
      averageProcessingFPS: processingFPSSamples > 0 ? totalProcessingFPS / Double(processingFPSSamples) : 0,
      frameCount: frameCount,
      processedFrameCount: processedFrameCount,
      droppedFrameCount: droppedFrameCount,
      droppedFrameRate: dropRate,
      averageInferenceDurationMs: inferenceSamples > 0 ? totalInferenceMs / Double(inferenceSamples) : 0,
      averagePipelineDurationMs: pipelineSamples > 0 ? totalPipelineMs / Double(pipelineSamples) : 0,
      trackingUpperBodyDuration: distribution.trackingUpperBodyDuration,
      trackingFullBodyDuration: distribution.trackingFullBodyDuration,
      reacquiringDuration: distribution.reacquiringDuration,
      lostDuration: distribution.lostDuration,
      upperBodyModeDuration: distribution.upperBodyModeDuration,
      fullBodyModeDuration: distribution.fullBodyModeDuration,
      unknownModeDuration: distribution.unknownModeDuration,
      averageUpperBodyCoverage: coverageSamples > 0 ? totalUpperCoverage / Double(coverageSamples) : 0,
      averageFullBodyCoverage: coverageSamples > 0 ? totalFullCoverage / Double(coverageSamples) : 0,
      averageHandCoverage: coverageSamples > 0 ? totalHandCoverage / Double(coverageSamples) : 0,
      averageReliability: coverageSamples > 0 ? totalReliability / Double(coverageSamples) : 0,
      reacquireAttempts: reacquireAttempts,
      reacquireSourceCounts: reacquireSourceCounts,
      backendEmptyResultCount: backendEmptyResultCount,
      fallbackActivationCount: fallbackActivationCount,
      lowLightActiveDuration: lowLightActiveDuration,
      lowLightActiveCount: lowLightActiveCount,
      averageROIArea: roiSamples > 0 ? totalROIArea / Double(roiSamples) : 0,
      roiResetCount: roiResetCount,
      roiClampCount: roiClampCount,
      roiWidenCount: roiWidenCount
    )
  }

  private func log(category: PoseLogCategory, level: String, name: String, fields: [String: String]) {
    let event = PoseEventRecord(
      timestampISO8601: isoFormatter.string(from: Date()),
      category: category.rawValue,
      name: name,
      level: level,
      fields: fields
    )
    events.append(event)
    guard flags.structuredLoggingEnabled else { return }
    let logger = Logger(subsystem: subsystem, category: category.rawValue)
    let payload = fields
      .sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value)" }
      .joined(separator: " ")
    switch level {
    case "error":
      logger.error("\(name, privacy: .public) \(payload, privacy: .public)")
    case "warning":
      logger.warning("\(name, privacy: .public) \(payload, privacy: .public)")
    case "debug":
      logger.debug("\(name, privacy: .public) \(payload, privacy: .public)")
    default:
      logger.info("\(name, privacy: .public) \(payload, privacy: .public)")
    }
  }

  @available(iOS 15.0, *)
  private func name(for step: PoseSignpostStep) -> StaticString {
    switch step {
    case .cameraFrame:
      return "camera_frame_receipt"
    case .framePipeline:
      return "frame_pipeline"
    case .backendInference:
      return "backend_inference"
    case .reacquirePass:
      return "reacquire_pass"
    case .continuityUpdate:
      return "continuity_update"
    case .smoothingUpdate:
      return "temporal_smoothing_update"
    case .qualityEvaluation:
      return "quality_evaluation"
    case .renderUpdate:
      return "render_update"
    }
  }

  private static func roiString(_ roi: CGRect) -> String {
    String(format: "%.3f,%.3f,%.3f,%.3f", roi.minX, roi.minY, roi.width, roi.height)
  }

  private static func f2(_ value: Double) -> String {
    String(format: "%.2f", value)
  }

  private static func deviceModel() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    return withUnsafePointer(to: &systemInfo.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: 1) {
        String(cString: $0)
      }
    }
  }
}
#endif
