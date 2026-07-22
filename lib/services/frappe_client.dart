import 'dart:convert';
import 'package:http/http.dart' as http;
import 'credential_store.dart';

/// Fehler mit einer für Nutzer lesbaren Meldung.
class FrappeException implements Exception {
  final String message;
  FrappeException(this.message);
  @override
  String toString() => message;
}

/// Spricht per REST mit einem Frappe-/ERPNext-Server.
///
/// Authentifizierung über Benutzer + Passwort. Nach dem Login wird das
/// `sid`-Session-Cookie gehalten und bei jeder Anfrage mitgeschickt. Läuft die
/// Session ab (HTTP 401/403), loggt sich der Client automatisch mit den sicher
/// gespeicherten Zugangsdaten neu ein und wiederholt die Anfrage einmal.
class FrappeClient {
  FrappeClient(this._store);
  final CredentialStore _store;

  String? _baseUrl;
  String? _sid;

  bool get isLoggedIn => _sid != null && _baseUrl != null;
  String? get baseUrl => _baseUrl;

  /// Normalisiert die eingegebene URL: ergänzt https://, entfernt End-Slashes.
  static String normalizeUrl(String raw) {
    var u = raw.trim();
    if (u.isEmpty) throw FrappeException('Server-URL fehlt.');
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    return u.replaceAll(RegExp(r'/+$'), '');
  }

  /// Meldet sich am Server an und speichert die Zugangsdaten sicher.
  /// Gibt den vollen Namen des Nutzers zurück (falls der Server ihn liefert).
  Future<String> login({
    required String baseUrl,
    required String username,
    required String password,
    bool persist = true,
  }) async {
    final url = normalizeUrl(baseUrl);

    http.Response resp;
    try {
      resp = await http
          .post(
            Uri.parse('$url/api/method/login'),
            body: {'usr': username, 'pwd': password},
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw FrappeException('Server nicht erreichbar. URL prüfen?\n($e)');
    }

    if (resp.statusCode == 401) {
      throw FrappeException('Benutzername oder Passwort falsch.');
    }
    if (resp.statusCode != 200) {
      throw FrappeException('Login fehlgeschlagen (HTTP ${resp.statusCode}).');
    }

    final sid = _extractSid(resp.headers['set-cookie']);
    if (sid == null) {
      throw FrappeException('Server hat keine gültige Session zurückgegeben.');
    }

    _baseUrl = url;
    _sid = sid;

    if (persist) {
      await _store.save(
        Credentials(baseUrl: url, username: username, password: password),
      );
    }

    try {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return (data['full_name'] as String?) ?? username;
    } catch (_) {
      return username;
    }
  }

  /// Stellt beim App-Start aus gespeicherten Zugangsdaten eine Session her.
  Future<bool> restoreSession() async {
    final creds = await _store.load();
    if (creds == null) return false;
    try {
      await login(
        baseUrl: creds.baseUrl,
        username: creds.username,
        password: creds.password,
        persist: false,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Meldet ab und löscht die gespeicherten Zugangsdaten.
  Future<void> logout() async {
    final url = _baseUrl;
    final sid = _sid;
    _sid = null;
    _baseUrl = null;
    if (url != null && sid != null) {
      try {
        await http.get(
          Uri.parse('$url/api/method/logout'),
          headers: {'Cookie': 'sid=$sid'},
        );
      } catch (_) {
        // Abmelden am Server ist Best-Effort; lokal ist die Session schon weg.
      }
    }
    await _store.clear();
  }

  /// GET auf einen Frappe-Pfad, z. B. '/api/method/frappe.auth.get_logged_user'.
  Future<http.Response> get(String path) => _send('GET', path);

  /// POST auf einen Frappe-Pfad.
  Future<http.Response> post(String path, {Object? body}) =>
      _send('POST', path, body: body);

  Future<http.Response> _send(String method, String path, {Object? body}) async {
    if (!isLoggedIn) throw FrappeException('Nicht eingeloggt.');

    var resp = await _raw(method, path, body: body);

    // Session abgelaufen? Einmal neu einloggen und wiederholen.
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      final ok = await restoreSession();
      if (ok) resp = await _raw(method, path, body: body);
    }
    return resp;
  }

  Future<http.Response> _raw(String method, String path, {Object? body}) {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = {
      'Cookie': 'sid=$_sid',
      'Accept': 'application/json',
    };
    switch (method) {
      case 'GET':
        return http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
      case 'POST':
        return http
            .post(uri, headers: headers, body: body)
            .timeout(const Duration(seconds: 20));
      default:
        throw FrappeException('HTTP-Methode $method nicht unterstützt.');
    }
  }

  /// Testabfrage: liefert die eingeloggte Benutzer-ID (E-Mail) vom Server.
  Future<String> getLoggedUser() async {
    final resp = await get('/api/method/frappe.auth.get_logged_user');
    if (resp.statusCode != 200) {
      throw FrappeException('Abfrage fehlgeschlagen (HTTP ${resp.statusCode}).');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['message'] as String? ?? '?';
  }

  /// Kurzer Erreichbarkeitstest des Servers. Jede HTTP-Antwort (auch 403)
  /// gilt als "online" – nur Netzwerkfehler/Timeout bedeuten "offline".
  Future<bool> ping() async {
    final url = _baseUrl;
    if (url == null) return false;
    try {
      final resp = await http.get(
        Uri.parse('$url/api/method/frappe.auth.get_logged_user'),
        headers: {'Cookie': 'sid=${_sid ?? ''}', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 6));
      return resp.statusCode > 0;
    } catch (_) {
      return false;
    }
  }

  /// Ruft eine whitelisted Frappe-Methode auf und gibt das `message`-Feld zurück.
  /// Beispiel: callMethod('apex.workforce.mobile.get_me').
  Future<dynamic> callMethod(
    String method, {
    Map<String, dynamic>? args,
    bool post = false,
  }) async {
    final http.Response resp;
    if (post) {
      resp = await this.post(
        '/api/method/$method',
        body: args?.map((k, v) => MapEntry(k, '$v')),
      );
    } else {
      final query = (args == null || args.isEmpty)
          ? ''
          : '?${Uri(queryParameters: args.map((k, v) => MapEntry(k, '$v'))).query}';
      resp = await get('/api/method/$method$query');
    }
    if (resp.statusCode != 200) {
      throw FrappeException(
        _extractError(resp) ?? 'Serverfehler bei $method (HTTP ${resp.statusCode}).',
      );
    }
    final data = jsonDecode(resp.body);
    if (data is Map<String, dynamic> && data.containsKey('message')) {
      return data['message'];
    }
    return data;
  }

  /// Holt den persönlichen Zeiterfassungs-Status (apx-mobile-time / get_me).
  Future<Map<String, dynamic>> getMe() async {
    final msg = await callMethod('apex.workforce.mobile.get_me');
    return (msg is Map<String, dynamic>) ? msg : <String, dynamic>{'raw': msg};
  }

  /// Versucht, aus einer Frappe-Fehlerantwort eine lesbare Meldung zu ziehen.
  String? _extractError(http.Response resp) {
    try {
      final data = jsonDecode(resp.body);
      if (data is Map) {
        final sm = data['_server_messages'];
        if (sm is String && sm.isNotEmpty) {
          final list = jsonDecode(sm);
          if (list is List && list.isNotEmpty) {
            final first = jsonDecode(list.first as String);
            if (first is Map && first['message'] != null) {
              return first['message'].toString();
            }
          }
        }
        if (data['exception'] != null) return data['exception'].toString();
        if (data['message'] != null && data['message'] is String) {
          return data['message'] as String;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Zieht den `sid`-Wert aus dem Set-Cookie-Header. 'Guest' zählt als kein Login.
  String? _extractSid(String? setCookie) {
    if (setCookie == null) return null;
    final match = RegExp(r'sid=([^;]+)').firstMatch(setCookie);
    final sid = match?.group(1);
    if (sid == null || sid.isEmpty || sid == 'Guest') return null;
    return sid;
  }
}
