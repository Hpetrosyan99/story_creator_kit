import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../api/assets/story_filter.dart';
import '../core/story_canvas.dart';
import '../model/story_document.dart';
import '../model/story_media.dart';
import 'overlay_rasterizer.dart';
import 'painters/story_edits_painter.dart';
import 'painters/story_paint_resources.dart';

/// Paints the edits (drawing and overlays) of a document.
typedef EditsPainter = void Function(
  Canvas canvas,
  StoryDocument document,
  StoryPaintResources resources,
);

/// Composes the images the export needs, at output resolution, with the same
/// painters as the editor preview.
///
/// Callers must have loaded [StoryPaintResources] for the document
/// (`ensureStoryPaintResources`) before composing.
class FrameComposer {
  /// Creates a composer. [paintEdits] defaults to
  /// `StoryEditsPainter.paintEdits`.
  const FrameComposer({
    this.rasterizer = const OverlayRasterizer(),
    this.paintEdits = StoryEditsPainter.paintEdits,
    this.maxDecodeSide = 4096,
  });

  /// Rasterizes at output size.
  final OverlayRasterizer rasterizer;

  /// Paints strokes and overlays.
  final EditsPainter paintEdits;

  /// Longest side a photo is decoded at.
  final int maxDecodeSide;

  /// The complete photo story frame: background, the photo with its filter
  /// (EXIF orientation respected, mirrored when `media.mirrored`) clipped to
  /// the canvas, then the edits.
  Future<ui.Image> composePhotoFrame(
    StoryDocument document,
    StoryPaintResources resources,
  ) async {
    final media = document.media;
    final rect = StoryCanvas.mediaRect(media.aspectRatio, document.placement);
    final photo = await decodePhoto(media, rect.size);
    try {
      final filter = resources.filter(document.filterId);
      return await rasterizer.rasterize((canvas) {
        StoryEditsPainter.paintBackground(canvas, document.background);
        paintPhoto(canvas, photo, media, rect, filter);
        paintEdits(canvas, document, resources);
      });
    } finally {
      photo.dispose();
    }
  }

  /// The overlay for a video story: the background with a transparent hole
  /// where the video shows (media rect ∩ canvas), plus the edits. The native
  /// exporter draws the video underneath.
  Future<ui.Image> composeVideoOverlay(
    StoryDocument document,
    StoryPaintResources resources,
  ) => rasterizer.rasterize((canvas) {
    StoryEditsPainter.paintBackground(canvas, document.background);
    final hole = videoRect(document).intersect(StoryCanvas.bounds);
    if (hole.width > 0 && hole.height > 0) {
      canvas.drawRect(hole, Paint()..blendMode = BlendMode.clear);
    }
    paintEdits(canvas, document, resources);
  });

  /// Where the media sits, in canvas units.
  static Rect videoRect(StoryDocument document) =>
      StoryCanvas.mediaRect(document.media.aspectRatio, document.placement);

  /// Decodes the photo at about the size it is drawn (never above its own
  /// size or [maxDecodeSide]).
  Future<ui.Image> decodePhoto(StoryMedia media, Size drawSize) async {
    final buffer = await ui.ImmutableBuffer.fromFilePath(media.path);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      final w = descriptor.width;
      final h = descriptor.height;
      final wanted = math.min(
        maxDecodeSide.toDouble(),
        math.max(drawSize.width, drawSize.height),
      );
      final scale = math.min(1, wanted / math.max(w, h));
      final codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (w * scale).round()),
        targetHeight: math.max(1, (h * scale).round()),
      );
      try {
        final frame = await codec.getNextFrame();
        return frame.image;
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }

  /// Draws [image] into [rect]. When the decoder did not apply the file's
  /// 90°/270° orientation (decoded aspect does not match the display
  /// aspect), the rotation is applied here.
  static void paintPhoto(
    Canvas canvas,
    ui.Image image,
    StoryMedia media,
    Rect rect,
    StoryFilter? filter,
  ) {
    final decodedLandscape = image.width > image.height;
    final displayLandscape = media.width > media.height;
    final quarterTurn =
        media.rotationDegrees % 180 == 90 &&
        image.width != image.height &&
        decodedLandscape != displayLandscape;
    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true;
    if (filter != null && !filter.isIdentity) {
      paint.colorFilter = ColorFilter.matrix(filter.matrix);
    }
    final drawSize = quarterTurn
        ? Size(rect.height, rect.width)
        : Size(rect.width, rect.height);
    canvas
      ..save()
      ..clipRect(StoryCanvas.bounds)
      ..translate(rect.center.dx, rect.center.dy);
    if (media.mirrored) {
      canvas.scale(-1, 1);
    }
    if (quarterTurn) {
      canvas.rotate(media.rotationDegrees * math.pi / 180);
    }
    canvas
      ..drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromCenter(
          center: Offset.zero,
          width: drawSize.width,
          height: drawSize.height,
        ),
        paint,
      )
      ..restore();
  }
}
