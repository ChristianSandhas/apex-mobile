import 'dart:async';
import 'package:flutter/material.dart';
import '../models/time_models.dart';
import '../services/frappe_client.dart';
import '../services/connectivity_service.dart';
import '../services/time_tracking_service.dart';
import '../services/location_service.dart';
import '../widgets/connection_indicator.dart';
import 'booking_wizard.dart';
import 'team_select_screen.dart';
import 'qr_scan_screen.dart';

/// Persönliche Zeiterfassung (apx-mobile-time): eigener Status + Ein-/Ausstempeln,
/// Pause/Fortsetzen, Buchungs-Assistent und die Team-Funktion (Kolonne).
class ZeiterfassungScreen extends StatefulWidget {
  const ZeiterfassungScreen({
    super.key,
    required this.client,
    required this.connectivity,
  });

  final FrappeClient client;
  final ConnectivityService connectivity;

  @override
  State<ZeiterfassungScreen> createState() => _ZeiterfassungScreenState();
}

class _ZeiterfassungScreenState extends State<ZeiterfassungScreen> {
  late final TimeTrackingService _service = TimeTrackingService(widget.client);
  final LocationService _location = LocationService();

  TimeStatus? _status;
  Object? _error;
  bool _loadingInitial = true;
  bool _busy = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _status?.running?.since != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loadingInitial = _status == null;
      _error = null;
    });
    try {
      final s = await _service.getMe();
      if (mounted) setState(() => _status = s);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loadingInitial = false);
    }
  }

  /// Führt eine Aktion aus und lädt danach den Gesamtstatus (eigen + Team) neu.
  Future<void> _run(Future<dynamic> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      final s = await _service.getMe();
      if (mounted) setState(() => _status = s);
    } catch (e) {
      _snack('$e');
      widget.connectivity.check();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  /// Ermittelt den Standort für eine Buchung. Ist GPS Pflicht und nicht
  /// verfügbar, wird null zurückgegeben (Buchung abbrechen) und eine Meldung
  /// angezeigt.
  Future<({double? lat, double? lng})?> _resolveGps(TimeStatus status) async {
    if (!status.requireGps) {
      final g = await _location.current();
      return (lat: g.lat, lng: g.lng);
    }
    final r = await _location.require();
    if (r.error != null) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(r.error!),
          behavior: SnackBarBehavior.floating,
          action: r.openSettings
              ? SnackBarAction(
                  label: 'Einstellungen',
                  onPressed: () => _location.openSettings(),
                )
              : null,
        ),
      );
      return null;
    }
    return (lat: r.lat, lng: r.lng);
  }

  Future<BookingChoice?> _openWizard(TimeStatus status) {
    return Navigator.of(context).push<BookingChoice>(
      MaterialPageRoute(
        builder: (_) => BookingWizard(service: _service, status: status),
      ),
    );
  }

  /// Fragt bei aktivem Team, ob die Aktion aufs ganze Team angewendet wird.
  /// null = abgebrochen.
  Future<bool?> _askApplyTeam() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Auf Team anwenden?'),
        content: const Text(
          'Soll diese Aktion auch für alle Team-Mitglieder ausgeführt werden?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nur ich'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ganzes Team'),
          ),
        ],
      ),
    );
  }

  // --- eigene Aktionen -------------------------------------------------------

  Future<void> _selfAction(Future<dynamic> Function(bool applyTeam) fn) async {
    var applyTeam = false;
    if (_status?.hasTeam == true) {
      final r = await _askApplyTeam();
      if (r == null) return;
      applyTeam = r;
    }
    await _run(() => fn(applyTeam));
  }

  Future<void> _bookSelf() async {
    final status = _status;
    if (status == null) return;
    _location.warmUp(); // Standort-Fix schon während der Auswahl anstoßen
    final choice = await _openWizard(status);
    if (choice == null) return;
    var applyTeam = false;
    if (status.hasTeam) {
      final r = await _askApplyTeam();
      if (r == null) return;
      applyTeam = r;
    }
    final geo = await _resolveGps(status);
    if (geo == null) return; // GPS Pflicht, aber nicht verfügbar
    await _run(
      () => _service.book(
        costCenter: choice.costCenter,
        projectOrder: choice.projectOrder,
        position: choice.position,
        latitude: geo.lat,
        longitude: geo.lng,
        applyTeam: applyTeam,
      ),
    );
  }

  // --- Team-Mitglied-Aktionen ------------------------------------------------

  Future<void> _memberActions(TeamMember m) async {
    final status = _status;
    if (status == null) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        Widget tile(
          IconData icon,
          String label,
          Color color,
          VoidCallback onTap,
        ) {
          return ListTile(
            leading: Icon(icon, color: color),
            title: Text(label),
            onTap: () {
              Navigator.pop(ctx);
              onTap();
            },
          );
        }

        final items = <Widget>[];
        if (status.canScan) {
          items.add(
            tile(
              Icons.qr_code_scanner,
              'Scannen (QR)',
              Colors.blue,
              () => _scanForMember(m),
            ),
          );
        }
        switch (m.state) {
          case TimeState.out:
            items.add(
              tile(
                Icons.play_arrow,
                'Einstempeln',
                Colors.green,
                () => _bookMember(m, status),
              ),
            );
          case TimeState.working:
            items.add(
              tile(
                Icons.pause,
                'Pause',
                Colors.orange,
                () => _run(() => _service.pause(employee: m.employee)),
              ),
            );
            items.add(
              tile(
                Icons.swap_horiz,
                'Umbuchen',
                Theme.of(context).colorScheme.primary,
                () => _bookMember(m, status),
              ),
            );
            items.add(
              tile(
                Icons.stop,
                'Ausstempeln',
                Colors.red,
                () => _run(() => _service.clockOut(employee: m.employee)),
              ),
            );
          case TimeState.paused:
            items.add(
              tile(
                Icons.play_arrow,
                'Fortsetzen',
                Colors.green,
                () => _run(() => _service.resume(employee: m.employee)),
              ),
            );
            items.add(
              tile(
                Icons.stop,
                'Ausstempeln',
                Colors.red,
                () => _run(() => _service.clockOut(employee: m.employee)),
              ),
            );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  m.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(height: 1),
              ...items,
            ],
          ),
        );
      },
    );
  }

  Future<void> _scanForMember(TeamMember m) async {
    final status = _status;
    if (status == null) return;
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => QrScanScreen(
          service: _service,
          status: status,
          targetEmployee: m.employee,
          targetName: m.name,
          targetOnBreak: m.onBreak,
        ),
      ),
    );
    if (done == true) _load();
  }

  Future<void> _bookMember(TeamMember m, TimeStatus status) async {
    _location.warmUp();
    final choice = await _openWizard(status);
    if (choice == null) return;
    final geo = await _resolveGps(status);
    if (geo == null) return; // GPS Pflicht, aber nicht verfügbar
    await _run(
      () => _service.book(
        costCenter: choice.costCenter,
        projectOrder: choice.projectOrder,
        position: choice.position,
        latitude: geo.lat,
        longitude: geo.lng,
        employee: m.employee,
      ),
    );
  }

  Future<void> _openScan() async {
    final status = _status;
    if (status == null) return;
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => QrScanScreen(service: _service, status: status),
      ),
    );
    if (done == true) _load();
  }

  Future<void> _openTeamSelect() async {
    final status = _status;
    if (status == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TeamSelectScreen(
          service: _service,
          current: status.team.map((m) => m.employee).toList(),
          until: status.teamUntil,
        ),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final allowTeam = _status?.allowTeam == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zeiterfassung'),
        actions: [
          if (allowTeam)
            IconButton(
              icon: const Icon(Icons.groups),
              tooltip: 'Team auswählen',
              onPressed: _openTeamSelect,
            ),
          ConnectionIndicator(connectivity: widget.connectivity),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(onRefresh: _load, child: _buildBody()),
            if (_busy)
              Container(
                color: Colors.black.withValues(alpha: 0.15),
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingInitial) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_status == null && _error != null) {
      return _ErrorView(message: '$_error', onRetry: _load);
    }
    final status = _status!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatusCard(status: status),
        const SizedBox(height: 20),
        ..._ownActions(status),
        if (status.hasTeam) ...[
          const SizedBox(height: 28),
          Row(
            children: [
              const Icon(Icons.groups, size: 20),
              const SizedBox(width: 8),
              Text('Team', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (status.teamUntil != null)
                Text(
                  'bis ${status.teamUntil}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          const SizedBox(height: 8),
          ...status.team.map(
            (m) => _TeamCard(member: m, onTap: () => _memberActions(m)),
          ),
        ],
      ],
    );
  }

  List<Widget> _ownActions(TimeStatus status) {
    final scan = status.canScan
        ? [
            _bigButton(
              Icons.qr_code_scanner,
              'Scannen (QR)',
              Colors.blue,
              _openScan,
            ),
            const SizedBox(height: 12),
          ]
        : <Widget>[];

    switch (status.state) {
      case TimeState.out:
        return [
          ...scan,
          if (status.canManual)
            _bigButton(
              Icons.play_arrow,
              'Einstempeln',
              Colors.green,
              _bookSelf,
            ),
        ];
      case TimeState.working:
        return [
          ...scan,
          _bigButton(
            Icons.pause,
            'Pause',
            Colors.orange,
            () => _selfAction((at) => _service.pause(applyTeam: at)),
          ),
          const SizedBox(height: 12),
          if (status.canManual) ...[
            _bigButton(
              Icons.swap_horiz,
              'Umbuchen',
              Theme.of(context).colorScheme.primary,
              _bookSelf,
            ),
            const SizedBox(height: 12),
          ],
          _bigButton(
            Icons.stop,
            'Ausstempeln',
            Colors.red,
            () => _selfAction((at) => _service.clockOut(applyTeam: at)),
          ),
        ];
      case TimeState.paused:
        return [
          ...scan,
          _bigButton(
            Icons.play_arrow,
            'Fortsetzen',
            Colors.green,
            () => _selfAction((at) => _service.resume(applyTeam: at)),
          ),
          const SizedBox(height: 12),
          _bigButton(
            Icons.stop,
            'Ausstempeln',
            Colors.red,
            () => _selfAction((at) => _service.clockOut(applyTeam: at)),
          ),
        ];
    }
  }

  Widget _bigButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return SizedBox(
      height: 60,
      child: FilledButton.icon(
        onPressed: _busy ? null : onTap,
        icon: Icon(icon, size: 26),
        label: Text(label, style: const TextStyle(fontSize: 18)),
        style: FilledButton.styleFrom(backgroundColor: color),
      ),
    );
  }
}

/// Kärtchen eines Team-Mitglieds mit Status-Punkt und aktueller Buchung.
class _TeamCard extends StatelessWidget {
  const _TeamCard({required this.member, required this.onTap});

  final TeamMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (member.state) {
      TimeState.working => Colors.green,
      TimeState.paused => Colors.orange,
      TimeState.out => Colors.grey,
    };
    final summary = member.bookingSummary;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        title: Text(member.name),
        subtitle: summary != null ? Text(summary) : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Statuskarte: Name, Zustand, laufender Timer, aktuelle Buchung, heute-Stunden.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final TimeStatus status;

  ({String text, Color color, IconData icon}) get _badge =>
      switch (status.state) {
        TimeState.working => (
          text: 'Anwesend',
          color: Colors.green,
          icon: Icons.work,
        ),
        TimeState.paused => (
          text: 'In Pause',
          color: Colors.orange,
          icon: Icons.pause_circle,
        ),
        TimeState.out => (
          text: 'Ausgestempelt',
          color: Colors.grey,
          icon: Icons.logout,
        ),
      };

  String _elapsed() {
    final since = status.running?.since;
    if (since == null) return '';
    var d = DateTime.now().difference(since);
    if (d.isNegative) d = Duration.zero;
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badge = _badge;
    final running = status.running;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    status.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: badge.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(badge.icon, size: 16, color: badge.color),
                      const SizedBox(width: 6),
                      Text(
                        badge.text,
                        style: TextStyle(
                          color: badge.color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (running?.since != null) ...[
              const SizedBox(height: 20),
              Center(
                child: Text(
                  _elapsed(),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_hasBooking(running!)) ...[
                const Divider(height: 24),
                if (running.vorgangDisplay != null)
                  _row(
                    context,
                    Icons.assignment,
                    'Vorgang',
                    running.vorgangDisplay!,
                    sub: running.customer,
                  ),
                if (running.positionDisplay != null)
                  _row(
                    context,
                    Icons.list_alt,
                    'Position',
                    running.positionDisplay!,
                  ),
                if (running.kostenstelleDisplay != null)
                  _row(
                    context,
                    Icons.account_balance,
                    'Kostenstelle',
                    running.kostenstelleDisplay!,
                  ),
              ],
            ],
            const Divider(height: 24),
            _row(
              context,
              Icons.today,
              'Heute',
              '${status.todayHours.toStringAsFixed(2)} h',
            ),
          ],
        ),
      ),
    );
  }

  bool _hasBooking(RunningEntry r) =>
      r.vorgangDisplay != null ||
      r.positionDisplay != null ||
      r.kostenstelleDisplay != null;

  Widget _row(
    BuildContext context,
    IconData icon,
    String label,
    String value, {
    String? sub,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value, textAlign: TextAlign.right),
                if (sub != null && sub.isNotEmpty)
                  Text(
                    sub,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
        const SizedBox(height: 16),
        Text(
          'Status konnte nicht geladen werden',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        Center(
          child: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
        ),
      ],
    );
  }
}
