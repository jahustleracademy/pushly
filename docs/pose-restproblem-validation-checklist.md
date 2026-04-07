# iOS Pose Tracking: Restproblem-Validierung (Kurzcheck)

Nur Validierung, keine Runtime-Änderung.
Voraussetzung: `debugMode = true`, danach pro Szenario eine Session mit `exportPoseDebugSessionAsync()` exportieren.

## 1) Near-Camera: Kein Crash
- Test: 3 Zyklen `normal -> sehr nah (Schulterbreite groß im Bild) -> normal`, jeweils mit kurzen Hip-Occlusions.
- Akzeptanz:
  - Kein App-/Render-Crash im gesamten Ablauf.
  - Export-Summary zeigt `tooCloseFallbackFrameCount > 0` in Nahphasen.
  - `tooCloseInferredHipTotal >= tooCloseFallbackFrameCount`.

## 2) Push-up Bottom: Skeleton bleibt sichtbar
- Test: 5 langsame Push-ups mit je 1-2 s Bottom-Hold.
- Akzeptanz:
  - Torso/Schultern/Ellbogen/Handgelenke/Hüften bleiben in Bottom sichtbar.
  - Kein abruptes Verschwinden während Bottom-Hold.
  - In Bottom-Frames ist `bottomRenderPersistenceActive` regelmäßig `true`.

## 3) Bottom-Persistenz bei Teil-Occlusion
- Test: Im Bottom gezielt Teil-Occlusion (ein Arm oder Hüfte kurz verdeckt), 10-15 s.
- Akzeptanz:
  - Rendering bleibt in der Grace-Phase stabil.
  - `segmentationAssistActive` tritt in Occlusion-Frames auf.
  - `bottomRenderDisappearReasonCounts` enthält nicht dominant `bottom_fallback_unavailable`.

## 4) 3 saubere Push-ups werden korrekt gezählt
- Test: Genau 3 vollständige Push-ups (top -> bottom -> top), kontrolliertes Tempo.
- Akzeptanz:
  - Endwert `repCount == 3`.
  - Kein Increment bei halben Zyklen oder reinem Bottom-Halten.
  - Bei Nichtzählung ist `bottomRepNotCountedReasonCounts` plausibel (z. B. reproduzierbare Blocker, kein Zufallsrauschen).

## 5) Keine offensichtlichen Left/Right-Flips in Push-up Bottom
- Test: 60 s Push-up-/Bottom-Stress (nah, Teil-Occlusion, dynamische Arme).
- Akzeptanz:
  - Keine sichtbaren Seiten-Sprünge im Bottom.
  - `sideSwapAppliedFrameCount / processedFrameCount <= 0.005`.
  - Keine Häufung von Flip-Ereignissen parallel zu `tooCloseFallbackActive`.

## 6) Debug-Session-Metriken sind plausibel
- Prüfen (Summary + sampled frames):
  - `bottomPhaseFrameCount > 0` bei Bottom-Tests.
  - `pushupFloorModeFrameCount > 0` bei Floor-/Bottom-Szenen.
  - `segmentationAssistFrameCount > 0` bei Teil-Occlusion-Szenen.
  - `bottomRenderPersistenceFrameCount > 0` bei Bottom-Holds.
  - `bottomArmAnchorAvailableFrameCount` und `bottomTorsoAnchorAvailableFrameCount` jeweils > 0.
  - `bottomRenderDisappearReasonCounts` und `bottomRepNotCountedReasonCounts` sind konsistent mit dem beobachteten Verhalten.

## Schnell-Checks (jq)
```bash
jq '.summary | {processedFrameCount, tooCloseFallbackFrameCount, tooCloseInferredHipTotal}' pose-debug-*.json
jq '.summary | {bottomPhaseFrameCount, pushupFloorModeFrameCount, segmentationAssistFrameCount, bottomRenderPersistenceFrameCount}' pose-debug-*.json
jq '.summary | {bottomArmAnchorAvailableFrameCount, bottomTorsoAnchorAvailableFrameCount, bottomRenderDisappearReasonCounts, bottomRepNotCountedReasonCounts}' pose-debug-*.json
jq '.summary | {repCount, sideSwapAppliedFrameCount, processedFrameCount, flipRate: (.sideSwapAppliedFrameCount / (.processedFrameCount|if .==0 then 1 else . end))}' pose-debug-*.json
```
