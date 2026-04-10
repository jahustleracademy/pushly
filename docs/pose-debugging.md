# Pose Pipeline Debugging (iOS)

## What Is Logged
- Structured runtime logs use Apple's unified logging (`Logger` / `OSLog`) with categories:
  - `camera`
  - `poseBackend`
  - `continuity`
  - `reacquire`
  - `renderer`
  - `bridge`
  - `diagnostics`
  - `performance`
- Event logs include:
  - tracking start/stop
  - backend init/unavailable/switch
  - mode and tracking-state transitions
  - reacquire begin/end
  - low-light state changes
  - orientation/mirroring/geometry snapshots
  - repeated empty backend outputs
  - ROI clamp/reset warnings
  - camera drop-rate and overload warnings
  - adaptive FPS changes

## Performance Tracing
- Signposts are emitted for:
  - camera frame receipt
  - end-to-end frame pipeline
  - backend inference
  - reacquire pass
  - continuity update
  - temporal smoothing update
  - quality evaluation
  - render update
- Open Instruments:
  - profile app with `Points of Interest` / `OS Signpost`
  - filter subsystem `com.pushly.pose`

## Debug Overlay
- Toggle overlay with native view prop `debugMode`.
- Overlay shows:
  - backend, mode, tracking state
  - reacquire source
  - mirrored + orientation
  - ROI summary
  - visible joint count + confidence/velocity
  - coverage (`upper/full/hand`)
  - low-light state
  - camera FPS / processing FPS / drop rate / backlog
  - inferred ratio + relock timing

## Session Export
- Export API:
  - JS/native module method: `exportPoseDebugSessionAsync()`
- Writes JSON to:
  - `tmp/pushly-debug/pose-sessions/pose-debug-<session-id>.json`
- Export payload includes:
  - compact session summary
  - bounded recent event ring buffer
  - optional sampled frame telemetry (throttled/gated)
  - config snapshot

## Important Flags (PushlyPoseConfig.pipeline)
- `structuredLoggingEnabled`
- `verboseFrameLoggingEnabled`
- `verboseFrameSampleInterval`
- `debugOverlayEnabled`
- `sessionExportEnabled`
- `signpostsEnabled`
- `cameraTelemetryEnabled`
- `backendTelemetryEnabled`
- `maxDiagnosticEventBuffer`
- `maxDiagnosticFrameBuffer`

Defaults are production-safe:
- structured event logging on
- per-frame verbose sampling off
- overlay off by default
- export enabled
- signposts enabled

## MediaPipe Runtime Verification
Use one session in trial with explicit debug enabled (`debugMode=true`) and verify:
- backend requested/active: `requestedBackend=mediapipe`, `activeBackend=mediapipe` (or explicit fallback reason),
- availability/build flags: `mediapipeAvailable`, `compiledWithMediaPipe`,
- model/init fields: `poseModelFound`, `poseModelName`, `poseLandmarkerInitStatus`, `mediapipeInitReason`,
- fallback diagnostics: `fallbackUsed`, `fallbackReason`.

If MediaPipe is unavailable, verify `mediapipeInitReason` first before tuning quality/count gates.

## Parameters That Influence Lag
Primary knobs (native):
- `PushlyPoseConfig.smoothing.logicPredictionLeadSeconds`
- `PushlyPoseConfig.smoothing.renderLineEndpointAlpha`
- `SkeletonRenderer` spring params (`min/maxStiffness`, `stable/movingDamping`, `maxVelocityPerFrame`)
- `PushlyPoseConfig.smoothing.renderPersistenceGraceSeconds`
- `PushlyPoseConfig.smoothing.pushupBottomRenderGraceSeconds`
- `PushlyPoseConfig.smoothing.segmentationBottomAssistRenderGraceSeconds`

Rule of thumb:
- higher endpoint alpha + higher stiffness/lower damping => less visible trailing,
- shorter render grace => less ghost persistence after brief drops.

## Parameters That Influence Low-Light Robustness
Thresholds:
- `PushlyPoseConfig.quality.lowLightLumaThreshold`
- `PushlyPoseConfig.quality.veryLowLightLumaThreshold`

Quality behavior:
- `TrackingQualityEvaluator` applies low-light penalties to `logicQuality` (count-readiness) more than render geometry,
- `very_low_light` is a stricter tier than `low_light`.

Capture behavior:
- `CameraCaptureManager` lowers capture FPS under `lowLightDetected` via `camera.lowLightCaptureFPS`.

## Count-Blocking Signals
When count does not increment, inspect:
- cycle/state: `descendingFrames`, `bottomFrames`, `ascendingFrames`, `bottomReached`,
- v1 path: `topReady`, `descendingStarted`, `bottomLatched`, `ascendingStarted`, `topRecovered`, `repCommitted`,
- gate status: `countGatePassed`, `countGateBlocked`, `countGateBlockReason`,
- common reasons: `top_not_ready`, `descending_not_started`, `bottom_not_latched`, `ascending_not_started`, `top_not_recovered`, `commit_safety_low`, `body_not_found`.

### Push-up v1 Gate Scope (Current)
- does NOT block active rep commit anymore:
  - `cycleLogicGate`
  - `motionTravelGate`
  - `strictCycleReady`
  - `floorFallbackCycleReady`
  - `rearmGate` (only post-commit)
- minimum safety only for commit:
  - `commit_safety_low` (relaxed logic/tracking/evidence floor)
- reset/abort only:
  - `movement_collapsed`
  - `no_recovery_within_timeout`
  - `motion_pattern_invalid`

## Push-up Trial Quick Reference
Use this minimal field set first before deep-diving into full frame telemetry:
- backend path:
  - `requestedBackend`
  - `activeBackend`
  - `compiledWithMediaPipe`
  - `mediapipeAvailable`
  - `mediapipeInitReason`
  - `fallbackReason`
- cycle continuity:
  - `state`
  - `stateTransitionEvent`
  - `descendingFrames`, `bottomFrames`, `ascendingFrames`, `bottomReached`
- progression vs count:
  - progression continuity: `canProgress`, `logicBlockedFrames`
  - strict count decision: `countGatePassed`, `countGateBlockReason`
  - strict gates: `strictCycleReady`, `floorFallbackCycleReady`, `cycleCoreReady`, `motionTravelGate`, `topRecoveryGate`
- rearm/recovery:
  - `repRearmPending`, `topRecoveryFrames`

### Most Common Blockers (Interpretation)
- `logic_gate_blocked`:
  - logic blockers persisted beyond progression grace.
- `torso_unstable`:
  - torso stability stayed below gate long enough to exceed torso stability grace.
- `ascending_not_confirmed`:
  - bottom confirmed, but ascent confirmation frames were not sustained.
- `rearm_pending`:
  - previous rep already counted; top recovery/rearm not completed yet.

### Runtime Verification: MediaPipe vs Vision
For a healthy MediaPipe-first session in trial debug:
- expected baseline:
  - `requestedBackend=mediapipe` (or `auto` resolving to MediaPipe)
  - `activeBackend=mediapipe`
  - `compiledWithMediaPipe=true`
  - `mediapipeAvailable=true`
- fallback indicator:
  - `activeBackend=visionFallback` with non-empty `fallbackReason` (`quality_degraded`, `primary_error`, `mediapipe_unavailable`).

If fallback appears frequently during clean reps, inspect `trackingQuality`, `logicQuality`, and low-light reason codes before relaxing count gates.

### Parameters Most Relevant For Fragile Later Reps
These tend to matter most for rep 3/4 misses:
- progression continuity:
  - `minLogicQualityToProgress`
  - `logicGateGraceFrames`
- ascent/recovery continuity:
  - `ascendingConfirmFrames`
  - `repRearmConfirmFrames`
- torso stability gating:
  - `minTorsoStability`
  - `floorMinTorsoStability`
- strict final count:
  - `minLogicQualityToCount`
  - `minTrackingQualityToCount` / `floorMinTrackingQualityToCount`

## Parameter Map (Current Push-up Stack)
### First Rep / Startup Readiness
- `PushlyPoseConfig.rep.plankLockFrames`
- `PushlyPoseConfig.rep.startupDescendBridgeMinTopFrames`
- `PushlyPoseConfig.rep.descentConfirmFrames`
- `PushlyPoseConfig.rep.logicGateGraceFrames`
- `PushlyPoseConfig.rep.repRearmConfirmFrames`

Debug fields to verify:
- `startupReady`
- `startupTopEvidence`
- `startupDescendBridgeUsed`
- `startBlockedReason`
- `repRearmPending`

### Occlusion / Baggy Clothing / Continuity
- `PushlyPoseConfig.tracker.missingJointPredictionMaxAge`
- `PushlyPoseConfig.tracker.pushupMissingJointPredictionMaxAgeScale`
- `PushlyPoseConfig.tracker.missingJointPredictionMaxExtrapolation`
- `PushlyPoseConfig.tracker.pushupMissingJointPredictionMaxExtrapolationScale`
- `PushlyPoseConfig.tracker.missingJointPredictionConfidenceDecayPerSecond`
- `PushlyPoseConfig.tracker.pushupMissingJointPredictionDecayRateScale`
- `PushlyPoseConfig.tracker.torsoOffsetMaxAge`
- `PushlyPoseConfig.tracker.pushupTorsoOffsetMaxAgeScale`
- `PushlyPoseConfig.tracker.pushupTorsoInferencePreserveConfidenceMin`
- `PushlyPoseConfig.mode.pushupFloorLostGraceFrames`
- `PushlyPoseConfig.mode.segmentationBottomAssistLostGraceFrames`
- `PushlyPoseConfig.mediaPipe.enablePoseSegmentationPresenceAssist`
- `PushlyPoseConfig.mediaPipe.poseSegmentationAssistCoverageThreshold`
- `PushlyPoseConfig.mediaPipe.poseSegmentationBottomAssistCoverageThreshold`

Debug fields to verify:
- `trackingState` / `poseTrackingState`
- `pushupFloorModeActive`
- `segmentationAssistActive`
- `fallbackUsed`, `fallbackReason`
- `inferredJointRatio`

### Connection Sanity (Renderer)
- `SkeletonRenderer` connection gates:
  - endpoint confidence gate (`endpoint_confidence_low`)
  - max distance vs torso scale (`distance_unplausible`)
  - uncertain endpoint jump gate (`endpoint_jump_unplausible`)
  - floor-like stricter uncertain-segment limits

Debug signals to watch:
- suppressed connection reasons in renderer debug logs
- `inferredJointRatio`, `inferredJointCount`
- visual symptom split:
  - line hidden but joint dot still visible => sanity gate active
  - both line and dot missing => upstream tracking drop

## After A Bad Test Run, Send Back
1. Written feedback:
   - near/far distance
   - light conditions
   - upper-body-only or full-body framing
   - what looked wrong (offset/mirror/lag/reacquire/fallback)
2. Screenshot or screen recording.
3. Exported debug JSON path + file.
4. Device model + iOS version (included in summary; mention if missing).
