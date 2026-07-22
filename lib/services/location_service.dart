import 'package:geolocator/geolocator.dart';

/// Liefert den aktuellen Standort für Buchungen – robust: kurzer Timeout,
/// Rückfall auf die letzte bekannte Position, wirft nie (fehlt GPS → null/null).
class LocationService {
  Future<({double? lat, double? lng})> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return _last();

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return _last();
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 4),
        ),
      );
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      return _last();
    }
  }

  /// Warmlauf: früh die Berechtigung anfragen und einen Fix vorbereiten.
  void warmUp() {
    current();
  }

  /// Verlangt einen Standort (GPS-Pflicht). Bei Erfolg lat/lng gesetzt,
  /// sonst [error] mit lesbarer Meldung ([openSettings] = iOS-Einstellungen nötig).
  Future<({double? lat, double? lng, String? error, bool openSettings})>
      require() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return (
          lat: null,
          lng: null,
          error: 'Standortdienste sind aus. Bitte in den Einstellungen aktivieren, um zu stempeln.',
          openSettings: false,
        );
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        return (
          lat: null,
          lng: null,
          error: 'Standortfreigabe ist deaktiviert. Bitte in den Einstellungen erlauben, um zu stempeln.',
          openSettings: true,
        );
      }
      if (perm == LocationPermission.denied) {
        return (
          lat: null,
          lng: null,
          error: 'Ohne Standortfreigabe ist kein Stempeln möglich.',
          openSettings: false,
        );
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 6),
        ),
      );
      return (lat: pos.latitude, lng: pos.longitude, error: null, openSettings: false);
    } catch (_) {
      final last = await _last();
      if (last.lat != null) {
        return (lat: last.lat, lng: last.lng, error: null, openSettings: false);
      }
      return (
        lat: null,
        lng: null,
        error: 'Standort konnte nicht ermittelt werden. Bitte erneut versuchen.',
        openSettings: false,
      );
    }
  }

  Future<void> openSettings() => Geolocator.openAppSettings();

  Future<({double? lat, double? lng})> _last() async {
    try {
      final p = await Geolocator.getLastKnownPosition();
      if (p != null) return (lat: p.latitude, lng: p.longitude);
    } catch (_) {}
    return (lat: null, lng: null);
  }
}
