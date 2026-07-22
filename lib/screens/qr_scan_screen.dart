import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/time_models.dart';
import '../services/time_tracking_service.dart';
import '../services/location_service.dart';

/// Kamera-QR-Scan wie auf der bisherigen Mobile-Seite.
/// Verarbeitet die `APX:*`-Codes:
///  - PO/POS  → Vorgang/Position merken (Server leitet den Vorgang aus der Position ab)
///  - CC      → Kostenstelle → bucht sofort
///  - BREAK   → Pause ⇄ Fortsetzen (Umschalter)
///  - END     → Ausstempeln
///  - EMP     → anderer Mitarbeiter (nur Meister)
///
/// Gibt `true` zurück, wenn eine Aktion ausgeführt wurde (Aufrufer lädt neu).
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({
    super.key,
    required this.service,
    required this.status,
    this.targetEmployee,
    this.targetName,
    this.targetOnBreak = false,
  });

  final TimeTrackingService service;
  final TimeStatus status;

  /// Optionales Ziel-Mitglied (Team): dann gelten alle Scans für dieses Mitglied.
  final String? targetEmployee;
  final String? targetName;
  final bool targetOnBreak;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _Pending {
  String? employee;
  String? projectOrder;
  String? position;
  String? costCenter;

  bool get canBook =>
      projectOrder != null || position != null || costCenter != null;
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  final _Pending _pending = _Pending();
  final _re = RegExp(
    r'^APX:(EMP|PO|POS|CC|BREAK|PAUSE|END|ENDE)(?::(.+))?$',
    caseSensitive: false,
  );

  String? _message;
  bool _busy = false;
  String? _lastCode;
  DateTime? _lastAt;

  final LocationService _location = LocationService();

  @override
  void initState() {
    super.initState();
    _pending.employee = widget.targetEmployee;
    _location.warmUp(); // Standort-Fix vorbereiten (und Berechtigung früh anfragen)
  }

  // Pause/Fortsetzen hängt am Zustand des Ziels (Mitglied) bzw. an mir selbst.
  bool get _onBreak => widget.targetEmployee != null
      ? widget.targetOnBreak
      : widget.status.onBreak;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_busy) return;
    final code = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (code == null) return;

    // Wiederholungen desselben Codes für 2,5 s unterdrücken.
    final now = DateTime.now();
    if (_lastCode == code &&
        _lastAt != null &&
        now.difference(_lastAt!) < const Duration(milliseconds: 2500)) {
      return;
    }
    _lastCode = code;
    _lastAt = now;

    HapticFeedback.mediumImpact();
    _handle(code);
  }

  Future<void> _handle(String code) async {
    final m = _re.firstMatch(code);
    if (m == null) {
      setState(() => _message = 'Unbekannter Code: $code');
      return;
    }
    final kind = m.group(1)!.toUpperCase();
    final value = (m.group(2) ?? '').trim();
    setState(() => _message = null);

    switch (kind) {
      case 'EMP':
        if (!widget.status.canBookOthers) {
          setState(() =>
              _message = 'Buchen für andere ist nur mit Meister-Rolle möglich.');
          return;
        }
        setState(() => _pending.employee = value);
      case 'PO':
        setState(() {
          _pending.projectOrder = value;
          _pending.position = null;
        });
      case 'POS':
        setState(() {
          _pending.position = value;
          _pending.projectOrder = null; // Server leitet den Vorgang ab
        });
      case 'CC':
        _pending.costCenter = value;
        await _book(); // Kostenstelle schließt die Buchung ab (wie im Assistenten)
      case 'BREAK':
      case 'PAUSE':
        await _simple(() => _onBreak
            ? widget.service.resume(employee: _pending.employee)
            : widget.service.pause(employee: _pending.employee));
      default: // END / ENDE
        await _simple(() => widget.service.clockOut(employee: _pending.employee));
    }
  }

  Future<void> _book() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      double? lat;
      double? lng;
      if (widget.status.requireGps) {
        final r = await _location.require();
        if (r.error != null) {
          if (mounted) {
            setState(() {
              _message = r.error;
              _busy = false;
              _pending.costCenter = null; // nicht als „gebucht" festhalten
            });
          }
          return;
        }
        lat = r.lat;
        lng = r.lng;
      } else {
        final g = await _location.current();
        lat = g.lat;
        lng = g.lng;
      }
      await widget.service.book(
        costCenter: _pending.costCenter,
        projectOrder: _pending.projectOrder,
        position: _pending.position,
        latitude: lat,
        longitude: lng,
        employee: _pending.employee,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = '$e';
          _busy = false;
          _pending.costCenter = null; // Fehlbuchung nicht festhalten
        });
      }
    }
  }

  Future<void> _simple(Future<dynamic> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = '$e';
          _busy = false;
        });
      }
    }
  }

  String get _hint {
    if (_message != null) return _message!;
    final parts = <String>[];
    if (_pending.employee != null) {
      parts.add('Mitarbeiter: ${_pending.employee}');
    }
    if (_pending.position != null) {
      parts.add('Position ✓');
    } else if (_pending.projectOrder != null) {
      parts.add('Vorgang ✓');
    }
    if (parts.isNotEmpty) {
      return '${parts.join(' · ')} — Kostenstelle scannen oder „Jetzt buchen"';
    }
    return 'QR-Code scannen (Vorgang, Position, Kostenstelle …)';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.targetName != null ? 'QR – ${widget.targetName}' : 'QR scannen',
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: 'Blitz',
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Scan-Rahmen
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          // Hinweis + „Jetzt buchen"
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
              color: Colors.black.withValues(alpha: 0.6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  if (_pending.canBook) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _book,
                        icon: const Icon(Icons.check),
                        label: const Text('Jetzt buchen',
                            style: TextStyle(fontSize: 17)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_busy)
            Container(
              color: Colors.black.withValues(alpha: 0.4),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
