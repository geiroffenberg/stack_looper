import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/track.dart';

class TrackCard extends StatelessWidget {
  const TrackCard({
    super.key,
    required this.track,
    required this.isSelected,
    required this.onSelect,
    required this.onDelete,
    required this.onToggleMute,
    required this.onBarLengthChanged,
  });

  final Track track;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onDelete;
  final VoidCallback onToggleMute;
  final ValueChanged<int> onBarLengthChanged;

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected
        ? Theme.of(context).colorScheme.primary
        : Colors.transparent;

    return GestureDetector(
      onTap: onSelect,
      onLongPress: onDelete,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 2),
          color: Theme.of(context).cardTheme.color,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Track ${track.id + 1}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: 120,
                        child: DropdownButtonFormField<int>(
                          value: track.barLength,
                          decoration: const InputDecoration(labelText: 'Bars'),
                          items: AppConstants.barLengthValues
                              .map(
                                (value) => DropdownMenuItem<int>(
                                  value: value,
                                  child: Text('$value'),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (updated) {
                            if (updated != null) {
                              onBarLengthChanged(updated);
                            }
                          },
                        ),
                      ),
                      Chip(label: Text(_stateLabel(track.state))),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              children: [
                const Text('Mute'),
                Switch(
                  value: track.canMute && track.isMuted,
                  onChanged: track.canMute ? (_) => onToggleMute() : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _stateLabel(TrackState state) {
    switch (state) {
      case TrackState.empty:
        return 'Empty';
      case TrackState.recording:
        return 'Recording';
      case TrackState.playing:
        return 'Playing';
      case TrackState.looping:
        return 'Looping';
    }
  }
}
