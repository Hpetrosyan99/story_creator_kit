import 'package:flutter/widgets.dart';

import '../../core/story_scope.dart';
import 'canvas_interaction.dart';

/// Centre lines shown while a dragged overlay is snapped. Chrome only.
class SnapGuides extends StatelessWidget {
  /// Creates the guides.
  const SnapGuides({required this.interaction, super.key});

  /// Drag state.
  final CanvasInteraction interaction;

  @override
  Widget build(BuildContext context) {
    final color = StoryScope.of(context).theme.accent;
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: interaction,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _GuidesPainter(
            vertical: interaction.dragging && interaction.snapVertical,
            horizontal: interaction.dragging && interaction.snapHorizontal,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _GuidesPainter extends CustomPainter {
  const _GuidesPainter({
    required this.vertical,
    required this.horizontal,
    required this.color,
  });

  final bool vertical;
  final bool horizontal;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    if (vertical) {
      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        paint,
      );
    }
    if (horizontal) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GuidesPainter oldDelegate) =>
      oldDelegate.vertical != vertical ||
      oldDelegate.horizontal != horizontal ||
      oldDelegate.color != color;
}
