import 'dart:math' as math;

import 'package:flutter/rendering.dart';

/// Paints waveform bars; bars whose centre lies inside the selected window
/// (`windowStart`–`windowEnd`, fractions of the width) use `activeColor`.
class MusicWaveformPainter extends CustomPainter {
  /// Creates the painter.
  const MusicWaveformPainter({
    required this.peaks,
    required this.windowStart,
    required this.windowEnd,
    required this.activeColor,
    required this.inactiveColor,
    this.barWidth = 3,
    this.gap = 2,
  });

  /// Peak levels 0–1, evenly spread over the track. Empty draws even bars.
  final List<double> peaks;

  /// Start of the window, 0–1.
  final double windowStart;

  /// End of the window, 0–1.
  final double windowEnd;

  /// Colour of the bars inside the window.
  final Color activeColor;

  /// Colour of the other bars.
  final Color inactiveColor;

  /// Width of one bar.
  final double barWidth;

  /// Space between bars.
  final double gap;

  static const double _emptyLevel = 0.3;
  static const double _minLevel = 0.08;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final count = math.max(1, ((size.width + gap) / (barWidth + gap)).floor());
    final step = size.width / count;
    final active = Paint()..color = activeColor;
    final inactive = Paint()..color = inactiveColor;
    final radius = Radius.circular(barWidth / 2);
    for (var i = 0; i < count; i++) {
      final level = math.max(_minLevel, _levelAt(i, count));
      final height = level * size.height;
      final centreX = step * (i + 0.5);
      final fraction = centreX / size.width;
      final rect = Rect.fromCenter(
        center: Offset(centreX, size.height / 2),
        width: math.min(barWidth, step),
        height: height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, radius),
        fraction >= windowStart && fraction <= windowEnd ? active : inactive,
      );
    }
  }

  /// The largest peak in the slice of [peaks] under bar [index] of [count].
  double _levelAt(int index, int count) {
    if (peaks.isEmpty) {
      return _emptyLevel;
    }
    final from = (index * peaks.length / count).floor();
    final to = math.max(from + 1, ((index + 1) * peaks.length / count).ceil());
    var level = 0.0;
    for (var i = from; i < to && i < peaks.length; i++) {
      level = math.max(level, peaks[i]);
    }
    return level.clamp(0, 1);
  }

  @override
  bool shouldRepaint(MusicWaveformPainter oldDelegate) =>
      !identical(peaks, oldDelegate.peaks) ||
      windowStart != oldDelegate.windowStart ||
      windowEnd != oldDelegate.windowEnd ||
      activeColor != oldDelegate.activeColor ||
      inactiveColor != oldDelegate.inactiveColor ||
      barWidth != oldDelegate.barWidth ||
      gap != oldDelegate.gap;
}
