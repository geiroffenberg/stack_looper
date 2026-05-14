import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_constants.dart';

class SettingsBar extends StatefulWidget {
  const SettingsBar({
    super.key,
    required this.bpm,
    required this.repeatCount,
    required this.repeatOptions,
    required this.onBpmChanged,
    required this.onRepeatChanged,
    required this.headphoneSafetyEnabled,
    required this.onToggleHeadphoneSafety,
    required this.onSettingsPressed,
  });

  final int bpm;
  final int repeatCount;
  final List<int> repeatOptions;
  final ValueChanged<int> onBpmChanged;
  final ValueChanged<int> onRepeatChanged;
  final bool headphoneSafetyEnabled;
  final VoidCallback onToggleHeadphoneSafety;
  final VoidCallback onSettingsPressed;

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

  void _stepBpm(int delta) {
    final int next = (widget.bpm + delta).clamp(
      AppConstants.minBpm,
      AppConstants.maxBpm,
    );
    if (next != widget.bpm) {
      widget.onBpmChanged(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                          _BpmStepButton(
                            icon: Icons.remove_rounded,
                            onPressed: () => _stepBpm(-1),
                          ),
                          SizedBox(
                            width: 54,
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
                                  horizontal: 6,
                                  vertical: 8,
                                ),
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                border: InputBorder.none,
                              ),
                              onSubmitted: _submitBpm,
                              onTapOutside: (_) => _submitBpm(_bpmController.text),
                            ),
                          ),
                          _BpmStepButton(
                            icon: Icons.add_rounded,
                            onPressed: () => _stepBpm(1),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SettingsItem(
                      label: 'Repeat',
                      framed: true,
                      child: _CompactDropdown(
                        value: widget.repeatCount,
                        options: widget.repeatOptions,
                        onChanged: widget.onRepeatChanged,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SettingsItem(
                      label: 'Headphones',
                      framed: true,
                      child: SizedBox(
                        width: 44,
                        height: 36,
                        child: IconButton(
                          tooltip: 'No headphones',
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          onPressed: widget.onToggleHeadphoneSafety,
                          style: IconButton.styleFrom(
                            foregroundColor: widget.headphoneSafetyEnabled
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).iconTheme.color,
                            backgroundColor: widget.headphoneSafetyEnabled
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(0.14)
                                : Colors.transparent,
                            side: BorderSide(
                              color: widget.headphoneSafetyEnabled
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.6)
                                  : Colors.transparent,
                              width: 1,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          icon: const Icon(
                            Icons.headset_off_rounded,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SettingsItem(
                      label: 'Settings',
                      framed: true,
                      child: SizedBox(
                        width: 44,
                        height: 36,
                        child: IconButton(
                          tooltip: 'Settings',
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          onPressed: widget.onSettingsPressed,
                          icon: const Icon(Icons.settings_rounded, size: 20),
                        ),
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
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).textTheme.labelMedium?.color,
          ),
        ),
        const SizedBox(height: 3),
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
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
            child: child,
          )
        else
          child,
      ],
    );
  }
}

class _BpmStepButton extends StatelessWidget {
  const _BpmStepButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
      ),
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
      width: 58,
      child: DropdownButtonFormField<int>(
        isDense: true,
        initialValue: options.contains(value) ? value : options.first,
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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

// BPM stepper removed per UI update (manual input only)
