import 'dart:ui';

import '../../core/story_canvas.dart';
import '../../model/drawing_stroke.dart';
import '../../model/media_placement.dart';
import '../../model/overlay_transform.dart';
import '../../model/story_document.dart';
import '../../model/story_overlay.dart';
import 'sticker_painter.dart';
import 'story_paint_resources.dart';
import 'story_text_layout.dart';
import 'stroke_renderer.dart';

/// Paints the parts of a story that are not the media itself: background,
/// drawing and overlays.
///
/// This is the single source of truth for how edits look. The editor's live
/// canvas and the export rasterizer both call it with a canvas already
/// scaled so that one unit is one canvas unit (1080×1920). Painting must be
/// deterministic and independent of screen size, text scale and locale.
abstract final class StoryEditsPainter {
  /// Fills the canvas with the background gradient.
  static void paintBackground(Canvas canvas, StoryBackground background) {
    final paint = Paint()
      ..shader = Gradient.linear(
        StoryCanvas.bounds.topCenter,
        StoryCanvas.bounds.bottomCenter,
        [background.top, background.bottom],
      );
    canvas.drawRect(StoryCanvas.bounds, paint);
  }

  /// Paints [strokes] in order; eraser strokes clear earlier strokes only
  /// (never the media), so they are drawn inside their own layer.
  static void paintStrokes(Canvas canvas, List<DrawingStroke> strokes) {
    if (strokes.isEmpty) {
      return;
    }
    final needsLayer = strokes.any((s) => s.tool == StrokeTool.eraser);
    if (needsLayer) {
      canvas.saveLayer(StoryCanvas.bounds, Paint());
    }
    for (final stroke in strokes) {
      StrokeRenderer.paintStroke(canvas, stroke);
    }
    if (needsLayer) {
      canvas.restore();
    }
  }

  /// Paints one overlay at its transform.
  static void paintOverlay(
    Canvas canvas,
    StoryOverlay overlay,
    StoryPaintResources resources,
  ) {
    paintOverlayAt(canvas, overlay, overlay.transform, resources);
  }

  /// Paints [overlay] at [transform] instead of its own (drag previews).
  static void paintOverlayAt(
    Canvas canvas,
    StoryOverlay overlay,
    OverlayTransform transform,
    StoryPaintResources resources,
  ) {
    final size = overlaySize(overlay, resources);
    canvas
      ..save()
      ..translate(transform.position.dx, transform.position.dy)
      ..rotate(transform.rotation)
      ..scale(transform.scale);
    final origin = Offset(-size.width / 2, -size.height / 2);
    switch (overlay) {
      case TextOverlay():
        StoryTextLayout.of(
          overlay,
          resources.font(overlay.style.fontId),
        ).paint(canvas, origin);
      case StickerOverlay():
        StickerPainter.paintSticker(
          canvas,
          resources.sticker(overlay.stickerId),
          origin,
          size,
        );
      case EmojiOverlay():
        StickerPainter.paintEmoji(canvas, overlay, origin);
    }
    canvas.restore();
  }

  /// Paints strokes, then overlays bottom to top.
  static void paintEdits(
    Canvas canvas,
    StoryDocument document,
    StoryPaintResources resources,
  ) {
    paintStrokes(canvas, document.strokes);
    for (final overlay in document.overlays) {
      paintOverlay(canvas, overlay, resources);
    }
  }

  /// Size of [overlay] at scale 1, before rotation, in canvas units. Used for
  /// hit testing and selection bounds.
  static Size overlaySize(
    StoryOverlay overlay,
    StoryPaintResources resources,
  ) => switch (overlay) {
    TextOverlay() => StoryTextLayout.of(
      overlay,
      resources.font(overlay.style.fontId),
    ).size,
    StickerOverlay() => StickerPainter.stickerSize(
      overlay,
      resources.sticker(overlay.stickerId),
    ),
    EmojiOverlay() => StickerPainter.emojiSize(overlay),
  };
}
