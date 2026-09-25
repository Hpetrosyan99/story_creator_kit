import 'dart:ui';

import 'package:perfect_freehand/perfect_freehand.dart' as pf;

import '../../model/drawing_stroke.dart';

/// Turns [DrawingStroke]s into filled outlines (via `perfect_freehand`) and
/// paints them. Geometry is in canvas units and cached per stroke instance.
abstract final class StrokeRenderer {
  static final Expando<Path> _outlines = Expando('storyStrokeOutline');
  static final Expando<Path> _cores = Expando('storyStrokeCore');

  /// Alpha multiplier of the marker.
  static const double markerAlpha = 0.55;

  /// Marker width relative to the brush size.
  static const double markerWidthFactor = 1.6;

  /// Neon core width relative to the brush size.
  static const double neonCoreFactor = 0.42;

  /// Neon glow blur sigma relative to the brush size.
  static const double neonGlowFactor = 0.55;

  /// Paints [stroke]. Eraser strokes clear pixels, so callers draw strokes
  /// inside their own layer (see `StoryEditsPainter.paintStrokes`).
  static void paintStroke(Canvas canvas, DrawingStroke stroke) {
    if (stroke.points.isEmpty) {
      return;
    }
    final outline = outlineOf(stroke);
    switch (stroke.tool) {
      case StrokeTool.pen:
        canvas.drawPath(outline, Paint()..color = stroke.color);
      case StrokeTool.marker:
        canvas.drawPath(
          outline,
          Paint()
            ..color = stroke.color.withValues(
              alpha: stroke.color.a * markerAlpha,
            ),
        );
      case StrokeTool.neon:
        canvas
          ..drawPath(
            outline,
            Paint()
              ..color = stroke.color
              ..maskFilter = MaskFilter.blur(
                BlurStyle.normal,
                stroke.size * neonGlowFactor,
              ),
          )
          ..drawPath(outline, Paint()..color = stroke.color)
          ..drawPath(
            _coreOf(stroke),
            Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.9),
          );
      case StrokeTool.eraser:
        canvas.drawPath(outline, Paint()..blendMode = BlendMode.clear);
    }
  }

  /// Outline of [stroke] in canvas units (cached).
  static Path outlineOf(DrawingStroke stroke) =>
      _outlines[stroke] ??= _buildPath(stroke, _widthOf(stroke));

  /// Bounds of [stroke]'s outline, including the neon glow.
  static Rect boundsOf(DrawingStroke stroke) {
    final bounds = outlineOf(stroke).getBounds();
    return stroke.tool == StrokeTool.neon
        ? bounds.inflate(stroke.size * neonGlowFactor * 3)
        : bounds;
  }

  static Path _coreOf(DrawingStroke stroke) =>
      _cores[stroke] ??= _buildPath(stroke, stroke.size * neonCoreFactor);

  static double _widthOf(DrawingStroke stroke) => switch (stroke.tool) {
    StrokeTool.marker => stroke.size * markerWidthFactor,
    StrokeTool.pen || StrokeTool.neon || StrokeTool.eraser => stroke.size,
  };

  static Path _buildPath(DrawingStroke stroke, double width) {
    final hasPressure = stroke.points.any((p) => p.pressure != 0.5);
    final flat =
        stroke.tool == StrokeTool.marker || stroke.tool == StrokeTool.eraser;
    final options = pf.StrokeOptions(
      size: width,
      thinning: flat ? 0 : (hasPressure ? 0.6 : 0.35),
      smoothing: 0.5,
      streamline: 0.45,
      simulatePressure: !flat && !hasPressure,
      isComplete: true,
    );
    final input = [
      for (final p in stroke.points) pf.PointVector(p.x, p.y, p.pressure),
    ];
    final outline = pf.getStroke(input, options: options);
    final path = Path();
    if (outline.isEmpty) {
      return path;
    }
    if (outline.length < 3) {
      final c = outline.first;
      return path..addOval(Rect.fromCircle(center: c, radius: width / 2));
    }
    path.moveTo(outline.first.dx, outline.first.dy);
    for (var i = 0; i < outline.length - 1; i++) {
      final p0 = outline[i];
      final p1 = outline[i + 1];
      path.quadraticBezierTo(
        p0.dx,
        p0.dy,
        (p0.dx + p1.dx) / 2,
        (p0.dy + p1.dy) / 2,
      );
    }
    return path..close();
  }
}
