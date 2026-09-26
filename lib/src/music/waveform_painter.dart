import 'dart:math' as math;

import 'package:flutter/rendering.dart';

/// Paints the segment selector's waveform: bars alternating 3 px and 2 px
/// wide, 5 px apart, 5–27 px high from the peaks, fully rounded.
///
/// The bars are laid out along the whole track, [trackWidth] pixels long and
/// starting at [originX] (usually negative once the start is moved), so they
/// scroll with the selection; only the bars inside the canvas are drawn.
class MusicWaveformPainter extends CustomPainter {
  /// Creates the painter.
  const MusicWaveformPainter({
    required this.peaks,
    required this.originX,
    required this.trackWidth,
    required this.color,
  });

  /// Peak levels 0–1, evenly spread over the track. Empty draws even bars.
  final List<double> peaks;

  /// Horizontal position of the start of the track.
  final double originX;

  /// Width of the whole track on the strip.
  final double trackWidth;

  /// Bar colour.
  final Color color;

  /// Width of the even bars.
  static const double wideBar = 3;

  /// Width of the odd bars.
  static const double narrowBar = 2;

  /// Space between bars.
  static const double gap = 5;

  /// Height of the quietest bar.
  static const double minBarHeight = 5;

  /// Height of the loudest bar.
  static const double maxBarHeight = 27;

  /// Distance from one wide bar to the next.
  static const double pairPitch = wideBar + gap + narrowBar + gap;

  static const double _emptyLevel = 0.3;

  /// Left edge of bar [index], relative to the start of the track.
  static double barLeft(int index) =>
      (index ~/ 2) * pairPitch + (index.isOdd ? wideBar + gap : 0);

  /// Number of bars on a track [trackWidth] pixels long.
  static int barCount(double trackWidth) {
    if (trackWidth <= 0) {
      return 0;
    }
    var count = (trackWidth / pairPitch).floor() * 2;
    while (barLeft(count) + _widthOf(count) <= trackWidth) {
      count++;
    }
    return count;
  }

  static double _widthOf(int index) => index.isEven ? wideBar : narrowBar;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || trackWidth <= 0) {
      return;
    }
    final count = barCount(trackWidth);
    if (count == 0) {
      return;
    }
    // Only the bars that fall inside the strip.
    final first = math.max(0, ((-originX) / pairPitch).floor() * 2 - 2);
    final paint = Paint()..color = color;
    const radius = Radius.circular(40);
    final centreY = size.height / 2;
    for (var i = first; i < count; i++) {
      final left = originX + barLeft(i);
      if (left > size.width) {
        break;
      }
      final width = _widthOf(i);
      if (left + width < 0) {
        continue;
      }
      final level = _levelAt(i, count);
      final height = minBarHeight + (maxBarHeight - minBarHeight) * level;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, centreY - height / 2, width, height),
          radius,
        ),
        paint,
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
      originX != oldDelegate.originX ||
      trackWidth != oldDelegate.trackWidth ||
      color != oldDelegate.color;
}
