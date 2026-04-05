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

## After A Bad Test Run, Send Back
1. Written feedback:
   - near/far distance
   - light conditions
   - upper-body-only or full-body framing
   - what looked wrong (offset/mirror/lag/reacquire/fallback)
2. Screenshot or screen recording.
3. Exported debug JSON path + file.
4. Device model + iOS version (included in summary; mention if missing).
