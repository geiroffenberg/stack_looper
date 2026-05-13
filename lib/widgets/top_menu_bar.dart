import 'package:flutter/material.dart';

import '../models/looper_state.dart';

class TopMenuBar extends StatelessWidget {
  const TopMenuBar({
    super.key,
    required this.transportState,
    required this.onPlay,
    required this.onRecord,
    required this.onMergePressed,
    required this.onToggleHeadphoneBleed,
    required this.headphoneSafetyEnabled,
    required this.onClearAll,
    required this.onFxPressed,
    required this.canRecord,
    required this.beatFlash,
    required this.recordArmed,
    required this.armedBlinkOn,
  });

  final TransportState transportState;
  final VoidCallback onPlay;
  final VoidCallback onRecord;
  final VoidCallback onMergePressed;
  final VoidCallback onToggleHeadphoneBleed;
  final bool headphoneSafetyEnabled;
  final VoidCallback onClearAll;
  final VoidCallback onFxPressed;
  final bool canRecord;
  final bool beatFlash;
  final bool recordArmed;
  final bool armedBlinkOn;

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
            flex: 7,
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TransportButton(
                      customIcon: const _MergeRightIcon(),
                      isActive: false,
                      activeColor: Theme.of(context).colorScheme.primary,
                      enabled: true,
                      onPressed: onMergePressed,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 5,
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
    required this.isActive,
    required this.activeColor,
    required this.enabled,
    required this.onPressed,
    this.icon,
    this.customIcon,
    this.flashActive = false,
  }) : assert(icon != null || customIcon != null);

  final IconData? icon;
  final Widget? customIcon;
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
      icon: customIcon ?? Icon(icon, color: isActive ? activeColor : null),
    );
  }
}

class _MergeRightIcon extends StatelessWidget {
  const _MergeRightIcon();

  @override
  Widget build(BuildContext context) {
    final Color color = Theme.of(context).iconTheme.color ?? Colors.white;
    return CustomPaint(
      size: const Size(22, 22),
      painter: _MergeRightIconPainter(color: color),
    );
  }
}

class _MergeRightIconPainter extends CustomPainter {
  const _MergeRightIconPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path path = Path()
      ..moveTo(size.width * 0.14, size.height * 0.26)
      ..lineTo(size.width * 0.38, size.height * 0.26)
      ..quadraticBezierTo(
        size.width * 0.52,
        size.height * 0.26,
        size.width * 0.62,
        size.height * 0.50,
      )
      ..moveTo(size.width * 0.14, size.height * 0.74)
      ..lineTo(size.width * 0.38, size.height * 0.74)
      ..quadraticBezierTo(
        size.width * 0.52,
        size.height * 0.74,
        size.width * 0.62,
        size.height * 0.50,
      )
      ..moveTo(size.width * 0.62, size.height * 0.50)
      ..lineTo(size.width * 0.82, size.height * 0.50)
      ..moveTo(size.width * 0.72, size.height * 0.40)
      ..lineTo(size.width * 0.82, size.height * 0.50)
      ..lineTo(size.width * 0.72, size.height * 0.60);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MergeRightIconPainter oldDelegate) {
    return oldDelegate.color != color;
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
