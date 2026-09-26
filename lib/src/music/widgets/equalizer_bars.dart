import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The design's three-bar equaliser shown before the title of the selected
/// track: bars 1 px wide, 12 / 12 / 6 px high, 2 px apart, vertically
/// centred.
///
/// The bars bounce while [animating], unless the platform asks to reduce
/// motion; otherwise they rest at the design's heights.
class EqualizerBars extends StatefulWidget {
  /// Creates the bars.
  const EqualizerBars({required this.color, this.animating = false, super.key});

  /// Bar colour.
  final Color color;

  /// Whether the bars bounce.
  final bool animating;

  /// Width of the three bars with their gaps.
  static const double width = barWidth * 3 + gap * 2;

  /// Height of the tallest bar.
  static const double height = 12;

  /// Width of one bar.
  static const double barWidth = 1;

  /// Space between bars.
  static const double gap = 2;

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SingleTickerProviderStateMixin {
  static const Duration _period = Duration(milliseconds: 900);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _period,
  );

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(EqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate = widget.animating && !_reduceMotion;
    if (animate && !_controller.isAnimating) {
      unawaited(_controller.repeat());
    } else if (!animate &&
        (_controller.isAnimating || _controller.value != 0)) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: EqualizerBars.width,
      height: EqualizerBars.height,
      child: CustomPaint(
        painter: EqualizerBarsPainter(
          animation: _controller,
          color: widget.color,
          animating: widget.animating && !_reduceMotion,
        ),
      ),
    ),
  );
}

/// Paints [EqualizerBars].
class EqualizerBarsPainter extends CustomPainter {
  /// Creates the painter.
  EqualizerBarsPainter({
    required this.animation,
    required this.color,
    required this.animating,
  }) : super(repaint: animation);

  /// Drives the bounce, 0–1 per period.
  final Animation<double> animation;

  /// Bar colour.
  final Color color;

  /// Whether heights follow [animation]; otherwise the design's heights.
  final bool animating;

  static const List<double> _restHeights = [12, 12, 6];
  static const List<double> _phases = [0, 0.35, 0.7];
  static const double _minHeight = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var i = 0; i < _restHeights.length; i++) {
      final double height;
      if (animating) {
        final t = (animation.value + _phases[i]) * 2 * math.pi;
        height =
            _minHeight + (size.height - _minHeight) * (0.5 + 0.5 * math.sin(t));
      } else {
        height = _restHeights[i];
      }
      final left = i * (EqualizerBars.barWidth + EqualizerBars.gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            left,
            (size.height - height) / 2,
            EqualizerBars.barWidth,
            height,
          ),
          const Radius.circular(16),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(EqualizerBarsPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.animation != animation ||
      oldDelegate.animating != animating;
}
