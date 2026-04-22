import 'package:flutter/material.dart';

import '../models/looper_state.dart';

class TopMenuBar extends StatelessWidget {
  const TopMenuBar({
    super.key,
    required this.transportState,
    required this.onPlay,
    required this.onRecord,
    required this.canRecord,
    required this.beatFlash,
    required this.onSettingsPressed,
  });

  final TransportState transportState;
  final VoidCallback onPlay;
  final VoidCallback onRecord;
  final bool canRecord;
  final bool beatFlash;
  final VoidCallback onSettingsPressed;

  @override
  Widget build(BuildContext context) {
    final bool isRecording = transportState == TransportState.recording;
    final bool isCountIn = transportState == TransportState.countIn;
    final bool isRecordActive = isRecording || isCountIn;
    final bool isPlaying = transportState != TransportState.stopped;
    final IconData playIcon = isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            _TransportButton(
              icon: Icons.fiber_manual_record_rounded,
              isActive: isRecordActive,
              activeColor: Colors.red,
              enabled: canRecord,
              onPressed: onRecord,
              flashActive: beatFlash,
            ),
            const SizedBox(width: 8),
            _TransportButton(
              icon: playIcon,
              isActive: isPlaying,
              activeColor: Colors.green,
              enabled: true,
              onPressed: onPlay,
            ),
            const Spacer(),
            IconButton(
              onPressed: onSettingsPressed,
              icon: const Icon(Icons.settings),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.icon,
    required this.isActive,
    required this.activeColor,
    required this.enabled,
    required this.onPressed,
    this.flashActive = false,
  });

  final IconData icon;
  final bool isActive;
  final Color activeColor;
  final bool enabled;
  final VoidCallback onPressed;
  final bool flashActive;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: enabled ? onPressed : null,
      style: IconButton.styleFrom(
        backgroundColor:
            isActive ? activeColor.withOpacity(flashActive ? 0.65 : 0.22) : null,
      ),
      icon: Icon(icon, color: isActive ? activeColor : null),
    );
  }
}
