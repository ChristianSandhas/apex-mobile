# Changelog

Alle nennenswerten Änderungen an ApeX Mobile, neueste zuerst.
Sicht: Was kann die App jetzt? (Anwendersicht, technische Details nur wo nötig.)

## [Unreleased]

- **Doku:** Changelog eingeführt.

## [0.1.1] – 2026-07-23

- Anzeige im Querformat korrigiert (SafeArea – Inhalte werden nicht mehr von
  Kamera-Aussparung/Systemleisten überdeckt).
- Projekt-Wissensbasis (CLAUDE.md) und Notizen zur lokalen Build-Umgebung ergänzt.

## [0.1.0] – 2026-07-22

Erstes Release der mobilen Zeiterfassung:

- **Zeiterfassung:** Ein-/Ausstempeln, Pause/Fortsetzen, Umbuchen mit laufendem Timer
  und Tagesstunden-Anzeige.
- **Buchungs-Assistent:** Vorgang → Position → Kostenstelle, mit Suche und
  „Zuletzt verwendet"; Pflichtfelder kommen aus der Server-Konfiguration.
- **Team/Kolonne:** Team zusammenstellen (optional befristet), Aktionen für „Nur ich"
  oder das ganze Team, Einzelaktionen pro Mitglied.
- **QR-Scan:** `APX:*`-Codes (Mitarbeiter, Vorgang, Position, Kostenstelle, Pause, Ende).
- **GPS:** Standort wird an Buchungen übergeben.
- **Anmeldung:** Server-URL frei wählbar, sichere Speicherung der Zugangsdaten
  (Keychain/Keystore), Auto-Login und automatischer Relogin; Online-Anzeige.
- **CI:** Git-Tag `v*` baut die Android-APK und erstellt das GitHub-Release.
