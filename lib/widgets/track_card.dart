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
    required this.onSelect,
    required this.onDelete,
    required this.onToggleMute,
    required this.onBarLengthChanged,
  });

  final Track track;
  final bool isSelected;
  final int visualBarDividers;
  final double playheadProgress;
  final VoidCallback onSelect;
  final VoidCallback onDelete;
  final VoidCallback onToggleMute;
  final ValueChanged<int> onBarLengthChanged;

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).dividerColor.withOpacity(0.3);

    return GestureDetector(
      onTap: onSelect,
      onLongPress: onDelete,
      child: Container(
        height: 92,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.5),
          color: Theme.of(context).cardTheme.color,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  child: Text(
                    '${track.id + 1}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 56,
                  child: DropdownButtonFormField<int>(
                    isDense: true,
                    value: track.barLength,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: track.canMute ? onToggleMute : null,
                  icon: Icon(
                    track.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
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
}

class _WaveformPainter extends CustomPainter {
  // Two layered sine curves keep the placeholder waveform simple but organic.
  static const double _primaryFrequency = 2.2; // Cycles per repeated segment.
  static const double _primaryPhaseStep = 0.6; // Per-segment offset for variation.
  static const double _secondaryFrequency = 5.0; // Higher detail cycles per segment.
  static const double _secondaryPhaseStep = 0.4; // Secondary per-segment phase shift.
  // Combined amplitudes define waveform height/energy in the track area.
  static const double _primaryAmplitude = 0.5;
  static const double _secondaryAmplitude = 0.25;
  static const double _verticalScale = 0.32;

  const _WaveformPainter({
    required this.hasAudio,
    required this.visualBarDividers,
    required this.trackBarLength,
    required this.playheadProgress,
    required this.playheadColor,
    required this.dividerColor,
    required this.waveformColor,
  });

  final bool hasAudio;
  final int visualBarDividers;
  final int trackBarLength;
  final double playheadProgress;
  final Color playheadColor;
  final Color dividerColor;
  final Color waveformColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint bgPaint = Paint()..color = Colors.white.withOpacity(0.02);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final Paint dividerPaint = Paint()
      ..color = dividerColor.withOpacity(0.5)
      ..strokeWidth = 1;
    for (int i = 1; i < visualBarDividers; i++) {
      final x = (size.width / visualBarDividers) * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), dividerPaint);
    }

    if (hasAudio) {
      final Paint waveformPaint = Paint()
        ..color = waveformColor.withOpacity(0.75)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      final int repeats = math.max(1, visualBarDividers ~/ trackBarLength);
      final double segmentWidth = size.width / repeats;
      final int points = math.max(18, (segmentWidth / 5).floor());

      for (int repeat = 0; repeat < repeats; repeat++) {
        final Path path = Path();
        for (int i = 0; i <= points; i++) {
          final double t = i / points;
          final double x = repeat * segmentWidth + t * segmentWidth;
          final double wave =
              math.sin((t * 2 * math.pi * _primaryFrequency) +
                      (repeat * _primaryPhaseStep)) *
                  _primaryAmplitude +
                  math.sin((t * 2 * math.pi * _secondaryFrequency) +
                      (repeat * _secondaryPhaseStep)) *
                  _secondaryAmplitude;
          final double y = (size.height * 0.5) - (wave * size.height * _verticalScale);
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        canvas.drawPath(path, waveformPaint);
      }
    }

    final Paint playheadPaint = Paint()
      ..color = playheadColor
      ..strokeWidth = 2;
    final double clampedProgress = playheadProgress.clamp(0.0, 1.0).toDouble();
    final double playheadX = size.width * clampedProgress;
    canvas.drawLine(Offset(playheadX, 0), Offset(playheadX, size.height), playheadPaint);
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.hasAudio != hasAudio ||
        oldDelegate.visualBarDividers != visualBarDividers ||
        oldDelegate.trackBarLength != trackBarLength ||
        oldDelegate.playheadProgress != playheadProgress ||
        oldDelegate.playheadColor != playheadColor ||
        oldDelegate.dividerColor != dividerColor ||
        oldDelegate.waveformColor != waveformColor;
  }
}
