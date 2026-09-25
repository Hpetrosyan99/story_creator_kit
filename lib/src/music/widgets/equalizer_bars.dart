import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Three small bouncing bars shown next to the title of the previewing track.
///
/// Static when the platform asks to reduce motion.
class EqualizerBars extends StatefulWidget {
  /// Creates the bars.
  const EqualizerBars({required this.color, this.size = 14, super.key});

  /// Bar colour.
  final Color color;

  /// Width and height.
  final double size;

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 0.25;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _BarsPainter(animation: _controller, color: widget.color),
      ),
    ),
  );
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.animation, required this.color})
    : super(repaint: animation);

  final Animation<double> animation;
  final Color color;

  static const List<double> _phases = [0, 0.35, 0.7];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final barWidth = size.width / 5;
    for (var i = 0; i < _phases.length; i++) {
      final t = (animation.value + _phases[i]) * 2 * math.pi;
      final level = 0.3 + 0.7 * (0.5 + 0.5 * math.sin(t));
      final height = size.height * level;
      final left = barWidth * (i * 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - height, barWidth, height),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.animation != animation;
}
