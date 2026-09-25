import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A circular progress ring with the percentage in the middle.
class ExportProgressRing extends StatelessWidget {
  /// Creates the ring.
  const ExportProgressRing({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.textStyle,
    required this.semanticsLabel,
    this.size = 112,
    this.strokeWidth = 6,
    super.key,
  });

  /// Progress 0–1.
  final ValueListenable<double> progress;

  /// Arc colour.
  final Color color;

  /// Background track colour.
  final Color trackColor;

  /// Style of the percentage.
  final TextStyle textStyle;

  /// Semantics label; the value is the percentage.
  final String semanticsLabel;

  /// Diameter.
  final double size;

  /// Ring thickness.
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: progress,
    builder: (context, value, _) {
      final percent = (value * 100).clamp(0, 100).floor();
      return Semantics(
        label: semanticsLabel,
        value: '$percent%',
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _RingPainter(
              value: value,
              color: color,
              trackColor: trackColor,
              strokeWidth: strokeWidth,
            ),
            child: Center(
              child: ExcludeSemantics(
                child: Text('$percent%', style: textStyle),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double value;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = trackColor;
    canvas.drawArc(rect, 0, 2 * math.pi, false, track);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * value.clamp(0, 1),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}
