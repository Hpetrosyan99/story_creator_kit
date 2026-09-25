import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../model/media_placement.dart';
import '../../model/story_overlay.dart';
import '../../render/painters/story_edits_painter.dart';
import '../../render/painters/story_paint_resources.dart';

/// Paints the overlays with the shared painter, scaled to the view.
class OverlayLayer extends StatelessWidget {
  /// Creates the layer.
  const OverlayLayer({
    required this.overlays,
    required this.resources,
    required this.viewScale,
    required this.resourcesRevision,
    this.hiddenId,
    super.key,
  });

  /// Overlays bottom to top.
  final List<StoryOverlay> overlays;

  /// Fonts and stickers.
  final StoryPaintResources resources;

  /// Screen pixels per canvas unit.
  final double viewScale;

  /// Changes when fonts or stickers finish loading, to repaint.
  final int resourcesRevision;

  /// Overlay not painted (being edited in the text editor).
  final String? hiddenId;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _OverlaysPainter(
          overlays: overlays,
          resources: resources,
          scale: viewScale,
          revision: resourcesRevision,
          hiddenId: hiddenId,
        ),
      ),
    ),
  );
}

class _OverlaysPainter extends CustomPainter {
  const _OverlaysPainter({
    required this.overlays,
    required this.resources,
    required this.scale,
    required this.revision,
    required this.hiddenId,
  });

  final List<StoryOverlay> overlays;
  final StoryPaintResources resources;
  final double scale;
  final int revision;
  final String? hiddenId;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(scale);
    for (final overlay in overlays) {
      if (overlay.id != hiddenId) {
        StoryEditsPainter.paintOverlay(canvas, overlay, resources);
      }
    }
  }

  @override
  bool shouldRepaint(_OverlaysPainter oldDelegate) =>
      !listEquals(oldDelegate.overlays, overlays) ||
      oldDelegate.resources != resources ||
      oldDelegate.scale != scale ||
      oldDelegate.revision != revision ||
      oldDelegate.hiddenId != hiddenId;
}

/// Paints the background gradient with the shared painter.
class BackgroundLayer extends StatelessWidget {
  /// Creates the layer.
  const BackgroundLayer({
    required this.background,
    required this.viewScale,
    super.key,
  });

  /// The gradient.
  final StoryBackground background;

  /// Screen pixels per canvas unit.
  final double viewScale;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.infinite,
    painter: _BackgroundPainter(background, viewScale),
  );
}

class _BackgroundPainter extends CustomPainter {
  const _BackgroundPainter(this.background, this.scale);

  final StoryBackground background;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(scale);
    StoryEditsPainter.paintBackground(canvas, background);
  }

  @override
  bool shouldRepaint(_BackgroundPainter oldDelegate) =>
      oldDelegate.background != background || oldDelegate.scale != scale;
}
