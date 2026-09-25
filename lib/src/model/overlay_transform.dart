import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Position, scale and rotation of an overlay on the canvas.
@immutable
class OverlayTransform {
  /// Creates a transform.
  const OverlayTransform({
    required this.position,
    this.scale = 1,
    this.rotation = 0,
  });

  /// Centre of the overlay in canvas units.
  final Offset position;

  /// Uniform scale; 1 is the overlay's natural size.
  final double scale;

  /// Clockwise rotation in radians.
  final double rotation;

  /// Returns a copy with the given values replaced.
  OverlayTransform copyWith({
    Offset? position,
    double? scale,
    double? rotation,
  }) => OverlayTransform(
    position: position ?? this.position,
    scale: scale ?? this.scale,
    rotation: rotation ?? this.rotation,
  );

  /// Rotation normalised to (-π, π].
  double get normalizedRotation {
    var r = rotation % (2 * math.pi);
    if (r > math.pi) {
      r -= 2 * math.pi;
    }
    return r;
  }

  @override
  bool operator ==(Object other) =>
      other is OverlayTransform &&
      other.position == position &&
      other.scale == scale &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(position, scale, rotation);
}
