import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_constants.dart';
import '../models/looper_state.dart';

class TopMenuBar extends StatefulWidget {
  const TopMenuBar({
    super.key,
    required this.transportState,
    required this.bpm,
    required this.repeatCount,
    required this.numTracksToRecord,
    required this.repeatOptions,
    required this.numTrackOptions,
    required this.onPlay,
    required this.onRecord,
    required this.onBpmChanged,
    required this.onRepeatChanged,
    required this.onNumTracksChanged,
    required this.canRecord,
  });

  final TransportState transportState;
  final int bpm;
  final int repeatCount;
  final int numTracksToRecord;
  final List<int> repeatOptions;
  final List<int> numTrackOptions;
  final VoidCallback onPlay;
  final VoidCallback onRecord;
  final ValueChanged<int> onBpmChanged;
  final ValueChanged<int> onRepeatChanged;
  final ValueChanged<int> onNumTracksChanged;
  final bool canRecord;

  @override
  State<TopMenuBar> createState() => _TopMenuBarState();
}

class _TopMenuBarState extends State<TopMenuBar> {
  late final TextEditingController _bpmController;

  @override
  void initState() {
    super.initState();
    _bpmController = TextEditingController(text: widget.bpm.toString());
  }

  @override
  void didUpdateWidget(covariant TopMenuBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bpm != widget.bpm && _bpmController.text != widget.bpm.toString()) {
      _bpmController.text = widget.bpm.toString();
    }
  }

  @override
  void dispose() {
    _bpmController.dispose();
    super.dispose();
  }

  void _submitBpm(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null) {
      _bpmController.text = widget.bpm.toString();
      return;
    }
    if (parsed < AppConstants.minBpm || parsed > AppConstants.maxBpm) {
      _bpmController.text = widget.bpm.toString();
      return;
    }
    widget.onBpmChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final bool isRecording = widget.transportState == TransportState.recording;
    final bool isPlaying = widget.transportState != TransportState.stopped;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            _TransportButton(
              icon: Icons.fiber_manual_record_rounded,
              isActive: isRecording,
              activeColor: Colors.red,
              enabled: widget.canRecord,
              onPressed: widget.onRecord,
            ),
            const SizedBox(width: 8),
            _TransportButton(
              icon: Icons.play_arrow_rounded,
              isActive: isPlaying,
              activeColor: Colors.green,
              enabled: true,
              onPressed: widget.onPlay,
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 64,
              child: TextField(
                controller: _bpmController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
                onSubmitted: _submitBpm,
                onTapOutside: (_) => _submitBpm(_bpmController.text),
              ),
            ),
            const Spacer(),
            _CompactDropdown(
              value: widget.repeatCount,
              options: widget.repeatOptions,
              onChanged: widget.onRepeatChanged,
            ),
            const SizedBox(width: 8),
            _CompactDropdown(
              value: widget.numTracksToRecord,
              options: widget.numTrackOptions,
              onChanged: widget.onNumTracksChanged,
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
  });

  final IconData icon;
  final bool isActive;
  final Color activeColor;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: enabled ? onPressed : null,
      style: IconButton.styleFrom(
        backgroundColor: isActive ? activeColor.withOpacity(0.28) : null,
      ),
      icon: Icon(icon, color: isActive ? activeColor : null),
    );
  }
}

class _CompactDropdown extends StatelessWidget {
  const _CompactDropdown({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final int value;
  final List<int> options;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: 60,
      child: DropdownButtonFormField<int>(
        isDense: true,
        value: options.contains(value) ? value : options.first,
        decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
        items: options
            .map(
              (option) => DropdownMenuItem<int>(
                value: option,
                child: Center(child: Text('$option')),
              ),
            )
            .toList(growable: false),
        onChanged: (updated) {
          if (updated != null) {
            onChanged(updated);
          }
        },
      ),
    );
  }
}
