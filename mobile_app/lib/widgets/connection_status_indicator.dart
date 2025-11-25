import 'package:flutter/material.dart';
import '../services/live_gemini_service.dart';

/// A widget that displays the current connection status with a colored indicator
class ConnectionStatusIndicator extends StatelessWidget {
  final LiveState connectionState;
  final double size;

  const ConnectionStatusIndicator({
    super.key,
    required this.connectionState,
    this.size = 12,
  });

  Color _getStatusColor() {
    switch (connectionState) {
      case LiveState.ready:
      case LiveState.recording:
        return Colors.green;
      case LiveState.connecting:
        return Colors.orange;
      case LiveState.disconnected:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _getStatusColor(),
        boxShadow: [
          BoxShadow(
            color: _getStatusColor().withValues(alpha: 0.5),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}
