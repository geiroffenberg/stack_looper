import 'package:flutter/material.dart';

import '../models/looper_state.dart';

class TopMenuBar extends StatelessWidget {
  const TopMenuBar({
    super.key,
    required this.transportState,
    required this.onPlay,
    required this.onRecord,
    required this.onToggleHeadphoneBleed,
    required this.headphoneSafetyEnabled,
    required this.onClearAll,
    required this.onFxPressed,
    required this.canRecord,
    required this.beatFlash,
    required this.recordArmed,
    required this.armedBlinkOn,
    required this.onSettingsPressed,
  });

  final TransportState transportState;
  final VoidCallback onPlay;
  final VoidCallback onRecord;
  final VoidCallback onToggleHeadphoneBleed;
  final bool headphoneSafetyEnabled;
  final VoidCallback onClearAll;
  final VoidCallback onFxPressed;
  final bool canRecord;
  final bool beatFlash;
  final bool recordArmed;
  final bool armedBlinkOn;
  final VoidCallback onSettingsPressed;

  @override
  Widget build(BuildContext context) {
    final bool isRecording = transportState == TransportState.recording;
    final bool isCountIn = transportState == TransportState.countIn;
    final bool isRecordActive = isRecording || isCountIn || recordArmed;
    final bool isPlaying = transportState != TransportState.stopped;
    final IconData playIcon = isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded;
    final Color borderColor = Theme.of(context).colorScheme.primary.withOpacity(0.5);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: _ButtonGroup(
              borderColor: borderColor,
              child: Row(
                children: [
                  Expanded(
                    child: _TransportButton(
                      icon: Icons.fiber_manual_record_rounded,
                      isActive: isRecordActive,
                      activeColor: Colors.red,
                      enabled: canRecord,
                      onPressed: onRecord,
                      flashActive: beatFlash || armedBlinkOn,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TransportButton(
                      icon: playIcon,
                      isActive: isPlaying,
                      activeColor: Colors.green,
                      enabled: true,
                      onPressed: onPlay,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 7,
            child: _ButtonGroup(
              borderColor: borderColor,
              child: Row(
                children: [
                  Expanded(
                    child: _MenuActionButton(
                      icon: Icons.headset_off_rounded,
                      tooltip: 'No headphones',
                      onPressed: onToggleHeadphoneBleed,
                      isActive: headphoneSafetyEnabled,
                      activeColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _MenuActionButton(
                      icon: Icons.delete_sweep_rounded,
                      tooltip: 'Clear all',
                      onPressed: onClearAll,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _MenuActionButton(
                      icon: Icons.tune_rounded,
                      tooltip: 'FX',
                      onPressed: onFxPressed,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _MenuActionButton(
                      icon: Icons.settings_rounded,
                      tooltip: 'Settings',
                      onPressed: onSettingsPressed,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ButtonGroup extends StatelessWidget {
  const _ButtonGroup({
    required this.borderColor,
    required this.child,
  });

  final Color borderColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: child,
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
        minimumSize: const Size.fromHeight(44),
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        backgroundColor:
            isActive
                ? activeColor.withOpacity(flashActive ? 0.72 : 0.22)
                : Theme.of(context).colorScheme.surface.withOpacity(0.35),
        side: BorderSide(
          color: isActive
              ? activeColor.withOpacity(0.75)
              : Theme.of(context).dividerColor.withOpacity(0.85),
          width: 1,
        ),
      ),
      icon: Icon(icon, color: isActive ? activeColor : null),
    );
  }
}

class _MenuActionButton extends StatelessWidget {
  const _MenuActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isActive = false,
    this.activeColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isActive;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        backgroundColor: isActive
            ? (activeColor ?? Theme.of(context).colorScheme.primary)
                .withOpacity(0.25)
            : Theme.of(context).colorScheme.surface.withOpacity(0.35),
        side: BorderSide(
          color: isActive
              ? (activeColor ?? Theme.of(context).colorScheme.primary)
                  .withOpacity(0.75)
              : Theme.of(context).dividerColor.withOpacity(0.85),
          width: 1,
        ),
      ),
      icon: Icon(
        icon,
        size: 20,
        color: isActive ? (activeColor ?? Theme.of(context).colorScheme.primary) : null,
      ),
    );
  }
}
