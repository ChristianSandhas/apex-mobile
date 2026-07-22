import 'package:flutter/material.dart';
import '../models/time_models.dart';
import '../services/time_tracking_service.dart';

/// Auswahl der Team-Mitglieder (Kolonne). Gibt beim Speichern `true` zurück,
/// damit der aufrufende Screen neu lädt.
class TeamSelectScreen extends StatefulWidget {
  const TeamSelectScreen({
    super.key,
    required this.service,
    required this.current,
    required this.until,
  });

  final TimeTrackingService service;
  final List<String> current;
  final String? until;

  @override
  State<TeamSelectScreen> createState() => _TeamSelectScreenState();
}

class _TeamSelectScreenState extends State<TeamSelectScreen> {
  Future<List<TeamMember>>? _options;
  late Set<String> _selected;
  DateTime? _until;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _options = widget.service.getTeamOptions();
    _selected = {...widget.current};
    if (widget.until != null) _until = DateTime.tryParse(widget.until!);
  }

  String? _fmt(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickUntil() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _until ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _until = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.service.setTeam(_selected.toList(), until: _fmt(_until));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Team auswählen'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Speichern'),
          ),
        ],
      ),
      body: Stack(
        children: [
          FutureBuilder<List<TeamMember>>(
            future: _options,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Fehler:\n${snap.error}', textAlign: TextAlign.center),
                  ),
                );
              }
              final pool = snap.data ?? const <TeamMember>[];
              return ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.event),
                    title: const Text('Gültig bis'),
                    subtitle: Text(_fmt(_until) ?? 'unbegrenzt'),
                    trailing: _until == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _until = null),
                          ),
                    onTap: _pickUntil,
                  ),
                  const Divider(height: 1),
                  if (pool.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Keine auswählbaren Mitarbeiter.'),
                    ),
                  ...pool.map((m) {
                    final checked = _selected.contains(m.employee);
                    return CheckboxListTile(
                      value: checked,
                      title: Text(m.name),
                      subtitle: m.employeeNumber != null
                          ? Text(m.employeeNumber!)
                          : null,
                      secondary: _StatusDot(state: m.state),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selected.add(m.employee);
                        } else {
                          _selected.remove(m.employee);
                        }
                      }),
                    );
                  }),
                ],
              );
            },
          ),
          if (_saving)
            Container(
              color: Colors.black.withValues(alpha: 0.15),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.state});
  final TimeState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      TimeState.working => Colors.green,
      TimeState.paused => Colors.orange,
      TimeState.out => Colors.grey,
    };
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
