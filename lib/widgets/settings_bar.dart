import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_constants.dart';

class SettingsBar extends StatefulWidget {
  const SettingsBar({
    super.key,
    required this.bpm,
    required this.repeatCount,
    required this.numTracksToRecord,
    required this.repeatOptions,
    required this.numTrackOptions,
    required this.onBpmChanged,
    required this.onRepeatChanged,
    required this.onNumTracksChanged,
  });

  final int bpm;
  final int repeatCount;
  final int numTracksToRecord;
  final List<int> repeatOptions;
  final List<int> numTrackOptions;
  final ValueChanged<int> onBpmChanged;
  final ValueChanged<int> onRepeatChanged;
  final ValueChanged<int> onNumTracksChanged;

  @override
  State<SettingsBar> createState() => _SettingsBarState();
}

class _SettingsBarState extends State<SettingsBar> {
  late final TextEditingController _bpmController;

  @override
  void initState() {
    super.initState();
    _bpmController = TextEditingController(text: widget.bpm.toString());
  }

  @override
  void didUpdateWidget(covariant SettingsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bpm != widget.bpm &&
        _bpmController.text != widget.bpm.toString()) {
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

  void _decreaseBpm() {
    final int newBpm = (widget.bpm - 1).clamp(
      AppConstants.minBpm,
      AppConstants.maxBpm,
    );
    widget.onBpmChanged(newBpm);
  }

  void _increaseBpm() {
    final int newBpm = (widget.bpm + 1).clamp(
      AppConstants.minBpm,
      AppConstants.maxBpm,
    );
    widget.onBpmChanged(newBpm);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _SettingsItem(
                label: 'BPM',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _decreaseBpm,
                      icon: const Icon(Icons.remove, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minHeight: 32,
                        minWidth: 32,
                      ),
                    ),
                    const SizedBox(width: 4),
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
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                        ),
                        onSubmitted: _submitBpm,
                        onTapOutside: (_) => _submitBpm(_bpmController.text),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: _increaseBpm,
                      icon: const Icon(Icons.add, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minHeight: 32,
                        minWidth: 32,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _SettingsItem(
                label: 'Repeat',
                child: _CompactDropdown(
                  value: widget.repeatCount,
                  options: widget.repeatOptions,
                  onChanged: widget.onRepeatChanged,
                ),
              ),
              const SizedBox(width: 12),
              _SettingsItem(
                label: 'Tracks',
                child: _CompactDropdown(
                  value: widget.numTracksToRecord,
                  options: widget.numTrackOptions,
                  onChanged: widget.onNumTracksChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _SettingsItem({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24, width: 1),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: child,
        ),
      ],
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
      width: 70,
      child: DropdownButtonFormField<int>(
        isDense: true,
        initialValue: options.contains(value) ? value : options.first,
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        ),
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
