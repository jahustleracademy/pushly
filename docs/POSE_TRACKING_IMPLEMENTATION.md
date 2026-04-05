# Pose Tracking Implementation (MediaPipe-First Rebuild)

## Why the old approach was replaced
The previous native pipeline was centered on Vision/MLKit-only landmark extraction and was too fragile for close-range upper-body scenes.
Key failures were:
- upper-body-only framing sometimes degraded to `lost` because lower-body evidence was missing,
- unstable backend behavior across reacquire cycles,
- limited mode-aware quality and instruction signaling.

This rebuild moves the primary stack to MediaPipe, keeps Vision as fallback/reacquire support, and makes upper-body vs full-body tracking explicit.

## New architecture
### 1. Camera input and telemetry
- `CameraCaptureManager` remains non-blocking (`AVCaptureVideoDataOutput` with late-frame discard).
- Added adaptive capture FPS logic driven by processing FPS, drop-rate, low-light, and thermal state.
- Telemetry now includes capture FPS, processing FPS (bridge), dropped frame breakdown, low-light boost, and exposure duration.

### 2. Canonical pose domain model
Implemented in `PushlyPoseTypes.swift`:
- canonical joints include head/nose, shoulders, elbows, wrists, hand anchors, hips, knees, ankles, and optional foot anchors,
- each joint carries confidence, visibility/presence, in-frame status, source type (measured/inferred/predicted),
- explicit mode/state model:
  - `poseMode`: `upperBody | fullBody | unknown`
  - `poseTrackingState`: `trackingUpperBody | trackingFullBody | reacquiring | lost`
- coverage model:
  - upper-body coverage,
  - full-body coverage,
  - hand coverage.

### 3. Backend abstraction
Implemented in `PoseBackend.swift`:
- `PoseFrameInput` normalizes frame/timestamp/orientation/mirroring/ROI hints.
- `PoseBackend` protocol is backend-agnostic and returns canonical `PoseProcessingResult`.
- `PoseBackendCoordinator` chooses primary backend and quality-based fallback.

### 4. Tracking backends
- **Primary**: `MediaPipePoseBackend`
  - uses `PoseLandmarker` in video mode,
  - optional `HandLandmarker` wrist refinement for hand anchors,
  - maps MediaPipe landmarks to canonical joints,
  - converts MediaPipe coordinates into canonical bottom-left normalized space.
- **Fallback**: `VisionPoseBackend`
  - used as fallback when MediaPipe confidence/coverage drops or backend errors.
- **Legacy**: `MLKitPoseBackend`
  - retained as non-active compatibility stub only.

### 5. Detector-first reacquire and continuity
- `ReacquireDetector`: face-first, upper-body-second reacquire hints.
- `TrackContinuityManager`:
  - explicit mode hysteresis for entering/exiting full-body,
  - upper-body tracking is valid and does not collapse to lost when legs are absent,
  - full-frame periodic refresh prevents ROI lock-in,
  - reacquire source is tracked (`face`, `upperBody`, `fullFrame`, `previousTrack`, `none`).

### 6. Temporal stabilization and rendering
- `TemporalJointTracker` updated for canonical model and source typing.
- Predicted joints are short-lived and decayed conservatively.
- `SkeletonRenderer` now supports optional hand/foot anchors and predicted/inferred visual separation.

### 7. Mode-aware quality and instruction logic
- `TrackingQualityEvaluator` now includes:
  - mode-aware coverage scoring,
  - hand coverage,
  - mode confidence,
  - inferred/predicted ratio penalties,
  - lower-body penalties only when full-body mode is active.
- `InstructionEngine` now distinguishes:
  - valid upper-body tracking,
  - full-body-required-but-missing-lower-body guidance,
  - true no-body/lost states.

### 8. JS/native bridge compatibility
`JSBridgePayloadMapper` preserves existing fields and adds optional fields:
- `poseBackend`
- `poseMode`
- `poseTrackingState`
- `trackingContinuityState`
- `upperBodyCoverage`
- `fullBodyCoverage`
- `handCoverage`
- `reacquireSource`
- `processingFPS`
- `lowLightActive`
- `modeConfidence`

TypeScript types in `PushlyNative.types.ts` were expanded accordingly while preserving legacy fields (`trackingState`, `bodyMode`).

## Backend selection logic
- Default: `auto`.
- `auto` prefers MediaPipe when available.
- Coordinator falls back to Vision on low-confidence/low-coverage or backend errors.
- Runtime override prop: `poseBackendMode = auto | mediapipe | vision` (legacy `mlkit` maps to MediaPipe override behavior).

## Coordinate and ROI hardening
`PoseCoordinateConverter` now centralizes:
- ROI clamping with minimum size,
- mirroring transforms,
- orientation remap for Vision ROI,
- MediaPipe top-left-origin to canonical bottom-left conversion.
- canonical-to-preview projection that accounts for `resizeAspectFill` crop, so skeleton rendering aligns to the real preview content rect (not raw view bounds).

## Config flags
`PushlyPoseConfig` now centralizes:
- backend preference (`auto | mediapipe | vision`),
- MediaPipe model names and hand-refinement thresholds,
- mode hysteresis windows,
- detector/full-frame refresh cadence,
- ROI padding/min size,
- smoothing thresholds,
- camera adaptation knobs,
- diagnostics verbosity and instruction mode requirements.

## Dependency and model packaging
- iOS pods now use `MediaPipeTasksVision`.
- Module bundles model resources from `modules/pushly-native/ios/Models/*.task`.
- Included models:
  - `pose_landmarker_lite.task`
  - `hand_landmarker.task`

## Manual QA checklist
1. Close upper-body-only framing (front camera):
   - expect `poseMode=upperBody`, `poseTrackingState=trackingUpperBody`, no false `lost`.
2. Full-body framing:
   - expect `poseMode=fullBody`, knees/ankles/feet rendered when visible.
3. Fast arm movement:
   - wrists/hands update without heavy lag; no floaty overlay.
4. Low-light scene:
   - low-light guidance appears; tracking degrades gracefully, not immediate loss.
5. Mirrored front camera alignment:
   - skeleton should remain tightly aligned left/right with user motion.
6. Leave and re-enter frame:
   - reacquire source transitions through face/upper-body/full-frame and relocks.
7. Partial occlusion:
   - invisible joints are not over-asserted as fully known.
8. Mode switching near threshold:
   - no 1-frame flicker between upper/full modes.
9. Fallback behavior:
   - if MediaPipe unavailable/error, Vision fallback still emits canonical payloads.
10. Processing pressure:
   - verify debug telemetry shows `cameraProcessingBacklog` and `cameraAverageProcessingMs` changing under heavy load.

## Native test wiring
- `PushlyNative.podspec` now includes a `test_spec` (`UnitTests`) that picks up `*Tests.swift`.
- After `pod install`, run tests from workspace with `xcodebuild` against generated Pod test schemes (or via Xcode Test navigator).

## Notes on conservative choices
- Full-body penalties are mode-aware; missing legs do not invalidate upper-body tracking.
- Hand refinement never blocks body tracking.
- Prediction windows are intentionally short to avoid “ghost joints.”
