# ApeX Mobile – Flutter-App zur Zeiterfassung

Mobile Zeiterfassung für Mitarbeiter im Feld: Ein-/Ausstempeln, Pause, Umbuchen auf
Vorgang/Position/Kostenstelle, Team-/Kolonnen-Buchungen, QR-Scan, GPS an der Buchung.
Backend ist die apex-App (`~/source/frappe/my-bench/apps/apex`), Modul `apex.workforce`.
Geschäftskontext/Glossar: `/home/christian/source/CLAUDE.md` (wird automatisch mitgeladen).

## Tech-Stack

- Flutter **3.44.6** (fest in CI), Dart ^3.12, Material 3 (light+dark). Ziel: **Android + iOS**
  (App-ID `de.sandhasgroup.apexmobileapp`); `web/`/`macos/` sind ungenutztes Gerüst.
- Bewusst **kein** State-Management-Framework: StatefulWidget/FutureBuilder, DI per
  Konstruktor-Injection des `FrappeClient`. Diesen Stil beibehalten.
- Pakete: `http`, `flutter_secure_storage` (Credentials), `mobile_scanner` (QR),
  `geolocator` (GPS), `flutter_lints`. iOS ohne CocoaPods (Swift Packages).

## Struktur (lib/)

- `main.dart` – `ApexApp` + `AuthGate` (Auto-Login via restoreSession)
- `models/time_models.dart` – TimeStatus, Lookups, ProjectOrder, CostCenter, Position …
  inkl. Config-Parsing (`allow_team`, `capture_mode`, `can_book_others`, `use_gps`)
- `screens/` – login, home_page, zeiterfassung, booking_wizard, team_select, qr_scan, connection
- `services/` – `frappe_client.dart` (HTTP+Session, sid-Cookie, 1× Auto-Relogin bei 401/403),
  `time_tracking_service.dart` (alle Aufrufe von `apex.workforce.mobile.*`),
  `credential_store.dart`, `location_service.dart`, `connectivity_service.dart` (8-s-Ping)
- Naming: Dateien snake_case; Services `_service`/`_store`/`_client`, Screens `_screen`/`_page`

## Backend-Anbindung

- Nur `/api/method/...`-REST. Server-URL wird zur Laufzeit im Login eingegeben
  (keine Flavors/Hardcoding), Credentials im Secure Storage.
- Endpunkte: `get_me` (Status + config), `get_lookups`, `get_recent`, `get_positions`,
  `get_team_options`, `set_team`, `book` (POST, GPS, `apply_team`), `clock_out`, `pause`, `resume`.
- Verhalten ist **config-getrieben** über `get_me → config` – Feature-Schalter kommen vom Server.
- `BACKEND_OFFLINE_booked_at.md` = Konzept für echte Offline-Nachbuchung (`booked_at`-Parameter,
  Änderung liegt im **apex**-Backend, kiosk.py/mobile.py). Noch nicht umgesetzt – die App sendet
  bisher kein `booked_at`; „offline" ist derzeit nur eine Erreichbarkeitsanzeige.

## Befehle

- `flutter pub get` → `flutter run` (URL/Login beim ersten Start eingeben)
- `flutter analyze` (läuft auch in CI), `flutter test`
- Release: Git-Tag `v*` pushen → GitHub Actions baut APK und erstellt das Release.
  Achtung: APK ist mit dem **Debug-Key** signiert – vor einem Play-Store-Release
  eigenen Keystore einrichten. Kein iOS-Build in CI (Apple-Zertifikate fehlen).

## Lokale Umgebung (ubuntu-dev-01)

- Flutter-SDK: `~/flutter`, JDK 21: `~/java`, Android-SDK: `~/android-sdk` (alles in PATH/ENV via ~/.bashrc).
- Lokaler APK-Build: `flutter build apk --debug` funktioniert. Achtung: Der Rechner hat nur 7 GB RAM –
  `~/.gradle/gradle.properties` drosselt Gradle auf 2 GB und überstimmt die 8G-Vorgabe des Repos
  (nicht löschen, sonst killt der OOM-Killer den Build).
- Kein KVM/Display → kein Emulator. Test auf echtem Gerät per WLAN-Debugging (`adb pair`).

## Konventionen / Stolpersteine

- Tests: bisher nur ein Smoke-Test (`test/widget_test.dart`) – bei neuen Services gern Unit-Tests ergänzen.
- Fehlt `use_gps` in der Server-Config, gilt GPS als Pflicht (`time_models.dart`).
- Schnittstellen-Änderungen immer **zusammen mit dem Backend** denken (apex `workforce/mobile.py`) –
  bei übergreifenden Prüfungen den code-pruefer aus einer `~/source`-Session nutzen.
