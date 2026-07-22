import 'package:flutter/material.dart';
import '../services/frappe_client.dart';
import 'home_page.dart';
import 'login_screen.dart';

/// Wird direkt nach dem Login gezeigt: prüft die Verbindung per Testabfrage.
/// Bei Erfolg gibt es einen OK-Button, der weiter zur Home-Seite führt.
class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key, required this.client, this.welcome});

  final FrappeClient client;
  final String? welcome;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late Future<String> _user;

  @override
  void initState() {
    super.initState();
    _user = widget.client.getLoggedUser();
  }

  void _retry() {
    setState(() => _user = widget.client.getLoggedUser());
  }

  void _continue(String userId) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomePage(
          client: widget.client,
          userId: userId,
          fullName: widget.welcome,
        ),
      ),
    );
  }

  Future<void> _backToLogin() async {
    await widget.client.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => LoginScreen(client: widget.client)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: FutureBuilder<String>(
                future: _user,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const _CheckingView();
                  }
                  if (snap.hasError) {
                    return _ErrorView(
                      message: '${snap.error}',
                      onRetry: _retry,
                      onBack: _backToLogin,
                    );
                  }
                  return _SuccessView(
                    serverUrl: widget.client.baseUrl ?? '–',
                    userId: snap.data ?? '–',
                    fullName: widget.welcome,
                    onContinue: () => _continue(snap.data ?? '–'),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ladezustand während der Verbindungsprüfung.
class _CheckingView extends StatelessWidget {
  const _CheckingView();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 20),
        Text('Verbindung wird geprüft …'),
      ],
    );
  }
}

/// Erfolgsansicht mit Serverdaten und OK-Button.
class _SuccessView extends StatelessWidget {
  const _SuccessView({
    required this.serverUrl,
    required this.userId,
    required this.fullName,
    required this.onContinue,
  });

  final String serverUrl;
  final String userId;
  final String? fullName;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle_rounded, size: 72, color: Colors.green),
        const SizedBox(height: 16),
        Text(
          'Verbindung steht',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 24),
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              children: [
                _InfoRow(icon: Icons.dns_outlined, label: 'Server', value: serverUrl),
                const Divider(height: 1),
                _InfoRow(icon: Icons.badge_outlined, label: 'Benutzer', value: userId),
                if (fullName != null) ...[
                  const Divider(height: 1),
                  _InfoRow(icon: Icons.person_outline, label: 'Name', value: fullName!),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: onContinue,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('OK, weiter'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }
}

/// Fehleransicht mit Wiederholen- und Zurück-Option.
class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.cloud_off_rounded, size: 72, color: Colors.redAccent),
        const SizedBox(height: 16),
        Text(
          'Verbindung fehlgeschlagen',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Erneut versuchen'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: onBack,
          child: const Text('Zurück zum Login'),
        ),
      ],
    );
  }
}

/// Eine Info-Zeile mit Icon, Label und Wert.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
