import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Brush kinds.
enum StrokeTool {
  /// Solid pen.
  pen,

  /// Semi-transparent, flat marker.
  marker,

  /// Bright core with a coloured glow.
  neon,

  /// Removes earlier strokes where it passes.
  eraser,
}

/// One sampled point of a stroke, in canvas units.
@immutable
class StrokePoint {
  /// Creates a point.
  const StrokePoint(this.x, this.y, [this.pressure = 0.5]);

  /// Horizontal position in canvas units.
  final double x;

  /// Vertical position in canvas units.
  final double y;

  /// Pressure 0–1 (0.5 when the device does not report pressure).
  final double pressure;

  @override
  bool operator ==(Object other) =>
      other is StrokePoint &&
      other.x == x &&
      other.y == y &&
      other.pressure == pressure;

  @override
  int get hashCode => Object.hash(x, y, pressure);
}

/// A freehand stroke.
@immutable
class DrawingStroke {
  /// Creates a stroke.
  const DrawingStroke({
    required this.points,
    required this.color,
    required this.size,
    this.tool = StrokeTool.pen,
  });

  /// Sampled points in drawing order.
  final List<StrokePoint> points;

  /// Brush colour (ignored by the eraser).
  final Color color;

  /// Brush width in canvas units.
  final double size;

  /// Brush kind.
  final StrokeTool tool;

  @override
  bool operator ==(Object other) =>
      other is DrawingStroke &&
      listEquals(other.points, points) &&
      other.color == color &&
      other.size == size &&
      other.tool == tool;

  @override
  int get hashCode => Object.hash(Object.hashAll(points), color, size, tool);
}
