import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../model/drawing_stroke.dart';

/// The brush the drawing tool paints with. Kept by the editor so the choice
/// survives switching tools.
@immutable
class DrawingBrush {
  /// Creates a brush.
  const DrawingBrush({
    required this.tool,
    required this.color,
    required this.size,
  });

  /// Pen, marker, neon or eraser.
  final StrokeTool tool;

  /// Colour (ignored by the eraser).
  final Color color;

  /// Width in canvas units.
  final double size;

  /// Returns a copy with the given values replaced.
  DrawingBrush copyWith({StrokeTool? tool, Color? color, double? size}) =>
      DrawingBrush(
        tool: tool ?? this.tool,
        color: color ?? this.color,
        size: size ?? this.size,
      );

  @override
  bool operator ==(Object other) =>
      other is DrawingBrush &&
      other.tool == tool &&
      other.color == color &&
      other.size == size;

  @override
  int get hashCode => Object.hash(tool, color, size);
}
