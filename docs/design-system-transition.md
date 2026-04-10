# Design-System Transition (interim)

`references/design-system` fehlt aktuell. Bis der Zielpfad existiert, gilt fuer Implementierungen in diesem Repo folgender Uebergangsstandard:

## Source of truth (interim)
1. `references/design-policy` definiert visuelle Leitplanken (Spacing, Tonalitaet, Kontrast, Hierarchie).
2. `references/onboarding-flow` definiert konkrete Screen-Kompositionen und Flow-Muster.
3. Technische Tokens bleiben zentral in `constants/theme.ts`.

## Working rule
- Neue UI-Komponenten duerfen nur mit Tokens aus `constants/theme.ts` gebaut werden.
- Wenn ein Wert fehlt, zuerst Token erweitern statt Hardcoding in Screens.
- Reusable UI zuerst in `components/ui/*`, Screen-spezifisches Styling in Screen-Dateien.

## Exit criteria fuer echten `references/design-system`
- Ein dokumentierter Token-Katalog (Color, Type, Radius, Spacing).
- Komponenten-Spezifikationen fuer Buttons/Cards/Inputs/Status.
- Mapping-Tabelle von alten Policy-Referenzen auf neue System-Komponenten.

Bis dahin ist diese Datei die verbindliche Bruecke zwischen vorhandenen Referenzen und Implementierung.
