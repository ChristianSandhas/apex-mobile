import 'dart:async';
import 'package:flutter/foundation.dart';
import 'frappe_client.dart';

/// Prüft regelmäßig, ob der Frappe-Server erreichbar ist, und stellt den
/// Online-/Offline-Zustand als [ValueListenable] bereit.
///
/// Online  = Server hat auf den Ping geantwortet.
/// Offline = Netzwerkfehler oder Zeitüberschreitung.
class ConnectivityService {
  ConnectivityService(this._client);
  final FrappeClient _client;

  /// true = online, false = offline. Startwert offline, bis der erste Ping da ist.
  final ValueNotifier<bool> online = ValueNotifier<bool>(false);

  Timer? _timer;
  bool _checking = false;

  /// Startet die periodische Prüfung (Standard alle 8 Sekunden).
  void start({Duration interval = const Duration(seconds: 8)}) {
    check();
    _timer ??= Timer.periodic(interval, (_) => check());
  }

  /// Führt sofort eine Prüfung durch (z. B. nach einer fehlgeschlagenen Aktion).
  Future<void> check() async {
    if (_checking) return;
    _checking = true;
    try {
      online.value = await _client.ping();
    } finally {
      _checking = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    online.dispose();
  }
}
