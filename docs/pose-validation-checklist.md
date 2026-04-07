# Pose Validation Checklist (Recent iOS Tracking Fixes)

This checklist validates the latest continuity/occlusion/head-geometry/side-lock/rep improvements without changing runtime behavior.

## Preconditions
- Use front camera and a reproducible setup (same light, distance, floor).
- Enable `debugMode` for overlay checks.
- Export one debug session JSON via `exportPoseDebugSessionAsync()` after each scenario.
- For frame-level checks, temporarily enable:
  - `PushlyPoseConfig.pipeline.verboseFrameLoggingEnabled = true`
  - keep `verboseFrameSampleInterval` at `12` or lower.

## 1) Head Geometry (Too Long vs Correct)
### Procedure
- Stand at near-camera distance and normal distance.
- Keep shoulders visible; run with and without nose visibility (briefly cover nose).
- Record 10-15 seconds each.

### Acceptance
- Virtual crown line is visually short and stable, without "antenna" effect.
- In sampled frames, `trackingState` stays non-lost for the sequence.
- In DEBUG builds, no assertion from virtual-head geometry bounds.

## 2) Push-up Bottom Persistence
### Procedure
- Perform 5 slow push-ups with a 1-2 second hold at the bottom.
- Keep chest close to floor to force partial lower-body loss.

### Acceptance
- During bottom hold, skeleton remains visible for torso + shoulders + elbows + wrists + hips.
- No immediate collapse to empty render while floor mode is active.
- In sampled frames during bottom hold:
  - `renderedJointCount >= 5` for at least 80% of sampled bottom frames.
  - `trackingState != lost` for at least 90% of sampled bottom frames.

## 3) Left/Right Flip Rate
### Procedure
- Record 60+ seconds with near distance, fast arm movement, short partial occlusions.

### Acceptance
- From export summary:
  - `flipRate = sideSwapAppliedFrameCount / processedFrameCount`
  - pass when `flipRate <= 0.005` (<= 0.5%).
- During explicit stress (hard cross-body motion), occasional flips are acceptable only if immediately self-correcting.
- In DEBUG builds, no assertion for flip while too-close fallback is active.

## 4) Too-Close Stability
### Procedure
- Move from normal distance to very near camera and back (3 cycles).
- Include shoulder-dominant framing and brief hip occlusion.

### Acceptance
- No hard left/right skeleton collapse or geometry inversion during near phase.
- Summary checks:
  - `tooCloseFallbackFrameCount > 0` in near phases.
  - `tooCloseInferredHipTotal >= tooCloseFallbackFrameCount` (inferred hips present when fallback active).
- Re-lock after stepping back is smooth (no one-frame snap explosion).

## 5) Rep Count for 3 Clean Push-ups
### Procedure
- Perform exactly 3 clean reps (full cycle: top -> bottom -> top), controlled tempo.
- Avoid extra partial movements before/after.

### Acceptance
- Reported `repCount` ends at exactly `3`.
- No count increments at half reps or bottom-only pauses.
- If miscount occurs, review sampled-frame `pushupBlockedReasons` distribution and verify the dominant blockers are interpretable (not random flip/loss noise).

## 6) Jitter: Rest vs Movement
### Procedure
- 10 seconds static plank/rest position.
- 10 seconds dynamic push-up movement.

### Acceptance
- Debug overlay `rms(rt/ts)` in rest should be clearly lower than movement.
- Target guide values:
  - Rest: `raw->tracked <= 2.5 px`, `tracked->spring <= 1.8 px`
  - Movement: `raw->tracked <= 9.0 px`, `tracked->spring <= 6.0 px`
- Fail if rest jitter is consistently close to movement jitter.

## 7) Reacquire After Short Loss
### Procedure
- Intentionally leave frame for ~0.3-0.6 seconds, then return to same pose.
- Repeat 5 times.

### Acceptance
- Reacquire succeeds without long lost state:
  - event log shows `reacquire_begin` followed by successful `reacquire_end`.
  - no persistent `lost` state after return.
- Session summary:
  - `reacquireAttempts >= 5`
  - `lostTrackingFrameCount` remains low relative to attempts (target: no prolonged lost streaks).

## Optional Quick jq Snippets
- Flip rate:
```bash
jq '.summary | (.sideSwapAppliedFrameCount / (.processedFrameCount|if .==0 then 1 else . end))' pose-debug-*.json
```
- Too-close ratio:
```bash
jq '.summary | {tooCloseFallbackFrameCount, tooCloseInferredHipTotal, processedFrameCount}' pose-debug-*.json
```
- Reacquire summary:
```bash
jq '.summary | {reacquireAttempts, reacquireSourceCounts, lostTrackingFrameCount}' pose-debug-*.json
```
