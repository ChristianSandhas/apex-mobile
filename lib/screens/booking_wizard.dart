import 'package:flutter/material.dart';
import '../models/time_models.dart';
import '../services/time_tracking_service.dart';

/// Das Ergebnis des Assistenten: die getroffene Buchungsauswahl.
class BookingChoice {
  final String? costCenter;
  final String? projectOrder;
  final String? position;
  const BookingChoice({this.costCenter, this.projectOrder, this.position});
}

/// Buchungs-Assistent: Vorgang → (Position) → Kostenstelle.
/// Gibt beim Abschluss eine [BookingChoice] zurück (oder null bei Abbruch).
class BookingWizard extends StatefulWidget {
  const BookingWizard({
    super.key,
    required this.service,
    required this.status,
  });

  final TimeTrackingService service;
  final TimeStatus status;

  @override
  State<BookingWizard> createState() => _BookingWizardState();
}

enum _Step { vorgang, position, kostenstelle }

class _BookingWizardState extends State<BookingWizard> {
  Future<Lookups>? _lookups;
  _Step _step = _Step.vorgang;

  ProjectOrder? _selectedPo;
  Position? _selectedPosition;

  Future<List<Position>>? _positions;
  // Wurde der Positions-Schritt tatsächlich angezeigt (Vorgang hat Positionen)?
  bool _positionsShown = false;

  // Zuletzt verwendete Vorgänge/Kostenstellen (best effort – leer bei Fehler).
  List<ProjectOrder> _recentPo = const [];
  List<CostCenter> _recentCc = const [];

  @override
  void initState() {
    super.initState();
    _lookups = widget.service.getLookups();
    widget.service.getRecent().then((r) {
      if (mounted) {
        setState(() {
          _recentPo = r.projectOrders;
          _recentCc = r.costCenters;
        });
      }
    }).catchError((_) {});
  }

  void _finish(String? costCenter) {
    Navigator.of(context).pop(
      BookingChoice(
        costCenter: costCenter,
        projectOrder: _selectedPo?.name,
        position: _selectedPosition?.name,
      ),
    );
  }

  void _pickVorgang(ProjectOrder? po) {
    _selectedPo = po;
    _selectedPosition = null;
    _positionsShown = false;
    if (po != null) {
      // Immer die Positionen laden; der Positions-Schritt überspringt sich
      // selbst, wenn der Vorgang keine (zeiterfassbaren) Positionen hat.
      _positions = widget.service.getPositions(po.name);
      setState(() => _step = _Step.position);
    } else {
      setState(() => _step = _Step.kostenstelle);
    }
  }

  void _pickPosition(Position? pos) {
    _selectedPosition = pos;
    setState(() => _step = _Step.kostenstelle);
  }

  void _back() {
    switch (_step) {
      case _Step.vorgang:
        Navigator.of(context).pop();
        break;
      case _Step.position:
        setState(() => _step = _Step.vorgang);
        break;
      case _Step.kostenstelle:
        setState(() => _step = _positionsShown ? _Step.position : _Step.vorgang);
        break;
    }
  }

  String get _title => switch (_step) {
        _Step.vorgang => 'Vorgang wählen',
        _Step.position => 'Position wählen',
        _Step.kostenstelle => 'Kostenstelle wählen',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
        title: Text(_title),
      ),
      body: switch (_step) {
        _Step.vorgang => _buildVorgang(),
        _Step.position => _buildPosition(),
        _Step.kostenstelle => _buildKostenstelle(),
      },
    );
  }

  Widget _buildVorgang() {
    return FutureBuilder<Lookups>(
      future: _lookups,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _error('${snap.error}');
        }
        final pos = snap.data!.projectOrders;
        return _PickerList<ProjectOrder>(
          items: pos,
          recent: _recentPo,
          allowNone: !widget.status.requireProjectOrder,
          noneLabel: '— ohne Vorgang —',
          onNone: () => _pickVorgang(null),
          titleOf: (p) => p.label,
          subtitleOf: (p) => p.subtitle,
          searchTextOf: (p) =>
              '${p.fullNumber ?? ''} ${p.customer ?? ''} ${p.designation ?? ''}',
          onTap: _pickVorgang,
        );
      },
    );
  }

  Widget _buildPosition() {
    return FutureBuilder<List<Position>>(
      future: _positions,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _error('${snap.error}');
        }
        final positions = snap.data ?? const <Position>[];
        // Wenn keine Positionen vorhanden sind, überspringen wir den Schritt.
        if (positions.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _step = _Step.kostenstelle);
          });
          return const Center(child: CircularProgressIndicator());
        }
        _positionsShown = true;
        return _PickerList<Position>(
          items: positions,
          allowNone: !(_selectedPo?.requirePositions ?? false),
          noneLabel: '— ohne Position —',
          onNone: () => _pickPosition(null),
          titleOf: (p) => p.label,
          subtitleOf: (p) => null,
          searchTextOf: (p) => p.label,
          onTap: _pickPosition,
        );
      },
    );
  }

  Widget _buildKostenstelle() {
    return FutureBuilder<Lookups>(
      future: _lookups,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _error('${snap.error}');
        }
        final ccs = snap.data!.costCenters;
        return _PickerList<CostCenter>(
          items: ccs,
          recent: _recentCc,
          allowNone: !widget.status.requireCostCenter,
          noneLabel: '— ohne Kostenstelle —',
          onNone: () => _finish(null),
          titleOf: (c) => c.label,
          subtitleOf: (c) => c.groupLabel,
          searchTextOf: (c) => '${c.number ?? ''} ${c.title ?? ''}',
          onTap: (c) => _finish(c.name),
        );
      },
    );
  }

  Widget _error(String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Fehler beim Laden:\n$msg', textAlign: TextAlign.center),
        ),
      );
}

/// Durchsuchbare Auswahlliste mit „— ohne … —"-Zeile, „Zuletzt verwendet"
/// und „Alle". Bei aktiver Suche wird nur die gefilterte Gesamtliste gezeigt.
class _PickerList<T> extends StatefulWidget {
  const _PickerList({
    required this.items,
    required this.allowNone,
    required this.noneLabel,
    required this.onNone,
    required this.titleOf,
    required this.subtitleOf,
    required this.searchTextOf,
    required this.onTap,
    this.recent = const [],
  });

  final List<T> items;
  final List<T> recent;
  final bool allowNone;
  final String noneLabel;
  final VoidCallback onNone;
  final String Function(T) titleOf;
  final String? Function(T) subtitleOf;
  final String Function(T) searchTextOf;
  final void Function(T) onTap;

  @override
  State<_PickerList<T>> createState() => _PickerListState<T>();
}

class _PickerListState<T> extends State<_PickerList<T>> {
  String _query = '';

  Widget _tile(T item) {
    final sub = widget.subtitleOf(item);
    return ListTile(
      title: Text(widget.titleOf(item)),
      subtitle: (sub != null && sub.isNotEmpty) ? Text(sub) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => widget.onTap(item),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final searching = q.isNotEmpty;

    final children = <Widget>[];
    if (searching) {
      final filtered = widget.items
          .where((e) => widget.searchTextOf(e).toLowerCase().contains(q))
          .toList();
      children.addAll(filtered.map(_tile));
      if (filtered.isEmpty) {
        children.add(const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Keine Treffer.', textAlign: TextAlign.center),
        ));
      }
    } else {
      if (widget.allowNone) {
        children.add(ListTile(
          leading: const Icon(Icons.block, color: Colors.grey),
          title: Text(widget.noneLabel),
          onTap: widget.onNone,
        ));
      }
      if (widget.recent.isNotEmpty) {
        children.add(_header('Zuletzt verwendet'));
        children.addAll(widget.recent.map(_tile));
        children.add(_header('Alle'));
      }
      children.addAll(widget.items.map(_tile));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Suchen …',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(child: ListView(children: children)),
      ],
    );
  }
}
