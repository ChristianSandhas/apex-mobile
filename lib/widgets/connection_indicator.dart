import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';

/// Kleine Online-/Offline-Anzeige für die AppBar: farbiger Punkt + Text.
/// Grün = Verbindung zum Server, Rot = keine Verbindung.
class ConnectionIndicator extends StatelessWidget {
  const ConnectionIndicator({super.key, required this.connectivity});

  final ConnectivityService connectivity;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: connectivity.online,
      builder: (context, online, _) {
        final color = online ? Colors.green : Colors.red;
        return Padding(
          padding: const EdgeInsets.only(right: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(
                online ? 'Online' : 'Offline',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
