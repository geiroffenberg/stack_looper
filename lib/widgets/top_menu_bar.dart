import 'package:flutter/material.dart';

import '../models/looper_state.dart';

class TopMenuBar extends StatelessWidget {
  const TopMenuBar({
    super.key,
    required this.transportState,
    required this.bpm,
    required this.repeatCount,
    required this.numTracksToRecord,
    required this.bpmOptions,
    required this.repeatOptions,
    required this.numTrackOptions,
    required this.onPlay,
    required this.onStop,
    required this.onRecord,
    required this.onBpmChanged,
    required this.onRepeatChanged,
    required this.onNumTracksChanged,
    required this.canPlay,
    required this.canStop,
    required this.canRecord,
  });

  final TransportState transportState;
  final int bpm;
  final int repeatCount;
  final int numTracksToRecord;
  final List<int> bpmOptions;
  final List<int> repeatOptions;
  final List<int> numTrackOptions;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final VoidCallback onRecord;
  final ValueChanged<int> onBpmChanged;
  final ValueChanged<int> onRepeatChanged;
  final ValueChanged<int> onNumTracksChanged;
  final bool canPlay;
  final bool canStop;
  final bool canRecord;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _MenuButton(
              icon: Icons.play_arrow_rounded,
              isActive: transportState == TransportState.playing,
              enabled: canPlay,
              onPressed: onPlay,
            ),
            _MenuButton(
              icon: Icons.stop_rounded,
              isActive: transportState == TransportState.stopped,
              enabled: canStop,
              onPressed: onStop,
            ),
            _MenuButton(
              icon: Icons.fiber_manual_record_rounded,
              isActive: transportState == TransportState.recording,
              enabled: canRecord,
              onPressed: onRecord,
            ),
            _LabeledDropdown<int>(
              label: 'BPM',
              value: bpm,
              options: bpmOptions,
              toLabel: (v) => '$v',
              onChanged: onBpmChanged,
            ),
            _LabeledDropdown<int>(
              label: 'Repeat',
              value: repeatCount,
              options: repeatOptions,
              toLabel: (v) => '$v',
              onChanged: onRepeatChanged,
            ),
            _LabeledDropdown<int>(
              label: 'Tracks',
              value: numTracksToRecord,
              options: numTrackOptions,
              toLabel: (v) => '$v',
              onChanged: onNumTracksChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.isActive,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool isActive;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: enabled ? onPressed : null,
      style: IconButton.styleFrom(
        backgroundColor: isActive
            ? Theme.of(context).colorScheme.primary.withOpacity(0.25)
            : null,
      ),
      icon: Icon(icon),
    );
  }
}

class _LabeledDropdown<T> extends StatelessWidget {
  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.toLabel,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> options;
  final String Function(T) toLabel;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const SizedBox.shrink();
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 96),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          DropdownButtonFormField<T>(
            value: options.contains(value) ? value : options.first,
            items: options
                .map(
                  (option) => DropdownMenuItem<T>(
                    value: option,
                    child: Text(toLabel(option)),
                  ),
                )
                .toList(growable: false),
            onChanged: (updated) {
              if (updated != null) {
                onChanged(updated);
              }
            },
          ),
        ],
      ),
    );
  }
}
