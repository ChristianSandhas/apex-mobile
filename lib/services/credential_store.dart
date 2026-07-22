import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Die dauerhaft gespeicherten Zugangsdaten.
class Credentials {
  final String baseUrl;
  final String username;
  final String password;

  const Credentials({
    required this.baseUrl,
    required this.username,
    required this.password,
  });
}

/// Speichert die Frappe-Zugangsdaten verschlüsselt.
/// Auf iOS landet das im Keychain, auf Android in verschlüsselten Preferences.
class CredentialStore {
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _kUrl = 'frappe_url';
  static const _kUser = 'frappe_user';
  static const _kPass = 'frappe_pass';

  Future<void> save(Credentials c) async {
    await _storage.write(key: _kUrl, value: c.baseUrl);
    await _storage.write(key: _kUser, value: c.username);
    await _storage.write(key: _kPass, value: c.password);
  }

  Future<Credentials?> load() async {
    final url = await _storage.read(key: _kUrl);
    final user = await _storage.read(key: _kUser);
    final pass = await _storage.read(key: _kPass);
    if (url == null || user == null || pass == null) return null;
    return Credentials(baseUrl: url, username: user, password: pass);
  }

  Future<void> clear() async {
    await _storage.delete(key: _kUrl);
    await _storage.delete(key: _kUser);
    await _storage.delete(key: _kPass);
  }
}
