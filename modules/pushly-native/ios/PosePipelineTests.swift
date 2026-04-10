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
      isMirrored: false
    )

    let center = PoseCoordinateConverter.pointFromCanonical(CGPoint(x: 0.5, y: 0.5), projection: projection)
    XCTAssertEqual(center.x, 150, accuracy: 0.01)
    XCTAssertEqual(center.y, 300, accuracy: 0.01)

    let leftEdge = PoseCoordinateConverter.pointFromCanonical(CGPoint(x: 0.0, y: 0.5), projection: projection)
    XCTAssertLessThan(leftEdge.x, 0) // Expected cropped content outside visible viewport.
  }

  func testProjectionMirrorsFrontCameraOverlay() {
    let projection = PoseCoordinateConverter.ProjectionContext(
      previewBounds: CGRect(x: 0, y: 0, width: 300, height: 600),
      pixelBufferSize: CGSize(width: 1920, height: 1080),
      videoGravity: .resizeAspectFill,
      orientation: .right,
      isMirrored: true
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
    manager.update(measured: makeUpperBody(), modeHint: .upperBody, modeHintConfidence: 0.8, coverage: nil, segmentationBottomAssistActive: false, now: now, reacquire: nil)
    manager.update(measured: makeUpperBody(), modeHint: .upperBody, modeHintConfidence: 0.8, coverage: nil, segmentationBottomAssistActive: false, now: now + 0.03, reacquire: nil)

    XCTAssertEqual(manager.poseState, .trackingUpperBody)
    XCTAssertNotEqual(manager.poseState, .lost)
  }

  func testFullBodyModeTransitionAndDowngradeToUpper() {
    let config = PushlyPoseConfig()
    let manager = TrackContinuityManager(config: config)

    let now = CACurrentMediaTime()
    for i in 0..<5 {
      manager.update(measured: makeFullBody(), modeHint: .fullBody, modeHintConfidence: 0.9, coverage: nil, segmentationBottomAssistActive: false, now: now + Double(i) * 0.03, reacquire: nil)
    }
    XCTAssertEqual(manager.poseState, .trackingFullBody)
    XCTAssertEqual(manager.bodyMode, .fullBody)

    for i in 5..<11 {
      manager.update(measured: makeUpperBody(), modeHint: .upperBody, modeHintConfidence: 0.8, coverage: nil, segmentationBottomAssistActive: false, now: now + Double(i) * 0.03, reacquire: nil)
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

    manager.update(measured: ambiguous, modeHint: nil, modeHintConfidence: nil, coverage: nil, segmentationBottomAssistActive: false, now: now, reacquire: nil)
    XCTAssertEqual(manager.poseState, .reacquiring)

    for i in 1...7 {
      manager.update(measured: [:], modeHint: nil, modeHintConfidence: nil, coverage: nil, segmentationBottomAssistActive: false, now: now + Double(i) * 0.06, reacquire: nil)
    }

    XCTAssertEqual(manager.poseState, .lost)
  }

  func testShortLossReacquiresWithoutEnteringLost() {
    let config = PushlyPoseConfig()
    let manager = TrackContinuityManager(config: config)

    let now = CACurrentMediaTime()
    manager.update(measured: makeUpperBody(), modeHint: .upperBody, modeHintConfidence: 0.8, coverage: nil, segmentationBottomAssistActive: false, now: now, reacquire: nil)
    manager.update(measured: makeUpperBody(), modeHint: .upperBody, modeHintConfidence: 0.8, coverage: nil, segmentationBottomAssistActive: false, now: now + 0.03, reacquire: nil)
    XCTAssertEqual(manager.poseState, .trackingUpperBody)

    for i in 1..<config.mode.lostEnterFrames {
      manager.update(
        measured: [:],
        modeHint: nil,
        modeHintConfidence: nil,
        coverage: nil,
        segmentationBottomAssistActive: false,
        now: now + 0.03 + Double(i) * 0.03,
        reacquire: nil
      )
    }

    XCTAssertNotEqual(manager.poseState, .lost)
    XCTAssertEqual(manager.poseState, .reacquiring)

    let relockStart = now + 0.03 + Double(config.mode.lostEnterFrames) * 0.03
    manager.update(measured: makeUpperBody(), modeHint: .upperBody, modeHintConfidence: 0.8, coverage: nil, segmentationBottomAssistActive: false, now: relockStart, reacquire: nil)
    manager.update(measured: makeUpperBody(), modeHint: .upperBody, modeHintConfidence: 0.8, coverage: nil, segmentationBottomAssistActive: false, now: relockStart + 0.03, reacquire: nil)

    XCTAssertEqual(manager.poseState, .trackingUpperBody)
    XCTAssertGreaterThan(manager.relockSuccessCount, 0)
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

final class TemporalJointTrackerTests: XCTestCase {
  func testConfidenceHysteresisKeepsJointAliveAcrossMidConfidenceDip() {
    let config = PushlyPoseConfig()
    let tracker = TemporalJointTracker(config: config)
    let now = CACurrentMediaTime()

    _ = tracker.update(
      measured: trackedUpperBody(hipConfidence: 0.82),
      lowLightDetected: false,
      roiHint: nil,
      frameTimestamp: now
    )

    let dipped = tracker.update(
      measured: trackedUpperBody(hipConfidence: 0.28),
      lowLightDetected: false,
      roiHint: nil,
      frameTimestamp: now + 0.033
    )

    XCTAssertEqual(dipped[.leftHip]?.sourceType, .lowConfidenceMeasured)
    XCTAssertTrue(dipped[.leftHip]?.isRenderable == true)
  }

  func testKinematicLockPreservesLowerBodyDuringOcclusion() {
    let config = PushlyPoseConfig()
    let tracker = TemporalJointTracker(config: config)
    let now = CACurrentMediaTime()

    _ = tracker.update(
      measured: trackedFullBody(),
      lowLightDetected: false,
      roiHint: nil,
      frameTimestamp: now
    )

    let occluded = tracker.update(
      measured: occludedPushupUpperBody(),
      lowLightDetected: false,
      roiHint: nil,
      frameTimestamp: now + 0.033
    )

    XCTAssertEqual(occluded[.leftHip]?.sourceType, .inferred)
    XCTAssertEqual(occluded[.leftKnee]?.sourceType, .inferred)
    XCTAssertEqual(occluded[.leftAnkle]?.sourceType, .inferred)
    XCTAssertTrue(occluded[.leftFoot]?.isRenderable == true)
  }

  func testSideIdentityLockPreventsSingleFrameLeftRightFlip() {
    let config = PushlyPoseConfig()
    let tracker = TemporalJointTracker(config: config)
    let now = CACurrentMediaTime()

    _ = tracker.update(
      measured: trackedFullBody(),
      lowLightDetected: false,
      roiHint: nil,
      frameTimestamp: now
    )

    let flippedFrame = tracker.update(
      measured: trackedFullBodyFlippedSides(),
      lowLightDetected: false,
      roiHint: nil,
      frameTimestamp: now + 0.033
    )

    XCTAssertLessThan(
      flippedFrame[.leftShoulder]?.smoothedPosition.x ?? 1,
      flippedFrame[.rightShoulder]?.smoothedPosition.x ?? 0
    )
    XCTAssertLessThan(
      flippedFrame[.leftHip]?.smoothedPosition.x ?? 1,
      flippedFrame[.rightHip]?.smoothedPosition.x ?? 0
    )
  }

  func testPushupModeExtendsMissingPredictionWindowWithTighterDriftClamp() {
    let config = PushlyPoseConfig()
    let trackerBase = TemporalJointTracker(config: config)
    let trackerPushup = TemporalJointTracker(config: config)
    let now = CACurrentMediaTime()

    let frameA = trackedFullBodyWithLeftHand(handX: 0.24, handY: 0.42)
    let frameB = trackedFullBodyWithLeftHand(handX: 0.34, handY: 0.46)

    _ = trackerBase.update(
      measured: frameA,
      lowLightDetected: false,
      roiHint: nil,
      frameTimestamp: now
    )
    _ = trackerBase.update(
      measured: frameB,
      lowLightDetected: false,
      roiHint: nil,
      frameTimestamp: now + 0.033
    )

    _ = trackerPushup.update(
      measured: frameA,
      lowLightDetected: false,
      roiHint: nil,
      frameTimestamp: now
    )
    _ = trackerPushup.update(
      measured: frameB,
      lowLightDetected: false,
      roiHint: nil,
      frameTimestamp: now + 0.033
    )

    var occluded = frameB
    occluded.removeValue(forKey: .leftHand)
    let probeTime = now + config.tracker.missingJointPredictionMaxAge + 0.05
    let baseOut = trackerBase.update(
      measured: occluded,
      lowLightDetected: false,
      roiHint: nil,
      frameTimestamp: probeTime,
      pushupFloorModeActive: false
    )
    let pushupOut = trackerPushup.update(
      measured: occluded,
      lowLightDetected: false,
      roiHint: nil,
      frameTimestamp: probeTime,
      pushupFloorModeActive: true
    )

    XCTAssertNil(baseOut[.leftHand])
    let pushupHand = pushupOut[.leftHand]
    XCTAssertEqual(pushupHand?.sourceType, .predicted)
    XCTAssertTrue(pushupHand?.isRenderable == true)
    if let pushupHand {
      let anchor = frameB[.leftHand]!.point
      let distance = hypot(pushupHand.smoothedPosition.x - anchor.x, pushupHand.smoothedPosition.y - anchor.y)
      let maxPushupDrift = config.tracker.missingJointPredictionMaxExtrapolation * config.tracker.pushupMissingJointPredictionMaxExtrapolationScale
      XCTAssertLessThanOrEqual(distance, maxPushupDrift + 0.0001)
    }
  }

  func testPushupDistalTorsoInferenceStaysRenderableButLogicConservative() {
    let config = PushlyPoseConfig()
    let tracker = TemporalJointTracker(config: config)
    let now = CACurrentMediaTime()

    _ = tracker.update(
      measured: trackedFullBody(),
      lowLightDetected: false,
      roiHint: nil,
      frameTimestamp: now
    )

    let occluded = tracker.update(
      measured: occludedPushupUpperBody(),
      lowLightDetected: false,
      roiHint: nil,
      frameTimestamp: now + 0.033,
      pushupFloorModeActive: true
    )

    XCTAssertEqual(occluded[.leftKnee]?.sourceType, .inferred)
    XCTAssertTrue(occluded[.leftKnee]?.isRenderable == true)
    XCTAssertFalse(occluded[.leftKnee]?.isLogicUsable ?? true)
    XCTAssertEqual(occluded[.leftWrist]?.sourceType, .inferred)
    XCTAssertTrue(occluded[.leftWrist]?.isRenderable == true)
    XCTAssertFalse(occluded[.leftWrist]?.isLogicUsable ?? true)
  }

  func testPushupAnchorConfidenceDipPrefersLowConfidenceMeasuredOverInferred() {
    let config = PushlyPoseConfig()
    let trackerBase = TemporalJointTracker(config: config)
    let trackerPushup = TemporalJointTracker(config: config)
    let now = CACurrentMediaTime()

    let stable = trackedUpperBody(hipConfidence: 0.82)
    _ = trackerBase.update(
      measured: stable,
      lowLightDetected: false,
      roiHint: nil,
      frameTimestamp: now,
      pushupFloorModeActive: false
    )
    _ = trackerPushup.update(
      measured: stable,
      lowLightDetected: false,
      roiHint: nil,
      frameTimestamp: now,
      pushupFloorModeActive: true
    )

    var dipped = trackedUpperBody(hipConfidence: 0.24)
    dipped[.leftShoulder] = PoseJointMeasurement(
      name: .leftShoulder,
      point: CGPoint(x: 0.42, y: 0.72),
      confidence: 0.125,
      visibility: 0.16,
      presence: 0.16,
      sourceType: .measured,
      inFrame: true,
      backend: .visionFallback,
      measuredAt: now + 0.033
    )

    let baseOut = trackerBase.update(
      measured: dipped,
      lowLightDetected: false,
      roiHint: nil,
      frameTimestamp: now + 0.033,
      pushupFloorModeActive: false
    )
    let pushupOut = trackerPushup.update(
      measured: dipped,
      lowLightDetected: false,
      roiHint: nil,
      frameTimestamp: now + 0.033,
      pushupFloorModeActive: true
    )

    XCTAssertEqual(baseOut[.leftShoulder]?.sourceType, .inferred)
    XCTAssertEqual(pushupOut[.leftShoulder]?.sourceType, .lowConfidenceMeasured)
    XCTAssertTrue(pushupOut[.leftShoulder]?.isRenderable == true)
  }

  private func trackedUpperBody(hipConfidence: Float) -> [PushlyJointName: PoseJointMeasurement] {
    var joints: [PushlyJointName: PoseJointMeasurement] = [
      .nose: PoseJointMeasurement(name: .nose, point: CGPoint(x: 0.5, y: 0.84), confidence: 0.9, visibility: 0.9, presence: 0.9, backend: .mediapipe),
      .leftShoulder: PoseJointMeasurement(name: .leftShoulder, point: CGPoint(x: 0.42, y: 0.72), confidence: 0.9, visibility: 0.9, presence: 0.9, backend: .mediapipe),
      .rightShoulder: PoseJointMeasurement(name: .rightShoulder, point: CGPoint(x: 0.58, y: 0.72), confidence: 0.9, visibility: 0.9, presence: 0.9, backend: .mediapipe)
    ]
    joints[.leftHip] = PoseJointMeasurement(
      name: .leftHip,
      point: CGPoint(x: 0.45, y: 0.5),
      confidence: hipConfidence,
      visibility: hipConfidence,
      presence: hipConfidence,
      sourceType: .measured,
      inFrame: true,
      backend: .mediapipe
    )
    return joints
  }

  private func trackedFullBody() -> [PushlyJointName: PoseJointMeasurement] {
    [
      .nose: PoseJointMeasurement(name: .nose, point: CGPoint(x: 0.5, y: 0.84), confidence: 0.92, visibility: 0.92, presence: 0.92, backend: .mediapipe),
      .leftShoulder: PoseJointMeasurement(name: .leftShoulder, point: CGPoint(x: 0.42, y: 0.72), confidence: 0.92, visibility: 0.92, presence: 0.92, backend: .mediapipe),
      .rightShoulder: PoseJointMeasurement(name: .rightShoulder, point: CGPoint(x: 0.58, y: 0.72), confidence: 0.92, visibility: 0.92, presence: 0.92, backend: .mediapipe),
      .leftHip: PoseJointMeasurement(name: .leftHip, point: CGPoint(x: 0.45, y: 0.49), confidence: 0.9, visibility: 0.9, presence: 0.9, backend: .mediapipe),
      .rightHip: PoseJointMeasurement(name: .rightHip, point: CGPoint(x: 0.55, y: 0.49), confidence: 0.9, visibility: 0.9, presence: 0.9, backend: .mediapipe),
      .leftKnee: PoseJointMeasurement(name: .leftKnee, point: CGPoint(x: 0.44, y: 0.28), confidence: 0.9, visibility: 0.9, presence: 0.9, backend: .mediapipe),
      .rightKnee: PoseJointMeasurement(name: .rightKnee, point: CGPoint(x: 0.56, y: 0.28), confidence: 0.9, visibility: 0.9, presence: 0.9, backend: .mediapipe),
      .leftAnkle: PoseJointMeasurement(name: .leftAnkle, point: CGPoint(x: 0.43, y: 0.12), confidence: 0.88, visibility: 0.88, presence: 0.88, backend: .mediapipe),
      .rightAnkle: PoseJointMeasurement(name: .rightAnkle, point: CGPoint(x: 0.57, y: 0.12), confidence: 0.88, visibility: 0.88, presence: 0.88, backend: .mediapipe),
      .leftFoot: PoseJointMeasurement(name: .leftFoot, point: CGPoint(x: 0.41, y: 0.08), confidence: 0.86, visibility: 0.86, presence: 0.86, backend: .mediapipe),
      .rightFoot: PoseJointMeasurement(name: .rightFoot, point: CGPoint(x: 0.59, y: 0.08), confidence: 0.86, visibility: 0.86, presence: 0.86, backend: .mediapipe)
    ]
  }

  private func trackedFullBodyWithLeftHand(handX: CGFloat, handY: CGFloat) -> [PushlyJointName: PoseJointMeasurement] {
    var joints = trackedFullBody()
    joints[.leftHand] = PoseJointMeasurement(
      name: .leftHand,
      point: CGPoint(x: handX, y: handY),
      confidence: 0.86,
      visibility: 0.86,
      presence: 0.86,
      backend: .mediapipe
    )
    return joints
  }

  private func occludedPushupUpperBody() -> [PushlyJointName: PoseJointMeasurement] {
    [
      .nose: PoseJointMeasurement(name: .nose, point: CGPoint(x: 0.51, y: 0.76), confidence: 0.9, visibility: 0.9, presence: 0.9, backend: .mediapipe),
      .leftShoulder: PoseJointMeasurement(name: .leftShoulder, point: CGPoint(x: 0.43, y: 0.65), confidence: 0.9, visibility: 0.9, presence: 0.9, backend: .mediapipe),
      .rightShoulder: PoseJointMeasurement(name: .rightShoulder, point: CGPoint(x: 0.59, y: 0.65), confidence: 0.9, visibility: 0.9, presence: 0.9, backend: .mediapipe),
      .leftHip: PoseJointMeasurement(name: .leftHip, point: CGPoint(x: 0.45, y: 0.49), confidence: 0.01, visibility: 0.01, presence: 0.01, sourceType: .lowConfidenceMeasured, inFrame: false, backend: .mediapipe),
      .rightHip: PoseJointMeasurement(name: .rightHip, point: CGPoint(x: 0.55, y: 0.49), confidence: 0.01, visibility: 0.01, presence: 0.01, sourceType: .lowConfidenceMeasured, inFrame: false, backend: .mediapipe)
    ]
  }

  private func trackedFullBodyFlippedSides() -> [PushlyJointName: PoseJointMeasurement] {
    [
      .nose: PoseJointMeasurement(name: .nose, point: CGPoint(x: 0.5, y: 0.84), confidence: 0.92, visibility: 0.92, presence: 0.92, backend: .mediapipe),
      .leftShoulder: PoseJointMeasurement(name: .leftShoulder, point: CGPoint(x: 0.58, y: 0.72), confidence: 0.92, visibility: 0.92, presence: 0.92, backend: .mediapipe),
      .rightShoulder: PoseJointMeasurement(name: .rightShoulder, point: CGPoint(x: 0.42, y: 0.72), confidence: 0.92, visibility: 0.92, presence: 0.92, backend: .mediapipe),
      .leftElbow: PoseJointMeasurement(name: .leftElbow, point: CGPoint(x: 0.65, y: 0.61), confidence: 0.9, visibility: 0.9, presence: 0.9, backend: .mediapipe),
      .rightElbow: PoseJointMeasurement(name: .rightElbow, point: CGPoint(x: 0.35, y: 0.61), confidence: 0.9, visibility: 0.9, presence: 0.9, backend: .mediapipe),
      .leftWrist: PoseJointMeasurement(name: .leftWrist, point: CGPoint(x: 0.7, y: 0.52), confidence: 0.88, visibility: 0.88, presence: 0.88, backend: .mediapipe),
      .rightWrist: PoseJointMeasurement(name: .rightWrist, point: CGPoint(x: 0.3, y: 0.52), confidence: 0.88, visibility: 0.88, presence: 0.88, backend: .mediapipe),
      .leftHip: PoseJointMeasurement(name: .leftHip, point: CGPoint(x: 0.55, y: 0.49), confidence: 0.9, visibility: 0.9, presence: 0.9, backend: .mediapipe),
      .rightHip: PoseJointMeasurement(name: .rightHip, point: CGPoint(x: 0.45, y: 0.49), confidence: 0.9, visibility: 0.9, presence: 0.9, backend: .mediapipe),
      .leftKnee: PoseJointMeasurement(name: .leftKnee, point: CGPoint(x: 0.56, y: 0.28), confidence: 0.9, visibility: 0.9, presence: 0.9, backend: .mediapipe),
      .rightKnee: PoseJointMeasurement(name: .rightKnee, point: CGPoint(x: 0.44, y: 0.28), confidence: 0.9, visibility: 0.9, presence: 0.9, backend: .mediapipe),
      .leftAnkle: PoseJointMeasurement(name: .leftAnkle, point: CGPoint(x: 0.57, y: 0.12), confidence: 0.88, visibility: 0.88, presence: 0.88, backend: .mediapipe),
      .rightAnkle: PoseJointMeasurement(name: .rightAnkle, point: CGPoint(x: 0.43, y: 0.12), confidence: 0.88, visibility: 0.88, presence: 0.88, backend: .mediapipe)
    ]
  }
}

final class TrackingQualityEvaluatorTests: XCTestCase {
  func testFloorStateDoesNotPunishInferredLowerBodyAsMissing() {
    let evaluator = TrackingQualityEvaluator(config: PushlyPoseConfig())
    let now = CACurrentMediaTime()
    let joints: [PushlyJointName: TrackedJoint] = [
      .nose: trackedJoint(.nose, x: 0.5, y: 0.63, render: 0.92, logic: 0.92, source: .measured, now: now),
      .leftShoulder: trackedJoint(.leftShoulder, x: 0.4, y: 0.54, render: 0.92, logic: 0.92, source: .measured, now: now),
      .rightShoulder: trackedJoint(.rightShoulder, x: 0.6, y: 0.54, render: 0.92, logic: 0.92, source: .measured, now: now),
      .leftElbow: trackedJoint(.leftElbow, x: 0.32, y: 0.44, render: 0.88, logic: 0.88, source: .measured, now: now),
      .rightElbow: trackedJoint(.rightElbow, x: 0.68, y: 0.44, render: 0.88, logic: 0.88, source: .measured, now: now),
      .leftWrist: trackedJoint(.leftWrist, x: 0.24, y: 0.34, render: 0.84, logic: 0.84, source: .measured, now: now),
      .rightWrist: trackedJoint(.rightWrist, x: 0.76, y: 0.34, render: 0.84, logic: 0.84, source: .measured, now: now),
      .leftHip: trackedJoint(.leftHip, x: 0.34, y: 0.5, render: 0.46, logic: 0.22, source: .inferred, now: now),
      .rightHip: trackedJoint(.rightHip, x: 0.66, y: 0.5, render: 0.46, logic: 0.22, source: .inferred, now: now),
      .leftAnkle: trackedJoint(.leftAnkle, x: 0.16, y: 0.5, render: 0.36, logic: 0.2, source: .inferred, now: now),
      .rightAnkle: trackedJoint(.rightAnkle, x: 0.84, y: 0.5, render: 0.36, logic: 0.2, source: .inferred, now: now)
    ]

    let quality = evaluator.evaluate(
      joints: joints,
      lowLightDetected: false,
      trackingState: .tracking,
      poseState: .trackingFullBody,
      poseMode: .fullBody,
      modeConfidence: 0.82,
      roiCoverage: 0.4,
      coverageHint: PoseVisibilityCoverage(upperBodyCoverage: 0.9, fullBodyCoverage: 0.22, handCoverage: 0.8)
    )

    XCTAssertFalse(quality.reasonCodes.contains("lower_body_missing"))
    XCTAssertNotEqual(quality.bodyVisibilityState, .partial)
    XCTAssertGreaterThan(quality.logicQuality, 0.4)
  }

  func testLowLightPenaltyIsTieredAndKeepsRenderQualityStable() {
    let evaluator = TrackingQualityEvaluator(config: PushlyPoseConfig())
    let now = CACurrentMediaTime()
    let joints: [PushlyJointName: TrackedJoint] = [
      .nose: trackedJoint(.nose, x: 0.5, y: 0.63, render: 0.92, logic: 0.92, source: .measured, now: now),
      .leftShoulder: trackedJoint(.leftShoulder, x: 0.4, y: 0.54, render: 0.92, logic: 0.92, source: .measured, now: now),
      .rightShoulder: trackedJoint(.rightShoulder, x: 0.6, y: 0.54, render: 0.92, logic: 0.92, source: .measured, now: now),
      .leftElbow: trackedJoint(.leftElbow, x: 0.32, y: 0.44, render: 0.88, logic: 0.88, source: .measured, now: now),
      .rightElbow: trackedJoint(.rightElbow, x: 0.68, y: 0.44, render: 0.88, logic: 0.88, source: .measured, now: now),
      .leftWrist: trackedJoint(.leftWrist, x: 0.24, y: 0.34, render: 0.84, logic: 0.84, source: .measured, now: now),
      .rightWrist: trackedJoint(.rightWrist, x: 0.76, y: 0.34, render: 0.84, logic: 0.84, source: .measured, now: now),
      .leftHip: trackedJoint(.leftHip, x: 0.34, y: 0.5, render: 0.46, logic: 0.24, source: .inferred, now: now),
      .rightHip: trackedJoint(.rightHip, x: 0.66, y: 0.5, render: 0.46, logic: 0.24, source: .inferred, now: now),
      .leftAnkle: trackedJoint(.leftAnkle, x: 0.16, y: 0.5, render: 0.36, logic: 0.22, source: .inferred, now: now),
      .rightAnkle: trackedJoint(.rightAnkle, x: 0.84, y: 0.5, render: 0.36, logic: 0.22, source: .inferred, now: now)
    ]

    let base = evaluator.evaluate(
      joints: joints,
      lowLightDetected: false,
      veryLowLightDetected: false,
      trackingState: .tracking,
      poseState: .trackingFullBody,
      poseMode: .fullBody,
      modeConfidence: 0.82,
      roiCoverage: 0.4,
      coverageHint: PoseVisibilityCoverage(upperBodyCoverage: 0.9, fullBodyCoverage: 0.22, handCoverage: 0.8)
    )
    let low = evaluator.evaluate(
      joints: joints,
      lowLightDetected: true,
      veryLowLightDetected: false,
      trackingState: .tracking,
      poseState: .trackingFullBody,
      poseMode: .fullBody,
      modeConfidence: 0.82,
      roiCoverage: 0.4,
      coverageHint: PoseVisibilityCoverage(upperBodyCoverage: 0.9, fullBodyCoverage: 0.22, handCoverage: 0.8)
    )
    let veryLow = evaluator.evaluate(
      joints: joints,
      lowLightDetected: true,
      veryLowLightDetected: true,
      trackingState: .tracking,
      poseState: .trackingFullBody,
      poseMode: .fullBody,
      modeConfidence: 0.82,
      roiCoverage: 0.4,
      coverageHint: PoseVisibilityCoverage(upperBodyCoverage: 0.9, fullBodyCoverage: 0.22, handCoverage: 0.8)
    )

    XCTAssertEqual(base.renderQuality, low.renderQuality, accuracy: 0.0001)
    XCTAssertEqual(base.renderQuality, veryLow.renderQuality, accuracy: 0.0001)
    XCTAssertGreaterThan(base.logicQuality, low.logicQuality)
    XCTAssertGreaterThan(low.logicQuality, veryLow.logicQuality)
    XCTAssertLessThan(base.logicQuality - low.logicQuality, 0.06)
    XCTAssertTrue(veryLow.reasonCodes.contains("very_low_light"))
  }

  func testFloorStateFallbackWorksWithoutNoseWhenShoulderArmHipAnchorsExist() {
    let evaluator = TrackingQualityEvaluator(config: PushlyPoseConfig())
    let now = CACurrentMediaTime()
    let joints: [PushlyJointName: TrackedJoint] = [
      .leftShoulder: trackedJoint(.leftShoulder, x: 0.41, y: 0.54, render: 0.84, logic: 0.82, source: .lowConfidenceMeasured, now: now),
      .rightShoulder: trackedJoint(.rightShoulder, x: 0.59, y: 0.54, render: 0.84, logic: 0.82, source: .lowConfidenceMeasured, now: now),
      .leftElbow: trackedJoint(.leftElbow, x: 0.33, y: 0.49, render: 0.74, logic: 0.66, source: .inferred, now: now),
      .leftWrist: trackedJoint(.leftWrist, x: 0.27, y: 0.45, render: 0.68, logic: 0.22, source: .inferred, now: now),
      .leftHip: trackedJoint(.leftHip, x: 0.45, y: 0.5, render: 0.52, logic: 0.26, source: .inferred, now: now),
      .rightHip: trackedJoint(.rightHip, x: 0.55, y: 0.5, render: 0.5, logic: 0.24, source: .inferred, now: now)
    ]

    let quality = evaluator.evaluate(
      joints: joints,
      lowLightDetected: false,
      trackingState: .tracking,
      poseState: .trackingUpperBody,
      poseMode: .upperBody,
      pushupFloorModeActive: false,
      modeConfidence: 0.62,
      roiCoverage: 0.38,
      coverageHint: PoseVisibilityCoverage(upperBodyCoverage: 0.72, fullBodyCoverage: 0.18, handCoverage: 0.44)
    )

    XCTAssertEqual(quality.pushupFloorModeActive, true)
    XCTAssertGreaterThan(quality.logicQuality, 0.3)
    XCTAssertNotEqual(quality.bodyVisibilityState, .notFound)
  }

  private func trackedJoint(
    _ name: PushlyJointName,
    x: CGFloat,
    y: CGFloat,
    render: Float,
    logic: Float,
    source: PushlyJointSourceType,
    now: TimeInterval
  ) -> TrackedJoint {
    TrackedJoint(
      name: name,
      rawPosition: CGPoint(x: x, y: y),
      smoothedPosition: CGPoint(x: x, y: y),
      velocity: .zero,
      rawConfidence: render,
      renderConfidence: render,
      logicConfidence: logic,
      visibility: render,
      presence: render,
      inFrame: true,
      sourceType: source,
      timestamp: now
    )
  }
}

final class PushupRepDetectorStabilityTests: XCTestCase {
  func testPlankLocksWithInferredLowerBodySupport() {
    let config = PushlyPoseConfig()
    let detector = PushupRepDetector(config: config)
    let now = CACurrentMediaTime()
    let joints: [PushlyJointName: TrackedJoint] = [
      .nose: trackedJoint(.nose, x: 0.5, y: 0.63, render: 0.9, logic: 0.9, source: .measured, now: now),
      .leftShoulder: trackedJoint(.leftShoulder, x: 0.4, y: 0.54, render: 0.9, logic: 0.9, source: .measured, now: now),
      .rightShoulder: trackedJoint(.rightShoulder, x: 0.6, y: 0.54, render: 0.9, logic: 0.9, source: .measured, now: now),
      .leftElbow: trackedJoint(.leftElbow, x: 0.3, y: 0.52, render: 0.88, logic: 0.88, source: .measured, now: now),
      .rightElbow: trackedJoint(.rightElbow, x: 0.7, y: 0.52, render: 0.88, logic: 0.88, source: .measured, now: now),
      .leftWrist: trackedJoint(.leftWrist, x: 0.2, y: 0.5, render: 0.86, logic: 0.86, source: .measured, now: now),
      .rightWrist: trackedJoint(.rightWrist, x: 0.8, y: 0.5, render: 0.86, logic: 0.86, source: .measured, now: now),
      .leftHip: trackedJoint(.leftHip, x: 0.34, y: 0.5, render: 0.42, logic: 0.22, source: .inferred, now: now),
      .rightHip: trackedJoint(.rightHip, x: 0.66, y: 0.5, render: 0.42, logic: 0.22, source: .inferred, now: now),
      .leftAnkle: trackedJoint(.leftAnkle, x: 0.12, y: 0.5, render: 0.3, logic: 0.2, source: .inferred, now: now),
      .rightAnkle: trackedJoint(.rightAnkle, x: 0.88, y: 0.5, render: 0.3, logic: 0.2, source: .inferred, now: now)
    ]

    let quality = TrackingQuality(
      trackingQuality: 0.76,
      renderQuality: 0.78,
      logicQuality: 0.62,
      pushupFloorModeActive: true,
      bodyVisibilityState: .assisted,
      trackingState: .tracking,
      poseTrackingState: .trackingFullBody,
      poseMode: .fullBody,
      reasonCodes: [],
      spreadScore: 0.6,
      smoothedSpread: 0.6,
      visibleJointCount: joints.count,
      upperBodyRenderableCount: 7,
      reliability: 0.82,
      roiCoverage: 0.45,
      fullBodyCoverage: 0.4,
      upperBodyCoverage: 0.92,
      handCoverage: 0.9,
      wristRetention: 1,
      inferredJointRatio: 0.36,
      modeConfidence: 0.8
    )

    var output: RepDetectionOutput?
    for _ in 0..<config.rep.plankLockFrames {
      output = detector.update(joints: joints, quality: quality, repTarget: 10)
    }

    XCTAssertEqual(output?.state, .plankLocked)
    XCTAssertFalse(output?.blockedReasons.contains("measured_evidence_low") ?? true)
  }

  func testFrontalElbowJitterAloneDoesNotCountRep() {
    let config = PushlyPoseConfig()
    let detector = PushupRepDetector(config: config)
    let quality = stableFloorQuality(visibleJointCount: 11)
    var output: RepDetectionOutput?

    for _ in 0..<(config.rep.plankLockFrames + 1) {
      let joints = makeFrontalJoints(shoulderY: 0.54, elbowBend: 0.02, occludeElbows: false, asymmetricArms: false)
      output = detector.update(joints: joints, quality: quality, repTarget: 10)
    }

    for i in 0..<18 {
      let elbowBend: CGFloat = i % 2 == 0 ? 0.94 : 0.08
      let joints = makeFrontalJoints(shoulderY: 0.54, elbowBend: elbowBend, occludeElbows: false, asymmetricArms: false)
      output = detector.update(joints: joints, quality: quality, repTarget: 10)
    }

    XCTAssertEqual(output?.repCount, 0)
    XCTAssertNotEqual(output?.state, .repCounted)
  }

  func testFrontalCycleCountsExactlyOneRep() {
    let config = PushlyPoseConfig()
    let detector = PushupRepDetector(config: config)
    let quality = stableFloorQuality(visibleJointCount: 11)
    var output: RepDetectionOutput?

    for _ in 0..<(config.rep.plankLockFrames + 1) {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: 0.54, elbowBend: 0.02, occludeElbows: false, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }

    let cycle: [(CGFloat, CGFloat, Bool)] = [
      (0.56, 0.3, false),
      (0.58, 0.62, false),
      (0.60, 0.94, false),
      (0.60, 0.96, false),
      (0.58, 0.7, false),
      (0.56, 0.38, false),
      (0.54, 0.04, false),
      (0.54, 0.02, false)
    ]
    for (shoulderY, elbowBend, occluded) in cycle {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: shoulderY, elbowBend: elbowBend, occludeElbows: occluded, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }

    XCTAssertEqual(output?.repCount, 1)
  }

  func testFrontalCycleCountsWithoutVisibleNoseWhenFloorGeometryIsStable() {
    let config = PushlyPoseConfig()
    let detector = PushupRepDetector(config: config)
    let quality = stableFloorQuality(visibleJointCount: 10)
    var output: RepDetectionOutput?

    for _ in 0..<(config.rep.plankLockFrames + 1) {
      var joints = makeFrontalJoints(shoulderY: 0.54, elbowBend: 0.02, occludeElbows: false, asymmetricArms: false)
      joints.removeValue(forKey: .nose)
      output = detector.update(joints: joints, quality: quality, repTarget: 10)
    }

    let cycle: [(CGFloat, CGFloat, Bool)] = [
      (0.56, 0.3, false),
      (0.58, 0.62, false),
      (0.60, 0.94, false),
      (0.60, 0.96, false),
      (0.58, 0.7, false),
      (0.56, 0.38, false),
      (0.54, 0.04, false),
      (0.54, 0.02, false)
    ]
    for (shoulderY, elbowBend, occluded) in cycle {
      var joints = makeFrontalJoints(shoulderY: shoulderY, elbowBend: elbowBend, occludeElbows: occluded, asymmetricArms: false)
      joints.removeValue(forKey: .nose)
      output = detector.update(joints: joints, quality: quality, repTarget: 10)
    }

    XCTAssertEqual(output?.repCount, 1)
  }

  func testStartupDescendBridgeCountsFirstRepBeforeFullPlankLock() {
    let config = PushlyPoseConfig()
    let detector = PushupRepDetector(config: config)
    let quality = stableFloorQuality(visibleJointCount: 11)
    var output: RepDetectionOutput?
    var sawStartupBridge = false

    for _ in 0..<config.rep.startupDescendBridgeMinTopFrames {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: 0.54, elbowBend: 0.02, occludeElbows: false, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }

    XCTAssertEqual(output?.state, .bodyFound)

    let cycle: [(CGFloat, CGFloat, Bool)] = [
      (0.56, 0.3, false),
      (0.58, 0.62, false),
      (0.60, 0.94, false),
      (0.60, 0.96, false),
      (0.58, 0.7, false),
      (0.56, 0.38, false),
      (0.54, 0.04, false),
      (0.54, 0.02, false)
    ]
    for (shoulderY, elbowBend, occluded) in cycle {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: shoulderY, elbowBend: elbowBend, occludeElbows: occluded, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
      if output?.repDebug?.startupDescendBridgeUsed == true {
        sawStartupBridge = true
      }
    }

    XCTAssertTrue(sawStartupBridge)
    XCTAssertEqual(output?.repCount, 1)
  }

  func testEarlyDescendWithoutStartupTopEvidenceDoesNotCount() {
    let config = PushlyPoseConfig()
    let detector = PushupRepDetector(config: config)
    let quality = stableFloorQuality(visibleJointCount: 11)
    var output: RepDetectionOutput?

    // No top bootstrap frames before descent.
    let cycle: [(CGFloat, CGFloat, Bool)] = [
      (0.56, 0.3, false),
      (0.58, 0.62, false),
      (0.60, 0.94, false),
      (0.60, 0.96, false),
      (0.58, 0.7, false),
      (0.56, 0.38, false),
      (0.54, 0.04, false),
      (0.54, 0.02, false)
    ]
    for (shoulderY, elbowBend, occluded) in cycle {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: shoulderY, elbowBend: elbowBend, occludeElbows: occluded, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }

    XCTAssertEqual(output?.repCount, 0)
    XCTAssertEqual(output?.repDebug?.startupReady, false)
    XCTAssertEqual(output?.repDebug?.startBlockedReason, "startup_top_evidence_insufficient")
  }

  func testBottomOcclusionGraceAllowsRepCompletion() {
    let config = PushlyPoseConfig()
    let detector = PushupRepDetector(config: config)
    let quality = stableFloorQuality(visibleJointCount: 11)
    var output: RepDetectionOutput?

    for _ in 0..<(config.rep.plankLockFrames + 1) {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: 0.54, elbowBend: 0.02, occludeElbows: false, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }

    let cycle: [(CGFloat, CGFloat, Bool)] = [
      (0.56, 0.28, false),
      (0.58, 0.58, false),
      (0.60, 0.92, false),
      (0.60, 0.94, true),
      (0.60, 0.94, true),
      (0.60, 0.94, true),
      (0.58, 0.66, false),
      (0.56, 0.34, false),
      (0.54, 0.04, false),
      (0.54, 0.02, false)
    ]
    for (shoulderY, elbowBend, occluded) in cycle {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: shoulderY, elbowBend: elbowBend, occludeElbows: occluded, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }

    XCTAssertEqual(output?.repCount, 1)
  }

  func testBottomReacquireHoldBridgesShortDropAfterTrackingLossGrace() {
    let config = PushlyPoseConfig()
    let detector = PushupRepDetector(config: config)
    let quality = stableFloorQuality(visibleJointCount: 11)
    let bottomDipQuality = degradedBottomDipQuality(upperBodyCoverage: 0.23)
    var output: RepDetectionOutput?

    for _ in 0..<(config.rep.plankLockFrames + 1) {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: 0.54, elbowBend: 0.02, occludeElbows: false, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }

    let descendToBottom: [(CGFloat, CGFloat, Bool)] = [
      (0.56, 0.30, false),
      (0.58, 0.62, false),
      (0.60, 0.94, false),
      (0.60, 0.96, false)
    ]
    for (shoulderY, elbowBend, occluded) in descendToBottom {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: shoulderY, elbowBend: elbowBend, occludeElbows: occluded, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }
    XCTAssertEqual(output?.repDebug?.bottomReached, true)

    let dipFrames = max(config.rep.bottomOcclusionGraceFrames, config.rep.ascendingConfirmFrames + 2) + 1
    for _ in 0..<dipFrames {
      output = detector.update(
        joints: makeSparseFloorAnchorJoints(shoulderY: 0.60),
        quality: bottomDipQuality,
        repTarget: 10
      )
    }

    XCTAssertNotEqual(output?.repDebug?.resetReason, "body_not_found")
    XCTAssertEqual(output?.repDebug?.bottomReacquireState, "hold_active")
    XCTAssertEqual(output?.repCount, 0)
  }

  func testLongBottomLossStillResetsAfterReacquireHoldExpires() {
    let config = PushlyPoseConfig()
    let detector = PushupRepDetector(config: config)
    let quality = stableFloorQuality(visibleJointCount: 11)
    let bottomDipQuality = degradedBottomDipQuality(upperBodyCoverage: 0.23)
    var output: RepDetectionOutput?

    for _ in 0..<(config.rep.plankLockFrames + 1) {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: 0.54, elbowBend: 0.02, occludeElbows: false, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }

    let descendToBottom: [(CGFloat, CGFloat, Bool)] = [
      (0.56, 0.30, false),
      (0.58, 0.62, false),
      (0.60, 0.94, false),
      (0.60, 0.96, false)
    ]
    for (shoulderY, elbowBend, occluded) in descendToBottom {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: shoulderY, elbowBend: elbowBend, occludeElbows: occluded, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }
    XCTAssertEqual(output?.repDebug?.bottomReached, true)

    let longDropFrames = max(config.rep.bottomOcclusionGraceFrames, config.rep.ascendingConfirmFrames + 2) + 8
    for _ in 0..<longDropFrames {
      output = detector.update(
        joints: makeSparseFloorAnchorJoints(shoulderY: 0.60),
        quality: bottomDipQuality,
        repTarget: 10
      )
    }

    XCTAssertEqual(output?.repDebug?.bodyFound, false)
    XCTAssertEqual(output?.repDebug?.resetReason, "body_not_found")
    XCTAssertEqual(output?.repDebug?.whyRepDidNotCount, "body_not_found")
  }

  func testBottomHoldAloneDoesNotCreateFakeCount() {
    let config = PushlyPoseConfig()
    let detector = PushupRepDetector(config: config)
    let quality = stableFloorQuality(visibleJointCount: 11)
    let bottomDipQuality = degradedBottomDipQuality(upperBodyCoverage: 0.23)
    var output: RepDetectionOutput?

    for _ in 0..<(config.rep.plankLockFrames + 1) {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: 0.54, elbowBend: 0.02, occludeElbows: false, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }

    let descendToBottom: [(CGFloat, CGFloat, Bool)] = [
      (0.56, 0.30, false),
      (0.58, 0.62, false),
      (0.60, 0.94, false),
      (0.60, 0.96, false)
    ]
    for (shoulderY, elbowBend, occluded) in descendToBottom {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: shoulderY, elbowBend: elbowBend, occludeElbows: occluded, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }

    let holdOnlyFrames = max(config.rep.bottomOcclusionGraceFrames, config.rep.ascendingConfirmFrames + 2) + 2
    for _ in 0..<holdOnlyFrames {
      output = detector.update(
        joints: makeSparseFloorAnchorJoints(shoulderY: 0.60),
        quality: bottomDipQuality,
        repTarget: 10
      )
    }

    XCTAssertEqual(output?.repCount, 0)
    XCTAssertEqual(output?.repDebug?.repCommitted, false)
    XCTAssertNotEqual(output?.state, .repCounted)
  }

  func testHalfCycleDoesNotCountAndExposesCountGateReason() {
    let config = PushlyPoseConfig()
    let detector = PushupRepDetector(config: config)
    let quality = stableFloorQuality(visibleJointCount: 11)
    var output: RepDetectionOutput?

    for _ in 0..<(config.rep.plankLockFrames + 1) {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: 0.54, elbowBend: 0.02, occludeElbows: false, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }

    let halfCycle: [(CGFloat, CGFloat, Bool)] = [
      (0.56, 0.3, false),
      (0.58, 0.62, false),
      (0.60, 0.94, false),
      (0.60, 0.96, false),
      (0.59, 0.8, false)
    ]
    for (shoulderY, elbowBend, occluded) in halfCycle {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: shoulderY, elbowBend: elbowBend, occludeElbows: occluded, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }

    XCTAssertEqual(output?.repCount, 0)
    XCTAssertEqual(output?.repDebug?.countGateBlocked, true)
    XCTAssertNotNil(output?.repDebug?.countGateBlockReason)
  }

  func testRearmAllowsContinuousCadenceButStillBlocksImmediateDoubleCount() {
    let config = PushlyPoseConfig()
    let detector = PushupRepDetector(config: config)
    let quality = stableFloorQuality(visibleJointCount: 11)
    var output: RepDetectionOutput?

    func runFullCycle() {
      let cycle: [(CGFloat, CGFloat, Bool)] = [
        (0.56, 0.3, false),
        (0.58, 0.62, false),
        (0.60, 0.94, false),
        (0.60, 0.96, false),
        (0.58, 0.7, false),
        (0.56, 0.38, false),
        (0.54, 0.04, false),
        (0.54, 0.02, false)
      ]
      for (shoulderY, elbowBend, occluded) in cycle {
        output = detector.update(
          joints: makeFrontalJoints(shoulderY: shoulderY, elbowBend: elbowBend, occludeElbows: occluded, asymmetricArms: false),
          quality: quality,
          repTarget: 10
        )
      }
    }

    for _ in 0..<(config.rep.plankLockFrames + 1) {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: 0.54, elbowBend: 0.02, occludeElbows: false, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }

    runFullCycle()
    XCTAssertEqual(output?.repCount, 1)

    // Replaying deep-bottom frames right away must not trigger a duplicate without a real new cycle.
    for _ in 0..<3 {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: 0.60, elbowBend: 0.96, occludeElbows: false, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }
    XCTAssertEqual(output?.repCount, 1)

    // Only a very short top reset should be enough to start the next rep in continuous cadence.
    for _ in 0..<2 {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: 0.54, elbowBend: 0.02, occludeElbows: false, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }

    runFullCycle()
    XCTAssertEqual(output?.repCount, 2, "Continuous reps should count after short top recovery.")
  }

  func testSlowCadenceAndFastCadenceBothCountWithoutDoubleCounting() {
    let config = PushlyPoseConfig()
    let detector = PushupRepDetector(config: config)
    let quality = stableFloorQuality(visibleJointCount: 11)
    var output: RepDetectionOutput?

    func runCycle(frames: [(CGFloat, CGFloat, Bool)]) {
      for (shoulderY, elbowBend, occluded) in frames {
        output = detector.update(
          joints: makeFrontalJoints(shoulderY: shoulderY, elbowBend: elbowBend, occludeElbows: occluded, asymmetricArms: false),
          quality: quality,
          repTarget: 10
        )
      }
    }

    for _ in 0..<(config.rep.plankLockFrames + 1) {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: 0.54, elbowBend: 0.02, occludeElbows: false, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }

    let slowCycle: [(CGFloat, CGFloat, Bool)] = [
      (0.55, 0.14, false), (0.56, 0.26, false), (0.58, 0.48, false),
      (0.60, 0.86, false), (0.60, 0.96, false), (0.60, 0.96, false),
      (0.59, 0.78, false), (0.58, 0.62, false), (0.56, 0.36, false),
      (0.54, 0.06, false), (0.54, 0.02, false), (0.54, 0.02, false)
    ]
    runCycle(frames: slowCycle)
    XCTAssertEqual(output?.repCount, 1)

    let topResetFrames = max(2, config.rep.repRearmConfirmFrames + 1)
    for _ in 0..<topResetFrames {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: 0.54, elbowBend: 0.02, occludeElbows: false, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }
    XCTAssertEqual(output?.repDebug?.rearmGate, true)

    let fastCycle: [(CGFloat, CGFloat, Bool)] = [
      (0.57, 0.38, false),
      (0.60, 0.96, false),
      (0.60, 0.96, false),
      (0.56, 0.30, false),
      (0.54, 0.02, false)
    ]
    runCycle(frames: fastCycle)

    XCTAssertEqual(output?.repCount, 2)
  }

  func testThreeValidRepsInSequenceRemainStable() {
    let config = PushlyPoseConfig()
    let detector = PushupRepDetector(config: config)
    let quality = stableFloorQuality(visibleJointCount: 11)
    var output: RepDetectionOutput?

    func runFullCycle() {
      let cycle: [(CGFloat, CGFloat, Bool)] = [
        (0.56, 0.3, false),
        (0.58, 0.62, false),
        (0.60, 0.94, false),
        (0.60, 0.96, false),
        (0.58, 0.7, false),
        (0.56, 0.38, false),
        (0.54, 0.04, false),
        (0.54, 0.02, false)
      ]
      for (shoulderY, elbowBend, occluded) in cycle {
        output = detector.update(
          joints: makeFrontalJoints(shoulderY: shoulderY, elbowBend: elbowBend, occludeElbows: occluded, asymmetricArms: false),
          quality: quality,
          repTarget: 10
        )
      }
    }

    for _ in 0..<(config.rep.plankLockFrames + 1) {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: 0.54, elbowBend: 0.02, occludeElbows: false, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }

    for expectedCount in 1...3 {
      runFullCycle()
      XCTAssertEqual(output?.repCount, expectedCount)
      if expectedCount < 3 {
        for _ in 0..<2 {
          output = detector.update(
            joints: makeFrontalJoints(shoulderY: 0.54, elbowBend: 0.02, occludeElbows: false, asymmetricArms: false),
            quality: quality,
            repTarget: 10
          )
        }
        XCTAssertEqual(output?.repDebug?.rearmGate, true)
      }
    }
  }

  func testShortBodyDropDuringRearmDoesNotImmediatelyResetCycle() {
    let config = PushlyPoseConfig()
    let detector = PushupRepDetector(config: config)
    let quality = stableFloorQuality(visibleJointCount: 11)
    var output: RepDetectionOutput?

    func runFullCycle() {
      let cycle: [(CGFloat, CGFloat, Bool)] = [
        (0.56, 0.3, false),
        (0.58, 0.62, false),
        (0.60, 0.94, false),
        (0.60, 0.96, false),
        (0.58, 0.7, false),
        (0.56, 0.38, false),
        (0.54, 0.04, false),
        (0.54, 0.02, false)
      ]
      for (shoulderY, elbowBend, occluded) in cycle {
        output = detector.update(
          joints: makeFrontalJoints(shoulderY: shoulderY, elbowBend: elbowBend, occludeElbows: occluded, asymmetricArms: false),
          quality: quality,
          repTarget: 10
        )
      }
    }

    for _ in 0..<(config.rep.plankLockFrames + 1) {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: 0.54, elbowBend: 0.02, occludeElbows: false, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }
    runFullCycle()
    XCTAssertEqual(output?.repCount, 1)
    XCTAssertEqual(output?.repDebug?.repRearmPending, true)

    // Sparse but still plausible floor anchors: shoulder + arm segment + hip.
    for _ in 0..<2 {
      output = detector.update(
        joints: makeSparseFloorAnchorJoints(shoulderY: 0.54),
        quality: quality,
        repTarget: 10
      )
    }

    XCTAssertEqual(output?.state, .bodyFound)
    XCTAssertEqual(output?.repDebug?.bodyFound, true)
    XCTAssertNotEqual(output?.repDebug?.whyRepDidNotCount, "body_not_found")
    XCTAssertNotEqual(output?.repDebug?.resetReason, "body_not_found")
  }

  func testLongTrackingLossStillTriggersBodyNotFoundReset() {
    let config = PushlyPoseConfig()
    let detector = PushupRepDetector(config: config)
    let quality = stableFloorQuality(visibleJointCount: 11)
    var output: RepDetectionOutput?

    func runFullCycle() {
      let cycle: [(CGFloat, CGFloat, Bool)] = [
        (0.56, 0.3, false),
        (0.58, 0.62, false),
        (0.60, 0.94, false),
        (0.60, 0.96, false),
        (0.58, 0.7, false),
        (0.56, 0.38, false),
        (0.54, 0.04, false),
        (0.54, 0.02, false)
      ]
      for (shoulderY, elbowBend, occluded) in cycle {
        output = detector.update(
          joints: makeFrontalJoints(shoulderY: shoulderY, elbowBend: elbowBend, occludeElbows: occluded, asymmetricArms: false),
          quality: quality,
          repTarget: 10
        )
      }
    }

    for _ in 0..<(config.rep.plankLockFrames + 1) {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: 0.54, elbowBend: 0.02, occludeElbows: false, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }
    runFullCycle()
    XCTAssertEqual(output?.repCount, 1)

    for _ in 0..<5 {
      output = detector.update(joints: [:], quality: quality, repTarget: 10)
    }

    XCTAssertEqual(output?.repDebug?.bodyFound, false)
    XCTAssertEqual(output?.repDebug?.whyRepDidNotCount, "body_not_found")
    XCTAssertEqual(output?.repDebug?.resetReason, "body_not_found")
  }

  func testShortQualityDipAfterRepOneDoesNotBreakRearm() {
    let config = PushlyPoseConfig()
    let detector = PushupRepDetector(config: config)
    let quality = stableFloorQuality(visibleJointCount: 11)
    let dipQuality = TrackingQuality(
      trackingQuality: 0.2,
      renderQuality: 0.56,
      logicQuality: 0.16,
      pushupFloorModeActive: true,
      bodyVisibilityState: .partial,
      trackingState: .tracking,
      poseTrackingState: .trackingUpperBody,
      poseMode: .upperBody,
      reasonCodes: ["low_light"],
      spreadScore: 0.55,
      smoothedSpread: 0.55,
      visibleJointCount: 7,
      upperBodyRenderableCount: 5,
      reliability: 0.52,
      roiCoverage: 0.38,
      fullBodyCoverage: 0.24,
      upperBodyCoverage: 0.72,
      handCoverage: 0.6,
      wristRetention: 0.72,
      inferredJointRatio: 0.34,
      modeConfidence: 0.68
    )
    var output: RepDetectionOutput?

    func runFullCycle() {
      let cycle: [(CGFloat, CGFloat, Bool)] = [
        (0.56, 0.3, false),
        (0.58, 0.62, false),
        (0.60, 0.94, false),
        (0.60, 0.96, false),
        (0.58, 0.7, false),
        (0.56, 0.38, false),
        (0.54, 0.04, false),
        (0.54, 0.02, false)
      ]
      for (shoulderY, elbowBend, occluded) in cycle {
        output = detector.update(
          joints: makeFrontalJoints(shoulderY: shoulderY, elbowBend: elbowBend, occludeElbows: occluded, asymmetricArms: false),
          quality: quality,
          repTarget: 10
        )
      }
    }

    for _ in 0..<(config.rep.plankLockFrames + 1) {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: 0.54, elbowBend: 0.02, occludeElbows: false, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }
    runFullCycle()
    XCTAssertEqual(output?.repCount, 1)
    XCTAssertEqual(output?.repDebug?.repRearmPending, true)

    for _ in 0..<2 {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: 0.54, elbowBend: 0.02, occludeElbows: false, asymmetricArms: false),
        quality: dipQuality,
        repTarget: 10
      )
    }
    for _ in 0..<3 {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: 0.54, elbowBend: 0.02, occludeElbows: false, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }

    XCTAssertEqual(output?.repDebug?.rearmGate, true)
    XCTAssertEqual(output?.repDebug?.repRearmPending, false)

    runFullCycle()
    XCTAssertEqual(output?.repCount, 2)
  }

  func testRearmStaysBlockedWithoutRealTopRecovery() {
    let config = PushlyPoseConfig()
    let detector = PushupRepDetector(config: config)
    let quality = stableFloorQuality(visibleJointCount: 11)
    var output: RepDetectionOutput?

    func runFullCycle() {
      let cycle: [(CGFloat, CGFloat, Bool)] = [
        (0.56, 0.3, false),
        (0.58, 0.62, false),
        (0.60, 0.94, false),
        (0.60, 0.96, false),
        (0.58, 0.7, false),
        (0.56, 0.38, false),
        (0.54, 0.04, false),
        (0.54, 0.02, false)
      ]
      for (shoulderY, elbowBend, occluded) in cycle {
        output = detector.update(
          joints: makeFrontalJoints(shoulderY: shoulderY, elbowBend: elbowBend, occludeElbows: occluded, asymmetricArms: false),
          quality: quality,
          repTarget: 10
        )
      }
    }

    for _ in 0..<(config.rep.plankLockFrames + 1) {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: 0.54, elbowBend: 0.02, occludeElbows: false, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }
    runFullCycle()
    XCTAssertEqual(output?.repCount, 1)
    XCTAssertEqual(output?.repDebug?.repRearmPending, true)

    let noTopResetFrames: [(CGFloat, CGFloat)] = [
      (0.57, 0.4),
      (0.59, 0.74),
      (0.61, 0.96),
      (0.61, 0.96),
      (0.60, 0.92),
      (0.60, 0.92),
      (0.59, 0.86)
    ]
    for (shoulderY, elbowBend) in noTopResetFrames {
      output = detector.update(
        joints: makeFrontalJoints(shoulderY: shoulderY, elbowBend: elbowBend, occludeElbows: false, asymmetricArms: false),
        quality: quality,
        repTarget: 10
      )
    }

    XCTAssertEqual(output?.repCount, 1)
    XCTAssertEqual(output?.repDebug?.rearmGate, false)
    XCTAssertEqual(output?.repDebug?.repRearmPending, true)
    XCTAssertNotEqual(output?.repDebug?.rearmBlockedReason, "rearm_confirming")
  }

  private func stableFloorQuality(visibleJointCount: Int) -> TrackingQuality {
    TrackingQuality(
      trackingQuality: 0.82,
      renderQuality: 0.8,
      logicQuality: 0.74,
      pushupFloorModeActive: true,
      bodyVisibilityState: .assisted,
      trackingState: .tracking,
      poseTrackingState: .trackingFullBody,
      poseMode: .fullBody,
      reasonCodes: [],
      spreadScore: 0.62,
      smoothedSpread: 0.62,
      visibleJointCount: visibleJointCount,
      upperBodyRenderableCount: 7,
      reliability: 0.86,
      roiCoverage: 0.5,
      fullBodyCoverage: 0.44,
      upperBodyCoverage: 0.94,
      handCoverage: 0.86,
      wristRetention: 0.98,
      inferredJointRatio: 0.12,
      modeConfidence: 0.86
    )
  }

  private func degradedBottomDipQuality(upperBodyCoverage: Double) -> TrackingQuality {
    TrackingQuality(
      trackingQuality: 0.28,
      renderQuality: 0.19,
      logicQuality: 0.18,
      pushupFloorModeActive: true,
      bodyVisibilityState: .partial,
      trackingState: .tracking,
      poseTrackingState: .trackingUpperBody,
      poseMode: .upperBody,
      reasonCodes: ["bottom_occlusion"],
      spreadScore: 0.5,
      smoothedSpread: 0.5,
      visibleJointCount: 3,
      upperBodyRenderableCount: 2,
      reliability: 0.44,
      roiCoverage: 0.32,
      fullBodyCoverage: 0.18,
      upperBodyCoverage: upperBodyCoverage,
      handCoverage: 0.34,
      wristRetention: 0.4,
      inferredJointRatio: 0.42,
      modeConfidence: 0.52
    )
  }

  private func makeFrontalJoints(
    shoulderY: CGFloat,
    elbowBend: CGFloat,
    occludeElbows: Bool,
    asymmetricArms: Bool
  ) -> [PushlyJointName: TrackedJoint] {
    let clampedBend = max(0, min(1, elbowBend))
    let rightBend = asymmetricArms ? clampedBend * 0.25 : clampedBend
    let hipY = shoulderY + 0.10
    let ankleY = shoulderY + 0.20
    let leftElbow = CGPoint(x: 0.34 + clampedBend * 0.03, y: shoulderY + clampedBend * 0.06)
    let leftWrist = CGPoint(x: 0.26 + clampedBend * 0.04, y: shoulderY + clampedBend * 0.01)
    let rightElbow = CGPoint(x: 0.66 - rightBend * 0.03, y: shoulderY + rightBend * 0.06)
    let rightWrist = CGPoint(x: 0.74 - rightBend * 0.04, y: shoulderY + rightBend * 0.01)

    return [
      .nose: trackedJoint(.nose, x: 0.5, y: shoulderY + 0.03, render: 0.92, logic: 0.92, source: .measured, now: CACurrentMediaTime()),
      .leftShoulder: trackedJoint(.leftShoulder, x: 0.42, y: shoulderY, render: 0.92, logic: 0.92, source: .measured, now: CACurrentMediaTime()),
      .rightShoulder: trackedJoint(.rightShoulder, x: 0.58, y: shoulderY, render: 0.92, logic: 0.92, source: .measured, now: CACurrentMediaTime()),
      .leftElbow: trackedJoint(
        .leftElbow,
        x: leftElbow.x,
        y: leftElbow.y,
        render: occludeElbows ? 0 : 0.88,
        logic: occludeElbows ? 0 : 0.88,
        source: occludeElbows ? .missing : .measured,
        now: CACurrentMediaTime()
      ),
      .rightElbow: trackedJoint(
        .rightElbow,
        x: rightElbow.x,
        y: rightElbow.y,
        render: occludeElbows ? 0 : 0.88,
        logic: occludeElbows ? 0 : 0.88,
        source: occludeElbows ? .missing : .measured,
        now: CACurrentMediaTime()
      ),
      .leftWrist: trackedJoint(
        .leftWrist,
        x: leftWrist.x,
        y: leftWrist.y,
        render: occludeElbows ? 0 : 0.86,
        logic: occludeElbows ? 0 : 0.86,
        source: occludeElbows ? .missing : .measured,
        now: CACurrentMediaTime()
      ),
      .rightWrist: trackedJoint(
        .rightWrist,
        x: rightWrist.x,
        y: rightWrist.y,
        render: occludeElbows ? 0 : 0.86,
        logic: occludeElbows ? 0 : 0.86,
        source: occludeElbows ? .missing : .measured,
        now: CACurrentMediaTime()
      ),
      .leftHip: trackedJoint(.leftHip, x: 0.46, y: hipY, render: 0.9, logic: 0.88, source: .measured, now: CACurrentMediaTime()),
      .rightHip: trackedJoint(.rightHip, x: 0.54, y: hipY, render: 0.9, logic: 0.88, source: .measured, now: CACurrentMediaTime()),
      .leftAnkle: trackedJoint(.leftAnkle, x: 0.49, y: ankleY, render: 0.86, logic: 0.84, source: .measured, now: CACurrentMediaTime()),
      .rightAnkle: trackedJoint(.rightAnkle, x: 0.51, y: ankleY, render: 0.86, logic: 0.84, source: .measured, now: CACurrentMediaTime())
    ]
  }

  private func makeSparseFloorAnchorJoints(shoulderY: CGFloat) -> [PushlyJointName: TrackedJoint] {
    [
      .leftShoulder: trackedJoint(.leftShoulder, x: 0.42, y: shoulderY, render: 0.86, logic: 0.82, source: .measured, now: CACurrentMediaTime()),
      .leftElbow: trackedJoint(.leftElbow, x: 0.36, y: shoulderY + 0.05, render: 0.82, logic: 0.78, source: .measured, now: CACurrentMediaTime()),
      .leftHip: trackedJoint(.leftHip, x: 0.46, y: shoulderY + 0.10, render: 0.8, logic: 0.74, source: .measured, now: CACurrentMediaTime())
    ]
  }

  private func trackedJoint(
    _ name: PushlyJointName,
    x: CGFloat,
    y: CGFloat,
    render: Float,
    logic: Float,
    source: PushlyJointSourceType,
    now: TimeInterval
  ) -> TrackedJoint {
    TrackedJoint(
      name: name,
      rawPosition: CGPoint(x: x, y: y),
      smoothedPosition: CGPoint(x: x, y: y),
      velocity: .zero,
      rawConfidence: render,
      renderConfidence: render,
      logicConfidence: logic,
      visibility: render,
      presence: render,
      inFrame: true,
      sourceType: source,
      timestamp: now
    )
  }
}

final class InstructionEngineTests: XCTestCase {
  func testPushupTooCloseInstructionWinsWhenUpperBodyStillVisible() {
    let engine = InstructionEngine()
    let quality = TrackingQuality(
      trackingQuality: 0.72,
      renderQuality: 0.75,
      logicQuality: 0.66,
      pushupFloorModeActive: false,
      bodyVisibilityState: .assisted,
      trackingState: .tracking,
      poseTrackingState: .trackingUpperBody,
      poseMode: .upperBody,
      reasonCodes: ["framing_tight"],
      spreadScore: 0.18,
      smoothedSpread: 0.18,
      visibleJointCount: 7,
      upperBodyRenderableCount: 6,
      reliability: 0.84,
      roiCoverage: 0.54,
      fullBodyCoverage: 0.24,
      upperBodyCoverage: 0.76,
      handCoverage: 0.7,
      wristRetention: 0.9,
      inferredJointRatio: 0.2,
      modeConfidence: 0.82
    )

    var instruction: String?
    let start = CACurrentMediaTime()
    for step in 0..<6 {
      instruction = engine.makeInstruction(
        quality: quality,
        repState: .bodyFound,
        blockedReasons: [],
        lowLightDetected: false,
        requiresFullBody: false,
        now: start + Double(step) * 0.3
      )
    }

    XCTAssertEqual(instruction, "Zu nah dran. Geh 20 bis 30 cm weiter weg für stabile Push-up-Erkennung.")
  }
}

final class PoseBackendCoordinatorTests: XCTestCase {
  private struct MockBackend: PoseBackend {
    let kind: PoseBackendKind
    let isAvailable: Bool
    let detectedCount: Int
    let upperBodyCoverage: Double
    let segmentationAssistActive: Bool
    let segmentationBottomAssistActive: Bool

    init(
      kind: PoseBackendKind,
      isAvailable: Bool,
      detectedCount: Int,
      upperBodyCoverage: Double = 0.6,
      segmentationAssistActive: Bool = false,
      segmentationBottomAssistActive: Bool = false
    ) {
      self.kind = kind
      self.isAvailable = isAvailable
      self.detectedCount = detectedCount
      self.upperBodyCoverage = upperBodyCoverage
      self.segmentationAssistActive = segmentationAssistActive
      self.segmentationBottomAssistActive = segmentationBottomAssistActive
    }

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
        modeConfidence: has ? upperBodyCoverage : 0,
        coverage: has ? PoseVisibilityCoverage(upperBodyCoverage: upperBodyCoverage, fullBodyCoverage: 0.1, handCoverage: 0.4) : .empty,
        backendDiagnostics: PoseBackendDiagnostics(
          rawObservationCount: has ? 1 : 0,
          trackedJointCount: detectedCount,
          averageJointConfidence: has ? 0.9 : 0,
          roiUsed: frame.roiHint,
          durationMs: 2,
          modeConfidence: has ? upperBodyCoverage : 0,
          reliability: has ? 0.8 : 0,
          handRefinedJointCount: 0,
          segmentationAssistActive: segmentationAssistActive,
          segmentationBottomAssistActive: segmentationBottomAssistActive
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

  func testKeepsMediaPipeWhenSegmentationAssistProtectsLowJointFrame() throws {
    let config = PushlyPoseConfig()
    let coordinator = PoseBackendCoordinator(
      config: config,
      mediaPipeBackend: MockBackend(
        kind: .mediapipe,
        isAvailable: true,
        detectedCount: 1,
        upperBodyCoverage: 0.1,
        segmentationAssistActive: true
      ),
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

    XCTAssertEqual(result.backend, .mediapipe)
    XCTAssertEqual(coordinator.lastBackendDebugState.activeBackend, .mediapipe)
    XCTAssertFalse(coordinator.lastBackendDebugState.fallbackUsed)
  }

  func testAutoModeDoesNotDemoteMediaPipeOnSegmentationProtectedSequence() throws {
    let config = PushlyPoseConfig()
    let coordinator = PoseBackendCoordinator(
      config: config,
      mediaPipeBackend: MockBackend(
        kind: .mediapipe,
        isAvailable: true,
        detectedCount: 1,
        upperBodyCoverage: 0.1,
        segmentationBottomAssistActive: true
      ),
      visionFallbackBackend: MockBackend(kind: .visionFallback, isAvailable: true, detectedCount: 6)
    )

    var timing = CMSampleTimingInfo()
    var formatDesc: CMFormatDescription?
    var sample: CMSampleBuffer?
    CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: kCMVideoCodecType_422YpCbCr8, width: 4, height: 4, extensions: nil, formatDescriptionOut: &formatDesc)
    CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: nil, formatDescription: formatDesc, sampleCount: 0, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample)

    for step in 0..<14 {
      _ = try coordinator.process(
        frame: PoseFrameInput(
          sampleBuffer: sample!,
          orientation: .up,
          mirrored: false,
          roiHint: nil,
          timestamp: CACurrentMediaTime() + Double(step) * 0.033,
          targetMode: .upperBody,
          reacquireSource: .none,
          relockSuccessCount: 0,
          relockFailureCount: 0
        )
      )
    }

    XCTAssertEqual(coordinator.lastBackendDebugState.activeBackend, .mediapipe)
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
      pushupFloorModeActive: false,
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

    let rep = RepDetectionOutput(state: .plankLocked, repCount: 1, formEvidenceScore: 0.77, blockedReasons: [])

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
        inferredJointRatio: 0.1,
        measuredJointCount: 6,
        lowConfidenceMeasuredJointCount: 1,
        inferredJointCount: 0,
        predictedJointCount: 0,
        missingJointCount: 11,
        pushupBlockedReasons: [],
        sideLockSwapped: false,
        sideSwapEvidenceStreak: 0,
        sideKeepEvidenceStreak: 2,
        sideSwapAppliedThisFrame: false,
        tooCloseFallbackActive: false,
        tooCloseInferredHipCount: 0,
        cameraProcessingBacklog: 0.1,
        cameraAverageProcessingMs: 14
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

  func testDiagnosticsSummaryCountsTooCloseAndSideSwapFrames() throws {
    let config = PushlyPoseConfig()
    let diagnostics = PoseDiagnostics(config: config)
    diagnostics.beginSession(cameraPosition: .front, mirrored: true, activeBackend: .mediapipe, fallbackAvailable: true)
    diagnostics.recordReacquireAttempt(source: .face)
    diagnostics.recordReacquireEnd(success: true, source: .face)

    for i in 0..<4 {
      diagnostics.recordFrameReceived()
      diagnostics.recordProcessedFrame(
        frameIndex: i,
        timestamp: CACurrentMediaTime() + Double(i) * 0.03,
        backend: .mediapipe,
        mode: .upperBody,
        trackingState: i == 1 ? .lost : .trackingUpperBody,
        visibleJointCount: 6,
        upperBodyCoverage: 0.72,
        fullBodyCoverage: 0.18,
        handCoverage: 0.58,
        averageJointConfidence: 0.78,
        reliability: 0.74,
        roi: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.45),
        mirrored: true,
        orientation: .leftMirrored,
        inferenceDurationMs: 11,
        pipelineDurationMs: 17,
        renderedJointCount: 6,
        inferredJointRatio: 0.12,
        measuredJointCount: 5,
        lowConfidenceMeasuredJointCount: 1,
        inferredJointCount: i < 2 ? 2 : 0,
        predictedJointCount: 0,
        missingJointCount: 10,
        pushupBlockedReasons: [],
        sideLockSwapped: i >= 2,
        sideSwapEvidenceStreak: i >= 2 ? 5 : 0,
        sideKeepEvidenceStreak: i >= 2 ? 0 : 4,
        sideSwapAppliedThisFrame: i == 2,
        tooCloseFallbackActive: i < 2,
        tooCloseInferredHipCount: i < 2 ? 2 : 0,
        cameraProcessingBacklog: 0.08,
        cameraAverageProcessingMs: 13
      )
    }
    diagnostics.endSession(reason: "unit_test_counts")

    let expect = expectation(description: "export-counts")
    var exportedPath: String?
    diagnostics.exportToDisk(configSnapshot: ["unit": "counts"]) { result in
      if case .success(let url) = result {
        exportedPath = url.path
      }
      expect.fulfill()
    }
    wait(for: [expect], timeout: 2.0)

    XCTAssertNotNil(exportedPath)
    let data = try Data(contentsOf: URL(fileURLWithPath: exportedPath!))
    let decoded = try JSONDecoder().decode(PoseDebugExport.self, from: data)
    XCTAssertEqual(decoded.summary.reacquireAttempts, 1)
    XCTAssertEqual(decoded.summary.tooCloseFallbackFrameCount, 2)
    XCTAssertEqual(decoded.summary.tooCloseInferredHipTotal, 4)
    XCTAssertEqual(decoded.summary.sideSwapAppliedFrameCount, 1)
    XCTAssertEqual(decoded.summary.lostTrackingFrameCount, 1)
  }
}
#endif
#endif
