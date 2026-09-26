import 'dart:math' as math;
import 'dart:ui';

import '../../model/story_overlay.dart';
import 'story_text_layout.dart';

/// Paints the background of a text overlay: one rounded box (solid,
/// translucent) or a rounded highlight hugging each line.
abstract final class TextBackgroundPainter {
  /// Alpha of the translucent box.
  static const double translucentAlpha = 0.5;

  /// Paints the background of [layout] with its bounds' top-left at
  /// [origin].
  static void paint(Canvas canvas, StoryTextLayout layout, Offset origin) {
    final style = layout.style;
    switch (style.background) {
      case TextBackgroundStyle.none:
        return;
      case TextBackgroundStyle.solid:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            origin & layout.size,
            Radius.circular(layout.radius),
          ),
          Paint()..color = style.color,
        );
      case TextBackgroundStyle.translucent:
        final dark = style.color.computeLuminance() < 0.2;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            origin & layout.size,
            Radius.circular(layout.radius),
          ),
          Paint()
            ..color = (dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000))
                .withValues(alpha: translucentAlpha),
        );
      case TextBackgroundStyle.highlight:
        final path = highlightPath(layout.lineRects, layout.radius);
        canvas.drawPath(path.shift(origin), Paint()..color = style.color);
    }
  }

  /// A merged outline of rounded per-line boxes: convex corners are
  /// rounded, and where a narrower line meets a wider one the inner corner
  /// is filled with a concave fillet. `null` entries (empty lines) split the
  /// highlight into separate blocks.
  static Path highlightPath(List<Rect?> lines, double radius) {
    final path = Path();
    var i = 0;
    while (i < lines.length) {
      if (lines[i] == null) {
        i++;
        continue;
      }
      final block = <Rect>[];
      while (i < lines.length && lines[i] != null) {
        block.add(lines[i]!);
        i++;
      }
      var r = radius;
      for (final line in block) {
        r = math.min(r, math.min(line.height, line.width) / 2);
      }
      _addBlock(path, snapEdges(block, r), r);
    }
    return path;
  }

  /// Makes nearly aligned edges of adjacent lines exactly equal (within
  /// `2 × radius`), so no tiny steps or overlapping corners appear.
  static List<Rect> snapEdges(List<Rect> block, double radius) {
    final lefts = [for (final r in block) r.left];
    final rights = [for (final r in block) r.right];
    final threshold = 2 * radius;
    for (var pass = 0; pass < block.length; pass++) {
      var changed = false;
      for (var k = 1; k < block.length; k++) {
        final dl = (lefts[k] - lefts[k - 1]).abs();
        if (dl > 0 && dl < threshold) {
          lefts[k] = lefts[k - 1] = math.min(lefts[k], lefts[k - 1]);
          changed = true;
        }
        final dr = (rights[k] - rights[k - 1]).abs();
        if (dr > 0 && dr < threshold) {
          rights[k] = rights[k - 1] = math.max(rights[k], rights[k - 1]);
          changed = true;
        }
      }
      if (!changed) {
        break;
      }
    }
    return [
      for (var k = 0; k < block.length; k++)
        Rect.fromLTRB(lefts[k], block[k].top, rights[k], block[k].bottom),
    ];
  }

  /// Half-height of the strip that joins adjacent line boxes, canvas units.
  static const double _seamOverlap = 1;

  static void _addBlock(Path path, List<Rect> block, double r) {
    const eps = 0.01;
    final round = Radius.circular(r);
    for (var k = 0; k < block.length; k++) {
      final rect = block[k];
      final prev = k > 0 ? block[k - 1] : null;
      final next = k < block.length - 1 ? block[k + 1] : null;
      path.addRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: prev == null || prev.left > rect.left + eps
              ? round
              : Radius.zero,
          topRight: prev == null || prev.right < rect.right - eps
              ? round
              : Radius.zero,
          bottomLeft: next == null || next.left > rect.left + eps
              ? round
              : Radius.zero,
          bottomRight: next == null || next.right < rect.right - eps
              ? round
              : Radius.zero,
        ),
      );
      if (next == null) {
        continue;
      }
      final y = rect.bottom;
      // Line boxes meet edge to edge; anti-aliasing each box separately
      // leaves a hairline seam there. A thin strip across the joint, where
      // both boxes are straight, makes the fill one continuous shape.
      final seamLeft = math.max(rect.left, next.left);
      final seamRight = math.min(rect.right, next.right);
      if (seamRight > seamLeft) {
        path.addRect(
          Rect.fromLTRB(
            seamLeft,
            y - _seamOverlap,
            seamRight,
            y + _seamOverlap,
          ),
        );
      }
      if (rect.right > next.right + eps) {
        _addFillet(path, Offset(next.right, y), 1, 1, r);
      } else if (next.right > rect.right + eps) {
        _addFillet(path, Offset(rect.right, y), 1, -1, r);
      }
      if (rect.left < next.left - eps) {
        _addFillet(path, Offset(next.left, y), -1, 1, r);
      } else if (next.left < rect.left - eps) {
        _addFillet(path, Offset(rect.left, y), -1, -1, r);
      }
    }
  }

  /// Fills the concave corner at [corner]: the `r × r` square extending in
  /// direction ([dx], [dy]) minus the circle of radius [r] centred at its
  /// far corner.
  static void _addFillet(
    Path path,
    Offset corner,
    double dx,
    double dy,
    double r,
  ) {
    path
      ..moveTo(corner.dx, corner.dy)
      ..lineTo(corner.dx + dx * r, corner.dy)
      ..arcToPoint(
        Offset(corner.dx, corner.dy + dy * r),
        radius: Radius.circular(r),
        clockwise: dx * dy < 0,
      )
      ..close();
  }
}
