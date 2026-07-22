import 'package:flutter/material.dart';
import 'services/credential_store.dart';
import 'services/frappe_client.dart';
import 'screens/login_screen.dart';
import 'screens/home_page.dart';

void main() {
  final client = FrappeClient(CredentialStore());
  runApp(ApexApp(client: client));
}

class ApexApp extends StatelessWidget {
  const ApexApp({super.key, required this.client});
  final FrappeClient client;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ApeX Mobile App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: AuthGate(client: client),
    );
  }
}

/// Beim Start: gespeicherte Zugangsdaten prüfen und automatisch einloggen.
/// Klappt das, geht es direkt zur Startseite; sonst zum Login.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.client});
  final FrappeClient client;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<bool> _restore = widget.client.restoreSession();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _restore,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.data == true) {
          return HomePage(client: widget.client);
        }
        return LoginScreen(client: widget.client);
      },
    );
  }
}
