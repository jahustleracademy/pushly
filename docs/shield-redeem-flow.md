# Shield Redeem Flow (v1)

## Scope
Diese Architektur nutzt exakt dieselbe Credits-/Unlock-Runtime fuer App und Shield-Kontext. Es gibt keine zweite Credit- oder Redeem-Logik in Extensions.

## Verantwortlichkeiten
- Main App (`features/credits/*`, `components/shared/runtime/AppRuntimeProvider.tsx`):
  - Source-of-truth-Runtime fuer Credits, Ledger, Redeem, UnlockWindow, Daily Reset und Re-Shielding.
  - Einzige Stelle, die Credits abbucht und Unlock-Fenster erzeugt.
- Shield Configuration Extension (`targets/pushly-shield-configuration/ios/PushlyShieldConfigurationExtension.swift`):
  - Rein presentation layer (Shield-Texte, Buttons, optional Credits-Anzeige).
  - Keine Business-Logik.
- Shield Action Extension (`targets/pushly-shield-action/ios/PushlyShieldActionExtension.swift`):
  - Schreibt nur einen Pending-Intent in Shared Storage.
  - Keine Redeem-/Credit-Berechnung.
- Device Activity Monitor Extension (`targets/pushly-device-activity-monitor/ios/PushlyDeviceActivityMonitorExtension.swift`):
  - Re-appliziert Shielding nach DeviceActivity-Intervallen.

## Persistenz und App-Group Mechanik
- App Group: `group.com.pushly.shared`
- Shared Keys:
  - `pushly.creditsSnapshot.v1`: JSON-Snapshot fuer shield-relevanten Zustand.
  - `pushly.pendingShieldRedeemIntent.v1`: Pending-Intent von Shield Action -> Main App.
  - bestehend: `pushly.familyActivitySelection`, `pushly.familyActivitySelectionUpdatedAt`.
- Runtime-Persistenz (`features/credits/infrastructure/storage.ts`):
  - Dual storage: AsyncStorage + App Group Snapshot.
  - Beim Laden wird die neueste Version per `updatedAt` als Gewinner verwendet.
  - Danach self-healing write-back auf beide Speicherorte.
  - Beim Speichern gilt ein `newer snapshot wins`-Guard je Speicherort (older writes duerfen neuere Daten nicht ueberschreiben).

## Synchronisation App <-> Extensions
1. Main App schreibt bei jedem Runtime-Persist den Credits-Snapshot in AsyncStorage und App Group.
2. Shield Configuration liest Credits (Balance) aus App Group Snapshot fuer die UI.
3. Shield Action schreibt Pending-Intent in App Group.
4. `AppRuntimeProvider` konsumiert Pending-Intent bei App-Resume/Heartbeat und routed auf `/redeem?source=shield&minutes=...`.
5. Redeem wird nur in der Main-Runtime (`creditsRuntimeStore.redeemMinutes`) ausgefuehrt.

## Deep-Link Vertrag
- Route-orientiert (Shield -> App):
  - `pushly://redeem?source=shield&minutes=<n>`
- Optional instant contract (falls spaeter benoetigt):
  - `pushly://redeem?mode=instant&minutes=<n>`
- Pending-Intent Payload (App Group):
  - `{ "type": "route_redeem", "source": "shield", "suggestedMinutes": 15, "createdAt": "..." }`

## Fehlerverhalten und Recovery
- Redeem-Transaktion (`features/credits/application/creditsRuntime.ts`):
  - Kein Credit-Abzug ohne erfolgreiches `beginTimedUnlock`.
  - Persist-Fehler rollt State zurueck; falls Unlock zuvor gestartet wurde, wird ein Revert (`endTimedUnlock`) versucht.
- Unlock-Ablauf:
  - Bei Fehler in `endTimedUnlock` wird State nicht voreilig geloescht.
  - Deterministischer Retry nach 15s, bis Re-Shielding klappt.
- Reconcile:
  - Bei App-Start, App-Resume und Heartbeat (30s) wird Runtime reconciled und Pending-Intent verarbeitet.
  - Intent-Deduplizierung verhindert doppelte Verarbeitung identischer Deep-Links oder Pending-Payloads.

## Persistenz- und Recovery-Regeln (kurz)
- Credits/earned/spent/balance sind strikt an `dailyCredits.dateKey` gebunden.
- Tageswechsel erzwingt Reset auf 0, loescht aktives UnlockWindow und setzt Shielding wieder aktiv.
- `activeUnlockWindow` wird nach Neustart aus Snapshot rekonstruiert und gegen aktuelle Zeit validiert.
- Abgelaufene Unlocks werden deterministisch beendet (`endTimedUnlock`) und dann aus Runtime/Snapshot entfernt.
- Pending-Shield-Intents werden genau einmal konsumiert (`consume` + dedupe-key), danach nicht erneut verarbeitet.

## Manuelle TestFlight-Edge-Cases
- App waehrend aktivem Unlock killen -> neu oeffnen -> Restzeit korrekt, danach automatisches Re-Shielding.
- Mitternachtswechsel waehrend App im Hintergrund -> beim Resume Balance/Earned/Spent auf 0, Shield aktiv.
- Gleichzeitige schnelle Rep-Updates in Session -> keine doppelte Credit-Buchung fuer denselben repCount.
- Redeem mit knappem Restguthaben -> korrekte Fehlermeldung bei Unterdeckung, kein Teilabzug.
- Shield-Primary-Action mehrfach schnell tippen -> nur ein Redeem-Flow in der App, keine Doppelabbuchung.
- Pending-Intent vorhanden + Deep-Link gleichzeitig -> nur eine Verarbeitung.
- Unlock-Ende bei temporaerem nativen Fehler -> Retry laeuft, Zustand bleibt konsistent.

## API-/OS-Fallbacks
- Primarer offizieller Shield-Action-Pfad: `ShieldActionResponse.defer`.
- Falls kein sicherer direkter App-Open-Pfad verfuegbar ist, bleibt der Flow ueber Pending-Intent + App-Resume/Foreground robust.
- Keine private API, kein responder-chain Hack.
