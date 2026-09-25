import 'dart:math' as math;
import 'dart:ui';

import '../../model/story_overlay.dart';
import '../../render/painters/story_edits_painter.dart';
import '../../render/painters/story_paint_resources.dart';

/// Hit testing and bounds of overlays, in canvas units.
abstract final class OverlayGeometry {
  /// The topmost overlay under [point], or `null`.
  ///
  /// Each overlay's box is grown to at least [minExtent] canvas units per
  /// side (as drawn, i.e. after scaling) so small items stay grabbable.
  static StoryOverlay? hitTest(
    List<StoryOverlay> overlays,
    Offset point,
    StoryPaintResources resources, {
    double minExtent = 0,
  }) {
    for (final overlay in overlays.reversed) {
      if (contains(overlay, point, resources, minExtent: minExtent)) {
        return overlay;
      }
    }
    return null;
  }

  /// Whether [point] lies inside [overlay]'s (rotated) box.
  static bool contains(
    StoryOverlay overlay,
    Offset point,
    StoryPaintResources resources, {
    double minExtent = 0,
  }) {
    final t = overlay.transform;
    final size = StoryEditsPainter.overlaySize(overlay, resources);
    final local = _rotate(point - t.position, -t.rotation) / t.scale;
    final minHalf = minExtent / 2 / t.scale;
    final hx = math.max(size.width / 2, minHalf);
    final hy = math.max(size.height / 2, minHalf);
    return local.dx.abs() <= hx && local.dy.abs() <= hy;
  }

  /// Axis-aligned bounds of [overlay] as drawn.
  static Rect bounds(StoryOverlay overlay, StoryPaintResources resources) {
    final t = overlay.transform;
    final size = StoryEditsPainter.overlaySize(overlay, resources) * t.scale;
    final corners = [
      Offset(-size.width / 2, -size.height / 2),
      Offset(size.width / 2, -size.height / 2),
      Offset(size.width / 2, size.height / 2),
      Offset(-size.width / 2, size.height / 2),
    ].map((c) => _rotate(c, t.rotation) + t.position);
    var left = double.infinity;
    var top = double.infinity;
    var right = -double.infinity;
    var bottom = -double.infinity;
    for (final c in corners) {
      left = math.min(left, c.dx);
      top = math.min(top, c.dy);
      right = math.max(right, c.dx);
      bottom = math.max(bottom, c.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  static Offset _rotate(Offset v, double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  }
}
