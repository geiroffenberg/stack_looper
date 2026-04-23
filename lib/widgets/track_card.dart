import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/track.dart';

class TrackCard extends StatelessWidget {
  const TrackCard({
    super.key,
    required this.track,
    required this.isSelected,
    required this.visualBarDividers,
    required this.playheadProgress,
    required this.isArmed,
    required this.armedBlinkOn,
    required this.onDelete,
    required this.onToggleDelaySend,
    required this.onToggleReverbSend,
    required this.onDelaySendLevelChanged,
    required this.onReverbSendLevelChanged,
    required this.onToggleMute,
    required this.onBarLengthChanged,
  });

  final Track track;
  final bool isSelected;
  final int visualBarDividers;
  final double playheadProgress;
  final bool isArmed;
  final bool armedBlinkOn;
  final VoidCallback onDelete;
  final VoidCallback onToggleDelaySend;
  final VoidCallback onToggleReverbSend;
  final ValueChanged<double> onDelaySendLevelChanged;
  final ValueChanged<double> onReverbSendLevelChanged;
  final VoidCallback onToggleMute;
  final ValueChanged<int> onBarLengthChanged;

  @override
  Widget build(BuildContext context) {
    final Color selectedBorderColor = const Color(0xFF7DD3FC);
    final borderColor = isSelected
        ? selectedBorderColor
        : Theme.of(context).dividerColor.withOpacity(0.72);

    return GestureDetector(
      onLongPress: onDelete,
      child: Container(
        height: 92,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1.5),
          color: Theme.of(context).cardTheme.color,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: selectedBorderColor.withOpacity(0.18),
                    blurRadius: 14,
                    spreadRadius: 0.5,
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 72,
                  child: DropdownButtonFormField<int>(
                    isDense: true,
                    initialValue: track.barLength,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                    ),
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
                const Spacer(),
                _TrackHeaderToggle(
                  tooltip: 'Delay send',
                  label: 'DLY',
                  isActive: track.delaySendEnabled,
                  level: track.delaySendLevel,
                  onPressed: onToggleDelaySend,
                  onLongPress: () => _showDualSendLevelSheet(
                    context,
                    delayValue: track.delaySendLevel,
                    reverbValue: track.reverbSendLevel,
                    onDelayChanged: onDelaySendLevelChanged,
                    onReverbChanged: onReverbSendLevelChanged,
                  ),
                ),
                _TrackHeaderToggle(
                  tooltip: 'Reverb send',
                  label: 'REV',
                  isActive: track.reverbSendEnabled,
                  level: track.reverbSendLevel,
                  onPressed: onToggleReverbSend,
                  onLongPress: () => _showDualSendLevelSheet(
                    context,
                    delayValue: track.delaySendLevel,
                    reverbValue: track.reverbSendLevel,
                    onDelayChanged: onDelaySendLevelChanged,
                    onReverbChanged: onReverbSendLevelChanged,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: track.canMute ? onToggleMute : null,
                  icon: Icon(
                    track.isMuted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CustomPaint(
                  painter: _WaveformPainter(
                    hasAudio: track.hasAudio,
                    isRecording: track.state == TrackState.recording,
                    isArmed: isArmed,
                    armedBlinkOn: armedBlinkOn,
                    waveformPeaks: track.waveformPeaks,
                    visualBarDividers: visualBarDividers,
                    trackBarLength: track.barLength,
                    playheadProgress: playheadProgress,
                    playheadColor: Theme.of(context).colorScheme.secondary,
                    dividerColor: Theme.of(context).dividerColor,
                    waveformColor: Theme.of(context).colorScheme.primary,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDualSendLevelSheet(
    BuildContext context, {
    required double delayValue,
    required double reverbValue,
    required ValueChanged<double> onDelayChanged,
    required ValueChanged<double> onReverbChanged,
  }) async {
    double delay = delayValue.clamp(0.0, 1.0);
    double reverb = reverbValue.clamp(0.0, 1.0);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final int delayPct = (delay * 100).round();
            final int reverbPct = (reverb * 100).round();
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Track Send Levels',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _SendLevelRow(
                    label: 'Delay',
                    value: delay,
                    percentLabel: '$delayPct%',
                    onChanged: (v) {
                      setState(() => delay = v);
                      onDelayChanged(v);
                    },
                  ),
                  const SizedBox(height: 8),
                  _SendLevelRow(
                    label: 'Reverb',
                    value: reverb,
                    percentLabel: '$reverbPct%',
                    onChanged: (v) {
                      setState(() => reverb = v);
                      onReverbChanged(v);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SendLevelRow extends StatelessWidget {
  const _SendLevelRow({
    required this.label,
    required this.value,
    required this.percentLabel,
    required this.onChanged,
  });

  final String label;
  final double value;
  final String percentLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        Row(
          children: [
            Expanded(
              child: Slider(value: value, min: 0, max: 1, onChanged: onChanged),
            ),
            SizedBox(
              width: 52,
              child: Text(
                percentLabel,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TrackHeaderToggle extends StatelessWidget {
  const _TrackHeaderToggle({
    required this.tooltip,
    required this.label,
    required this.isActive,
    required this.level,
    required this.onPressed,
    required this.onLongPress,
  });

  final String tooltip;
  final String label;
  final bool isActive;
  final double level;
  final VoidCallback onPressed;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final Color activeColor = Theme.of(context).colorScheme.primary;
    final Color inactiveColor = Theme.of(
      context,
    ).dividerColor.withOpacity(0.75);
    final double clampedLevel = level.clamp(0.0, 1.0);
    final double activeFill = 0.12 + (0.28 * clampedLevel);
    final double activeBorder = 0.55 + (0.4 * clampedLevel);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: '$tooltip (tap to toggle, hold for both levels)',
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isActive
                    ? activeColor.withOpacity(activeBorder)
                    : inactiveColor,
                width: 1,
              ),
              color: isActive
                  ? activeColor.withOpacity(activeFill)
                  : Colors.transparent,
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: isActive
                    ? activeColor
                    : Theme.of(
                        context,
                      ).textTheme.labelSmall?.color?.withOpacity(0.72),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.hasAudio,
    required this.isRecording,
    required this.isArmed,
    required this.armedBlinkOn,
    required this.waveformPeaks,
    required this.visualBarDividers,
    required this.trackBarLength,
    required this.playheadProgress,
    required this.playheadColor,
    required this.dividerColor,
    required this.waveformColor,
  });

  final bool hasAudio;
  final bool isRecording;
  final bool isArmed;
  final bool armedBlinkOn;
  final List<double> waveformPeaks;
  final int visualBarDividers;
  final int trackBarLength;
  final double playheadProgress;
  final Color playheadColor;
  final Color dividerColor;
  final Color waveformColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint bgPaint = Paint()
      ..color = const Color(0xFF0D1420).withOpacity(0.55);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final double laneWidth =
        size.width *
        (trackBarLength / math.max(1, visualBarDividers)).clamp(0.0, 1.0);

    final Paint dividerPaint = Paint()
      ..color = dividerColor.withOpacity(0.72)
      ..strokeWidth = 1;
    for (int i = 1; i < visualBarDividers; i++) {
      final x = (size.width / visualBarDividers) * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), dividerPaint);
    }

    if (hasAudio && waveformPeaks.isNotEmpty) {
      final Paint waveformPaint = Paint()
        ..color = waveformColor.withOpacity(0.78)
        ..strokeCap = StrokeCap.round;
      final int count = waveformPeaks.length;
      final double gap = 1.0;
      final double barWidth = math.max(
        1.2,
        (laneWidth - ((count - 1) * gap)) / count,
      );
      for (int i = 0; i < count; i++) {
        final double peak = waveformPeaks[i].clamp(0.0, 1.0);
        final double height = size.height * (0.12 + (peak * 0.76));
        final double top = (size.height - height) * 0.5;
        final double x = i * (barWidth + gap) + (barWidth * 0.5);
        waveformPaint.strokeWidth = barWidth;
        canvas.drawLine(Offset(x, top), Offset(x, top + height), waveformPaint);
      }
    }

    if (isRecording) {
      final int desiredBars = math.max(16, trackBarLength * 32);
      final int barCount = math.min(
        desiredBars,
        math.max(16, (laneWidth / 3).floor()),
      );
      final double gap = 1.5;
      final double barWidth = math.max(
        1.5,
        (laneWidth - ((barCount - 1) * gap)) / barCount,
      );
      final double progressX =
          size.width * playheadProgress.clamp(0.0, 1.0).toDouble();
      final Paint recordedBarPaint = Paint()
        ..color = const Color(0xFFE53935).withOpacity(0.28)
        ..strokeCap = StrokeCap.round;
      final Paint pendingBarPaint = Paint()
        ..color = const Color(0xFFE53935).withOpacity(0.12)
        ..strokeCap = StrokeCap.round;

      for (int i = 0; i < barCount; i++) {
        final double x = i * (barWidth + gap) + (barWidth * 0.5);
        final double phase = (i / math.max(1, barCount - 1)) * math.pi * 6.0;
        final double envelope = 0.35 + 0.65 * ((math.sin(phase) + 1.0) * 0.5);
        final double detail =
            0.2 + 0.8 * ((math.sin((phase * 1.9) + 0.7) + 1.0) * 0.5);
        final double height = size.height * (0.16 + (0.56 * envelope * detail));
        final double top = (size.height - height) * 0.5;
        final Paint paint = x <= progressX ? recordedBarPaint : pendingBarPaint;
        paint.strokeWidth = barWidth;
        canvas.drawLine(Offset(x, top), Offset(x, top + height), paint);
      }
    }

    final Paint playheadPaint = Paint()
      ..color = (isRecording || isArmed)
          ? const Color(0xFFE53935)
          : playheadColor
      ..strokeWidth = 2;
    final double clampedProgress = playheadProgress.clamp(0.0, 1.0).toDouble();
    final double playheadX = size.width * clampedProgress;

    // Only draw playhead if track has audio or is currently recording
    if (isArmed) {
      if (armedBlinkOn) {
        canvas.drawLine(Offset(0, 0), Offset(0, size.height), playheadPaint);
      }
    } else if (hasAudio || isRecording) {
      canvas.drawLine(
        Offset(playheadX, 0),
        Offset(playheadX, size.height),
        playheadPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.hasAudio != hasAudio ||
        oldDelegate.isRecording != isRecording ||
        oldDelegate.isArmed != isArmed ||
        oldDelegate.armedBlinkOn != armedBlinkOn ||
        oldDelegate.waveformPeaks != waveformPeaks ||
        oldDelegate.visualBarDividers != visualBarDividers ||
        oldDelegate.trackBarLength != trackBarLength ||
        oldDelegate.playheadProgress != playheadProgress ||
        oldDelegate.playheadColor != playheadColor ||
        oldDelegate.dividerColor != dividerColor ||
        oldDelegate.waveformColor != waveformColor;
  }
}
