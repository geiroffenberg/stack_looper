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
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Row(
                  children: [
                    _SettingsItem(
                      label: 'BPM',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _BpmStepperButton(
                            icon: Icons.remove,
                            onPressed: _decreaseBpm,
                          ),
                          Container(
                            width: 1,
                            height: 24,
                            color: Theme.of(context).dividerColor.withOpacity(0.75),
                          ),
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
                                filled: false,
                                fillColor: Colors.transparent,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                border: InputBorder.none,
                              ),
                              onSubmitted: _submitBpm,
                              onTapOutside: (_) => _submitBpm(_bpmController.text),
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 24,
                            color: Theme.of(context).dividerColor.withOpacity(0.75),
                          ),
                          _BpmStepperButton(
                            icon: Icons.add,
                            onPressed: _increaseBpm,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _SettingsItem(
                      label: 'Repeat',
                      framed: true,
                      child: _CompactDropdown(
                        value: widget.repeatCount,
                        options: widget.repeatOptions,
                        onChanged: widget.onRepeatChanged,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _SettingsItem(
                      label: 'Tracks',
                      framed: true,
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
        },
      ),
    );
  }

  Widget _SettingsItem({
    required String label,
    required Widget child,
    bool framed = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).textTheme.labelMedium?.color,
          ),
        ),
        const SizedBox(height: 4),
        if (framed)
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.45),
              border: Border.all(
                color: Theme.of(context).dividerColor.withOpacity(0.82),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: child,
          )
        else
          child,
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
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          border: InputBorder.none,
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

class _BpmStepperButton extends StatelessWidget {
  const _BpmStepperButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(
        minHeight: 32,
        minWidth: 32,
      ),
    );
  }
}
