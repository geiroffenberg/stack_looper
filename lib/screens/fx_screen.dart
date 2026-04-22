import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/looper_provider.dart';

class FxScreen extends StatelessWidget {
  const FxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LooperProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Mixer & FX'),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: _HeaderActionButton(
                  label: 'Reset Perf',
                  onPressed: provider.resetPerformanceFx,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
                child: _HeaderActionButton(
                  label: 'Reset All',
                  onPressed: provider.resetAllFx,
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: SwitchListTile(
                  title: const Text('FX Enabled'),
                  subtitle: const Text('Bypass entire master chain quickly'),
                  value: provider.fxEnabled,
                  onChanged: (value) => unawaited(provider.setFxEnabled(value)),
                ),
              ),
              _Section(
                title: 'Send FX',
                children: [
                  _DivisionSelector(
                    label: 'Delay Time',
                    value: provider.fxDelayDivision,
                    onChanged: provider.setFxDelayDivision,
                  ),
                  _DelayFeelSelector(
                    value: provider.fxDelayFeel,
                    onChanged: provider.setFxDelayFeel,
                  ),
                  _PercentSlider(
                    label: 'Delay Send',
                    value: provider.fxDelaySend,
                    onChanged: provider.setFxDelaySend,
                  ),
                  _PercentSlider(
                    label: 'Reverb Send',
                    value: provider.fxReverbSend,
                    onChanged: provider.setFxReverbSend,
                  ),
                  _PercentSlider(
                    label: 'Reverb Room Size',
                    value: provider.fxReverbRoomSize,
                    onChanged: provider.setFxReverbRoomSize,
                  ),
                ],
              ),
              _Section(
                title: 'Performance FX',
                children: [
                  _SignedPercentSlider(
                    label: 'DJ Filter',
                    value: provider.fxDjFilterAmount,
                    onChanged: provider.setFxDjFilterAmount,
                  ),
                  _PercentSlider(
                    label: 'Filter Resonance',
                    value: provider.fxDjFilterResonance,
                    onChanged: provider.setFxDjFilterResonance,
                  ),
                  _PercentSlider(
                    label: 'Beat Repeat',
                    value: provider.fxBeatRepeatMix,
                    onChanged: provider.setFxBeatRepeatMix,
                  ),
                  _DivisionSelector(
                    label: 'Repeat Size',
                    value: provider.fxBeatRepeatDivision,
                    onChanged: provider.setFxBeatRepeatDivision,
                  ),
                  _PercentSlider(
                    label: 'Trans Gate',
                    value: provider.fxTransGateAmount,
                    onChanged: provider.setFxTransGateAmount,
                  ),
                  _DivisionSelector(
                    label: 'Gate Size',
                    value: provider.fxTransGateDivision,
                    onChanged: provider.setFxTransGateDivision,
                  ),
                  _PercentSlider(
                    label: 'Noise Riser',
                    value: provider.fxNoiseRiserAmount,
                    onChanged: provider.setFxNoiseRiserAmount,
                  ),
                  _PercentSlider(
                    label: 'Tape Stop',
                    value: provider.fxTapeStopAmount,
                    onChanged: provider.setFxTapeStopAmount,
                  ),
                  _PercentSlider(
                    label: 'Distortion',
                    value: provider.fxDistortionAmount,
                    onChanged: provider.setFxDistortionAmount,
                  ),
                ],
              ),
              _Section(
                title: 'Master FX',
                children: [
                  _HzSlider(
                    label: 'High-pass',
                    valueHz: provider.fxHighPassHz,
                    onChangedHz: (value) =>
                        unawaited(provider.setFxHighPassHz(value)),
                  ),
                  _HzSlider(
                    label: 'Low-pass',
                    valueHz: provider.fxLowPassHz,
                    onChangedHz: (value) =>
                        unawaited(provider.setFxLowPassHz(value)),
                  ),
                  _DbSlider(
                    label: 'EQ Low',
                    value: provider.fxEqLowDb,
                    min: -24,
                    max: 12,
                    onChanged: (value) =>
                        unawaited(provider.setFxEqLowDb(value)),
                  ),
                  _DbSlider(
                    label: 'EQ Mid',
                    value: provider.fxEqMidDb,
                    min: -24,
                    max: 12,
                    onChanged: (value) =>
                        unawaited(provider.setFxEqMidDb(value)),
                  ),
                  _DbSlider(
                    label: 'EQ High',
                    value: provider.fxEqHighDb,
                    min: -24,
                    max: 12,
                    onChanged: (value) =>
                        unawaited(provider.setFxEqHighDb(value)),
                  ),
                  _PercentSlider(
                    label: 'Compressor',
                    value: provider.fxCompressorAmount,
                    onChanged: provider.setFxCompressorAmount,
                  ),
                  _PercentSlider(
                    label: 'Saturation',
                    value: provider.fxSaturationAmount,
                    onChanged: provider.setFxSaturationAmount,
                  ),
                  _DbSlider(
                    label: 'Limiter Ceiling',
                    value: provider.fxLimiterCeilingDb,
                    min: -24,
                    max: -0.1,
                    onChanged: (value) =>
                        unawaited(provider.setFxLimiterCeilingDb(value)),
                  ),
                ],
              ),
              _Section(
                title: 'Track Mixer',
                children: [
                  SizedBox(
                    height: 220,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List<Widget>.generate(
                        provider.fxTrackOutputDb.length,
                        (index) => Expanded(
                          child: _VerticalTrackGainStrip(
                            label: 'T${index + 1}',
                            valueDb: provider.fxTrackOutputDb[index],
                            onChanged: (value) => unawaited(
                              provider.setTrackOutputGainDb(index, value),
                            ),
                            onReset: () =>
                                unawaited(provider.setTrackOutputGainDb(index, 0.0)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              _Section(
                title: 'Master Output',
                children: [
                  _MasterVolumeSlider(
                    label: 'Master Volume',
                    value: provider.fxMasterOutputDb,
                    min: -24,
                    max: 12,
                    onChanged: (value) =>
                        unawaited(provider.setFxMasterOutputDb(value)),
                    onReset: () => unawaited(provider.setFxMasterOutputDb(0.0)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final Color border = Theme.of(context).colorScheme.primary.withOpacity(0.9);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: BorderSide(color: border, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label),
    );
  }
}

class _PercentSlider extends StatelessWidget {
  const _PercentSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final int pct = (value * 100).round();
    return _SliderRow(
      label: label,
      valueText: '$pct%',
      child: Slider(
        value: value,
        min: 0,
        max: 1,
        onChanged: onChanged,
      ),
    );
  }
}

class _DbSlider extends StatelessWidget {
  const _DbSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SliderRow(
      label: label,
      valueText: '${value.toStringAsFixed(1)} dB',
      child: Slider(
        value: value,
        min: min,
        max: max,
        onChanged: onChanged,
      ),
    );
  }
}

class _HzSlider extends StatelessWidget {
  const _HzSlider({
    required this.label,
    required this.valueHz,
    required this.onChangedHz,
  });

  final String label;
  final double valueHz;
  final ValueChanged<double> onChangedHz;

  static const double _minHz = 20.0;
  static const double _maxHz = 20000.0;

  @override
  Widget build(BuildContext context) {
    final double sliderValue = _toLogNorm(valueHz);
    return _SliderRow(
      label: label,
      valueText: '${valueHz.toStringAsFixed(valueHz >= 1000 ? 0 : 1)} Hz',
      child: Slider(
        value: sliderValue,
        min: 0,
        max: 1,
        onChanged: (v) => onChangedHz(_fromLogNorm(v)),
      ),
    );
  }

  double _toLogNorm(double hz) {
    final double clamped = hz.clamp(_minHz, _maxHz);
    final double logMin = math.log(_minHz);
    final double logMax = math.log(_maxHz);
    return (math.log(clamped) - logMin) / (logMax - logMin);
  }

  double _fromLogNorm(double t) {
    final double logMin = math.log(_minHz);
    final double logMax = math.log(_maxHz);
    return math.exp(logMin + (logMax - logMin) * t).clamp(_minHz, _maxHz);
  }
}

class _SignedPercentSlider extends StatelessWidget {
  const _SignedPercentSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    String valueText;
    if (value.abs() < 0.01) {
      valueText = 'Center';
    } else if (value < 0) {
      valueText = 'LP ${(value.abs() * 100).round()}%';
    } else {
      valueText = 'HP ${(value.abs() * 100).round()}%';
    }
    return _SliderRow(
      label: label,
      valueText: valueText,
      child: Slider(
        value: value,
        min: -1,
        max: 1,
        onChanged: onChanged,
      ),
    );
  }
}

class _DivisionSelector extends StatelessWidget {
  const _DivisionSelector({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  static const List<int> _divisions = <int>[2, 4, 8, 16];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _divisions
                .map(
                  (division) => ChoiceChip(
                    label: Text('1/$division'),
                    selected: value == division,
                    onSelected: (_) => onChanged(division),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _DelayFeelSelector extends StatelessWidget {
  const _DelayFeelSelector({
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  static const List<(int, String)> _modes = <(int, String)>[
    (0, 'Straight'),
    (1, 'Dot'),
    (2, 'Triplet'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Delay Feel'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _modes
                .map(
                  (mode) => ChoiceChip(
                    label: Text(mode.$2),
                    selected: value == mode.$1,
                    onSelected: (_) => onChanged(mode.$1),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueText,
    required this.child,
  });

  final String label;
  final String valueText;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label),
              const Spacer(),
              Text(
                valueText,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
          child,
        ],
      ),
    );
  }
}

class _MasterVolumeSlider extends StatelessWidget {
  const _MasterVolumeSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onReset,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final bool nearUnity = (value - 0.0).abs() <= 0.2;
    return GestureDetector(
      onDoubleTap: onReset,
      child: _SliderRow(
        label: label,
        valueText: '${value.toStringAsFixed(1)} dB',
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double zeroNorm = ((0.0 - min) / (max - min)).clamp(0.0, 1.0);
            final double zeroLeft = constraints.maxWidth * zeroNorm;
            return SizedBox(
              height: 32,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: Slider(
                      value: value,
                      min: min,
                      max: max,
                      onChanged: onChanged,
                    ),
                  ),
                  Positioned(
                    left: zeroLeft,
                    top: 3,
                    bottom: 3,
                    child: IgnorePointer(
                      child: Container(
                        width: 1.4,
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(nearUnity ? 0.95 : 0.55),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _VerticalTrackGainStrip extends StatelessWidget {
  const _VerticalTrackGainStrip({
    required this.label,
    required this.valueDb,
    required this.onChanged,
    required this.onReset,
  });

  final String label;
  final double valueDb;
  final ValueChanged<double> onChanged;
  final VoidCallback onReset;

  static const double _minDb = -60;
  static const double _maxDb = 12;

  @override
  Widget build(BuildContext context) {
    final bool nearUnity = (valueDb - 0.0).abs() <= 0.2;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onDoubleTap: onReset,
        child: Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double zeroNorm = (0.0 - _minDb) / (_maxDb - _minDb);
                  final double zeroTop =
                      constraints.maxHeight * (1.0 - zeroNorm.clamp(0.0, 1.0));
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Slider(
                            value: valueDb,
                            min: _minDb,
                            max: _maxDb,
                            onChanged: onChanged,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        right: 8,
                        top: zeroTop,
                        child: IgnorePointer(
                          child: Container(
                            height: 1.2,
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(nearUnity ? 0.95 : 0.55),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Text(
              '${valueDb.toStringAsFixed(1)} dB',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            Text(
              '0 dB',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).dividerColor,
                    fontSize: 10,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
