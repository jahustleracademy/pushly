#if os(iOS)
#if canImport(XCTest)
import XCTest
import AVFoundation
@testable import PushlyNative

final class PoseCoordinateConverterTests: XCTestCase {
  func testClampNormalizedROI() {
    let roi = PoseCoordinateConverter.clampNormalizedROI(CGRect(x: -0.2, y: 0.9, width: 1.4, height: 0.4), minSize: 0.08)
    XCTAssertGreaterThanOrEqual(roi.minX, 0)
    XCTAssertLessThanOrEqual(roi.maxX, 1)
    XCTAssertGreaterThanOrEqual(roi.minY, 0)
    XCTAssertLessThanOrEqual(roi.maxY, 1)
    XCTAssertGreaterThanOrEqual(roi.width, 0.08)
    XCTAssertGreaterThanOrEqual(roi.height, 0.08)
  }

  func testMirroredPixelToVisionROI() {
    let roi = PoseCoordinateConverter.pixelBufferRectToVisionROI(
      pixelBufferRect: CGRect(x: 200, y: 100, width: 400, height: 600),
      pixelBufferSize: CGSize(width: 1000, height: 1000),
      orientation: .leftMirrored,
      mirrored: true
    )
    XCTAssertGreaterThan(roi.width, 0)
    XCTAssertGreaterThan(roi.height, 0)
  }

  func testCanonicalPointFromMediaPipeMirroring() {
    let raw = CGPoint(x: 0.2, y: 0.3)
    let nonMirrored = PoseCoordinateConverter.canonicalPointFromMediaPipe(raw, mirrored: false)
    let mirrored = PoseCoordinateConverter.canonicalPointFromMediaPipe(raw, mirrored: true)

    XCTAssertEqual(nonMirrored.y, 0.7, accuracy: 0.0001)
    XCTAssertEqual(mirrored.x, 0.8, accuracy: 0.0001)
    XCTAssertEqual(mirrored.y, nonMirrored.y, accuracy: 0.0001)
  }

  func testPreviewProjectionRespectsAspectFillCrop() {
    let projection = PoseCoordinateConverter.ProjectionContext(
      previewBounds: CGRect(x: 0, y: 0, width: 300, height: 600),
      pixelBufferSize: CGSize(width: 1920, height: 1080),
      videoGravity: .resizeAspectFill,
      orientation: .right,
      isMirrored: false,
      canonicalAlreadyMirrored: true
    )

    let center = PoseCoordinateConverter.pointFromCanonical(CGPoint(x: 0.5, y: 0.5), projection: projection)
    XCTAssertEqual(center.x, 150, accuracy: 0.01)
    XCTAssertEqual(center.y, 300, accuracy: 0.01)

    let leftEdge = PoseCoordinateConverter.pointFromCanonical(CGPoint(x: 0.0, y: 0.5), projection: projection)
    XCTAssertLessThan(leftEdge.x, 0) // Expected cropped content outside visible viewport.
  }

  func testProjectionMirrorsOnlyWhenCanonicalNotMirrored() {
    let projection = PoseCoordinateConverter.ProjectionContext(
      previewBounds: CGRect(x: 0, y: 0, width: 300, height: 600),
      pixelBufferSize: CGSize(width: 1920, height: 1080),
      videoGravity: .resizeAspectFill,
      orientation: .right,
      isMirrored: true,
      canonicalAlreadyMirrored: false
    )

    let leftCanonical = PoseCoordinateConverter.pointFromCanonical(CGPoint(x: 0.1, y: 0.5), projection: projection)
    let rightCanonical = PoseCoordinateConverter.pointFromCanonical(CGPoint(x: 0.9, y: 0.5), projection: projection)
    XCTAssertGreaterThan(leftCanonical.x, rightCanonical.x)
  }

  func testCanonicalVisionROIConversionMirroredLeft() {
    let canonical = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5)
    let vision = PoseCoordinateConverter.visionROIFromCanonical(canonical, orientation: .leftMirrored, mirrored: true)
    XCTAssertGreaterThan(vision.width, 0)
    XCTAssertGreaterThan(vision.height, 0)
    XCTAssertGreaterThanOrEqual(vision.minX, 0)
    XCTAssertGreaterThanOrEqual(vision.minY, 0)
    XCTAssertLessThanOrEqual(vision.maxX, 1)
    XCTAssertLessThanOrEqual(vision.maxY, 1)
  }
}

final class TrackContinuityManagerTests: XCTestCase {
  func testUpperBodyOnlyStaysTracked() {
    let config = PushlyPoseConfig()
    let manager = TrackContinuityManager(config: config)

    let now = CACurrentMediaTime()
    manager.update(measured: makeUpperBody(), modeHint: .upperBody, modeHintConfidence: 0.8, coverage: nil, now: now, reacquire: nil)
    manager.update(measured: makeUpperBody(), modeHint: .upperBody, modeHintConfidence: 0.8, coverage: nil, now: now + 0.03, reacquire: nil)

    XCTAssertEqual(manager.poseState, .trackingUpperBody)
    XCTAssertNotEqual(manager.poseState, .lost)
  }

  func testFullBodyModeTransitionAndDowngradeToUpper() {
    let config = PushlyPoseConfig()
    let manager = TrackContinuityManager(config: config)

    let now = CACurrentMediaTime()
    for i in 0..<5 {
      manager.update(measured: makeFullBody(), modeHint: .fullBody, modeHintConfidence: 0.9, coverage: nil, now: now + Double(i) * 0.03, reacquire: nil)
    }
    XCTAssertEqual(manager.poseState, .trackingFullBody)
    XCTAssertEqual(manager.bodyMode, .fullBody)

    for i in 5..<11 {
      manager.update(measured: makeUpperBody(), modeHint: .upperBody, modeHintConfidence: 0.8, coverage: nil, now: now + Double(i) * 0.03, reacquire: nil)
    }
    XCTAssertEqual(manager.poseState, .trackingUpperBody)
    XCTAssertEqual(manager.bodyMode, .upperBody)
  }

  func testAmbiguousThenLost() {
    let config = PushlyPoseConfig()
    let manager = TrackContinuityManager(config: config)

    let now = CACurrentMediaTime()
    let ambiguous: [PushlyJointName: PoseJointMeasurement] = [
      .nose: PoseJointMeasurement(name: .nose, point: CGPoint(x: 0.5, y: 0.8), confidence: 0.9, backend: .mediapipe),
      .leftShoulder: PoseJointMeasurement(name: .leftShoulder, point: CGPoint(x: 0.45, y: 0.7), confidence: 0.9, backend: .mediapipe)
    ]

    manager.update(measured: ambiguous, modeHint: nil, modeHintConfidence: nil, coverage: nil, now: now, reacquire: nil)
    XCTAssertEqual(manager.poseState, .reacquiring)

    for i in 1...7 {
      manager.update(measured: [:], modeHint: nil, modeHintConfidence: nil, coverage: nil, now: now + Double(i) * 0.06, reacquire: nil)
    }

    XCTAssertEqual(manager.poseState, .lost)
  }

  private func makeUpperBody() -> [PushlyJointName: PoseJointMeasurement] {
    [
      .nose: PoseJointMeasurement(name: .nose, point: CGPoint(x: 0.5, y: 0.8), confidence: 0.8, backend: .mediapipe),
      .leftShoulder: PoseJointMeasurement(name: .leftShoulder, point: CGPoint(x: 0.4, y: 0.7), confidence: 0.8, backend: .mediapipe),
      .rightShoulder: PoseJointMeasurement(name: .rightShoulder, point: CGPoint(x: 0.6, y: 0.7), confidence: 0.8, backend: .mediapipe),
      .leftElbow: PoseJointMeasurement(name: .leftElbow, point: CGPoint(x: 0.35, y: 0.6), confidence: 0.8, backend: .mediapipe),
      .rightElbow: PoseJointMeasurement(name: .rightElbow, point: CGPoint(x: 0.65, y: 0.6), confidence: 0.8, backend: .mediapipe),
      .leftWrist: PoseJointMeasurement(name: .leftWrist, point: CGPoint(x: 0.32, y: 0.52), confidence: 0.8, backend: .mediapipe),
      .rightWrist: PoseJointMeasurement(name: .rightWrist, point: CGPoint(x: 0.68, y: 0.52), confidence: 0.8, backend: .mediapipe)
    ]
  }

  private func makeFullBody() -> [PushlyJointName: PoseJointMeasurement] {
    var joints = makeUpperBody()
    joints[.leftHip] = PoseJointMeasurement(name: .leftHip, point: CGPoint(x: 0.45, y: 0.5), confidence: 0.8, backend: .mediapipe)
    joints[.rightHip] = PoseJointMeasurement(name: .rightHip, point: CGPoint(x: 0.55, y: 0.5), confidence: 0.8, backend: .mediapipe)
    joints[.leftKnee] = PoseJointMeasurement(name: .leftKnee, point: CGPoint(x: 0.45, y: 0.3), confidence: 0.8, backend: .mediapipe)
    joints[.rightKnee] = PoseJointMeasurement(name: .rightKnee, point: CGPoint(x: 0.55, y: 0.3), confidence: 0.8, backend: .mediapipe)
    joints[.leftAnkle] = PoseJointMeasurement(name: .leftAnkle, point: CGPoint(x: 0.45, y: 0.1), confidence: 0.8, backend: .mediapipe)
    joints[.rightAnkle] = PoseJointMeasurement(name: .rightAnkle, point: CGPoint(x: 0.55, y: 0.1), confidence: 0.8, backend: .mediapipe)
    joints[.leftFoot] = PoseJointMeasurement(name: .leftFoot, point: CGPoint(x: 0.43, y: 0.07), confidence: 0.8, backend: .mediapipe)
    joints[.rightFoot] = PoseJointMeasurement(name: .rightFoot, point: CGPoint(x: 0.57, y: 0.07), confidence: 0.8, backend: .mediapipe)
    return joints
  }
}

final class PoseBackendCoordinatorTests: XCTestCase {
  private struct MockBackend: PoseBackend {
    let kind: PoseBackendKind
    let isAvailable: Bool
    let detectedCount: Int

    func process(frame: PoseFrameInput) throws -> PoseProcessingResult {
      let has = detectedCount > 0
      let measured: [PushlyJointName: PoseJointMeasurement] = has
        ? [.nose: PoseJointMeasurement(name: .nose, point: CGPoint(x: 0.5, y: 0.5), confidence: 0.9, backend: kind)]
        : [:]

      return PoseProcessingResult(
        measured: measured,
        avgConfidence: has ? 0.9 : 0,
        brightnessLuma: 0.5,
        lowLightDetected: false,
        observationExists: has,
        detectedJointCount: detectedCount,
        backend: kind,
        mode: has ? .upperBody : .unknown,
        modeConfidence: has ? 0.8 : 0,
        coverage: has ? PoseVisibilityCoverage(upperBodyCoverage: 0.6, fullBodyCoverage: 0.1, handCoverage: 0.4) : .empty,
        backendDiagnostics: PoseBackendDiagnostics(
          rawObservationCount: has ? 1 : 0,
          trackedJointCount: detectedCount,
          averageJointConfidence: has ? 0.9 : 0,
          roiUsed: frame.roiHint,
          durationMs: 2,
          modeConfidence: has ? 0.8 : 0,
          reliability: has ? 0.8 : 0,
          handRefinedJointCount: 0
        ),
        reacquireDiagnostics: ReacquireDiagnostics(
          source: frame.reacquireSource,
          roi: frame.roiHint,
          relockSuccessCount: frame.relockSuccessCount,
          relockFailureCount: frame.relockFailureCount
        )
      )
    }
  }

  func testFallbackPicksVisionWhenMediaPipeEmpty() throws {
    let config = PushlyPoseConfig()
    let coordinator = PoseBackendCoordinator(
      config: config,
      mediaPipeBackend: MockBackend(kind: .mediapipe, isAvailable: true, detectedCount: 0),
      visionFallbackBackend: MockBackend(kind: .visionFallback, isAvailable: true, detectedCount: 6)
    )

    var timing = CMSampleTimingInfo()
    var formatDesc: CMFormatDescription?
    var sample: CMSampleBuffer?
    CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: kCMVideoCodecType_422YpCbCr8, width: 4, height: 4, extensions: nil, formatDescriptionOut: &formatDesc)
    CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: nil, formatDescription: formatDesc, sampleCount: 0, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample)

    let result = try coordinator.process(
      frame: PoseFrameInput(
        sampleBuffer: sample!,
        orientation: .up,
        mirrored: false,
        roiHint: nil,
        timestamp: CACurrentMediaTime(),
        targetMode: .upperBody,
        reacquireSource: .none,
        relockSuccessCount: 0,
        relockFailureCount: 0
      )
    )

    XCTAssertEqual(result.backend, .visionFallback)
    XCTAssertGreaterThan(result.detectedJointCount, 0)
  }
}

final class BridgePayloadCompatibilityTests: XCTestCase {
  func testBridgePayloadIncludesLegacyAndNewKeys() {
    let mapper = JSBridgePayloadMapper()
    let joints: [PushlyJointName: TrackedJoint] = [
      .nose: TrackedJoint(
        name: .nose,
        rawPosition: CGPoint(x: 0.5, y: 0.8),
        smoothedPosition: CGPoint(x: 0.51, y: 0.79),
        velocity: .zero,
        rawConfidence: 0.9,
        renderConfidence: 0.9,
        logicConfidence: 0.9,
        visibility: 0.9,
        presence: 0.9,
        inFrame: true,
        sourceType: .measured,
        timestamp: CACurrentMediaTime()
      )
    ]

    let quality = TrackingQuality(
      trackingQuality: 0.8,
      renderQuality: 0.78,
      logicQuality: 0.82,
      bodyVisibilityState: .good,
      trackingState: .tracking,
      poseTrackingState: .trackingUpperBody,
      poseMode: .upperBody,
      reasonCodes: [],
      spreadScore: 0.6,
      smoothedSpread: 0.58,
      visibleJointCount: 1,
      upperBodyRenderableCount: 1,
      reliability: 0.9,
      roiCoverage: 0.32,
      fullBodyCoverage: 0.2,
      upperBodyCoverage: 0.8,
      handCoverage: 0.4,
      wristRetention: 0.5,
      inferredJointRatio: 0,
      modeConfidence: 0.83
    )

    let rep = RepDetectionOutput(state: .plankLocked, repCount: 1, formScore: 0.77, blockedReasons: [])

    let payload = mapper.makePayload(
      joints: joints,
      quality: quality,
      rep: rep,
      instruction: "Test",
      lowLightDetected: false,
      poseBackend: .mediapipe,
      poseFPS: 28,
      cameraTelemetry: nil,
      bounds: CGRect(x: 0, y: 0, width: 300, height: 500),
      debugEnabled: false,
      reacquireSource: .previousTrack,
      orientation: .leftMirrored,
      mirrored: true,
      debugSessionID: "test-session",
      visibleJointCount: 1
    )

    XCTAssertNotNil(payload["trackingState"]) // legacy
    XCTAssertNotNil(payload["bodyMode"]) // legacy
    XCTAssertNotNil(payload["poseMode"]) // new
    XCTAssertNotNil(payload["poseTrackingState"]) // new
    XCTAssertNotNil(payload["processingFPS"]) // new
    XCTAssertNotNil(payload["handCoverage"]) // new
    XCTAssertNotNil(payload["cameraProcessingBacklog"]) // new
    XCTAssertNotNil(payload["cameraAverageProcessingMs"]) // new
    XCTAssertNotNil(payload["visibleJointCount"]) // new
    XCTAssertNotNil(payload["mirrored"]) // new
    XCTAssertNotNil(payload["orientation"]) // new
    XCTAssertNotNil(payload["debugSessionID"]) // new
  }
}

final class PoseDiagnosticsTests: XCTestCase {
  func testDiagnosticsExportContainsSummaryAndBoundedEvents() throws {
    let config = PushlyPoseConfig()
    let diagnostics = PoseDiagnostics(config: config)
    diagnostics.beginSession(cameraPosition: .front, mirrored: true, activeBackend: .mediapipe, fallbackAvailable: true)

    for _ in 0..<500 {
      diagnostics.recordBackendResultEmpty(.mediapipe, consecutive: 6)
    }
    for i in 0..<6 {
      diagnostics.recordFrameReceived()
      diagnostics.recordProcessedFrame(
        frameIndex: i,
        timestamp: CACurrentMediaTime() + Double(i) * 0.03,
        backend: .mediapipe,
        mode: .upperBody,
        trackingState: .trackingUpperBody,
        visibleJointCount: 7,
        upperBodyCoverage: 0.7,
        fullBodyCoverage: 0.2,
        handCoverage: 0.6,
        averageJointConfidence: 0.8,
        reliability: 0.76,
        roi: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5),
        mirrored: true,
        orientation: .leftMirrored,
        inferenceDurationMs: 12,
        pipelineDurationMs: 18,
        renderedJointCount: 7,
        inferredJointRatio: 0.1
      )
    }
    diagnostics.endSession(reason: "unit_test")

    let expect = expectation(description: "export")
    var exportedPath: String?
    diagnostics.exportToDisk(configSnapshot: ["unit": "test"]) { result in
      if case .success(let url) = result {
        exportedPath = url.path
      }
      expect.fulfill()
    }
    wait(for: [expect], timeout: 2.0)

    XCTAssertNotNil(exportedPath)
    let data = try Data(contentsOf: URL(fileURLWithPath: exportedPath!))
    let decoded = try JSONDecoder().decode(PoseDebugExport.self, from: data)
    XCTAssertEqual(decoded.summary.activePoseBackend, PoseBackendKind.mediapipe.rawValue)
    XCTAssertLessThanOrEqual(decoded.recentEvents.count, config.pipeline.maxDiagnosticEventBuffer)
    XCTAssertLessThanOrEqual(decoded.sampledFrames.count, config.pipeline.maxDiagnosticFrameBuffer)
    XCTAssertEqual(decoded.sampledFrames.count, 0) // Default config has verbose frame sampling disabled.
  }

  func testDiagnosticsFlagsFollowConfigDefaults() {
    let config = PushlyPoseConfig()
    let diagnostics = PoseDiagnostics(config: config)
    XCTAssertEqual(diagnostics.overlayEnabledByDefault, config.pipeline.debugOverlayEnabled)
  }
}
#endif
#endif
