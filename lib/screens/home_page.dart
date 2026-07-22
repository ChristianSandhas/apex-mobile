import 'package:flutter/material.dart';
import '../services/frappe_client.dart';
import '../services/connectivity_service.dart';
import '../widgets/connection_indicator.dart';
import 'login_screen.dart';
import 'zeiterfassung_screen.dart';

/// Die Haupt-Seite der App: Kachel-Übersicht der Bereiche.
/// Oben rechts die Online-/Offline-Anzeige, oben links das Hamburger-Menü.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.client,
    this.userId,
    this.fullName,
  });

  final FrappeClient client;
  final String? userId;
  final String? fullName;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final ConnectivityService _connectivity;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _userId = widget.userId;
    _connectivity = ConnectivityService(widget.client)..start();

    if (_userId == null) {
      widget.client.getLoggedUser().then((u) {
        if (mounted) setState(() => _userId = u);
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _connectivity.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await widget.client.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => LoginScreen(client: widget.client)),
    );
  }

  void _showInfo() {
    showAboutDialog(
      context: context,
      applicationName: 'ApeX Mobile App',
      applicationVersion: 'Version 0.0.1',
      applicationIcon: const Icon(Icons.timer_outlined, size: 40),
      children: const [
        SizedBox(height: 8),
        Text('Copyright 2026 Christian Sandhas'),
      ],
    );
  }

  void _openZeiterfassung() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ZeiterfassungScreen(
          client: widget.client,
          connectivity: _connectivity,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Datengetriebene Kachel-Liste – weitere Bereiche hier einfach ergänzen.
    final tiles = <_TileData>[
      _TileData(
        icon: Icons.access_time,
        label: 'Zeiterfassung',
        onTap: _openZeiterfassung,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('ApeX Mobile App'),
        actions: [ConnectionIndicator(connectivity: _connectivity)],
      ),
      drawer: _AppDrawer(
        title: widget.fullName ?? _userId ?? 'Angemeldet',
        subtitle: _userId,
        onLogout: () {
          Navigator.of(context).pop();
          _logout();
        },
        onInfo: () {
          Navigator.of(context).pop();
          _showInfo();
        },
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 190, // ergibt 2 Kacheln auf dem Handy, mehr auf breiten Geräten
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1, // quadratisch
        ),
        itemCount: tiles.length,
        itemBuilder: (context, i) => _Tile(data: tiles[i]),
      ),
    );
  }
}

/// Beschreibt eine Kachel.
class _TileData {
  const _TileData({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Eine quadratische Kachel mit Icon und Beschriftung darunter.
class _Tile extends StatelessWidget {
  const _Tile({required this.data});

  final _TileData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: data.onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(data.icon, size: 52, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              data.label,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Das Hamburger-Menü (Drawer).
class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.title,
    required this.subtitle,
    required this.onLogout,
    required this.onInfo,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onLogout;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
              ),
              currentAccountPicture: const CircleAvatar(
                child: Icon(Icons.timer_outlined, size: 32),
              ),
              accountName: Text(
                title,
                style: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
              accountEmail: subtitle == null
                  ? null
                  : Text(
                      subtitle!,
                      style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
                    ),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Abmelden'),
              onTap: onLogout,
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Info'),
              onTap: onInfo,
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Version 0.0.1\nCopyright 2026 Christian Sandhas',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
