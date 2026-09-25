import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../api/assets/story_filter.dart';
import '../../core/story_canvas.dart';
import '../../core/story_scope.dart';
import '../../model/media_placement.dart';
import '../../model/story_media.dart';

/// The photo or video, placed at `StoryCanvas.mediaRect`, mirrored when
/// needed and colour-filtered with the same 4×5 matrix export uses.
class MediaLayer extends StatelessWidget {
  /// Creates the layer.
  const MediaLayer({
    required this.media,
    required this.placement,
    required this.viewScale,
    this.filter,
    this.video,
    super.key,
  });

  /// Source media.
  final StoryMedia media;

  /// Placement in canvas units.
  final MediaPlacement placement;

  /// Screen pixels per canvas unit.
  final double viewScale;

  /// Selected filter, if any.
  final StoryFilter? filter;

  /// The video view (from `VideoSession.buildView`) for videos.
  final Widget? video;

  @override
  Widget build(BuildContext context) {
    final rect = StoryCanvas.mediaRect(media.aspectRatio, placement);
    final scaled = Rect.fromLTRB(
      rect.left * viewScale,
      rect.top * viewScale,
      rect.right * viewScale,
      rect.bottom * viewScale,
    );
    var child = media.isVideo
        ? (video ?? const SizedBox.expand())
        : _Photo(media: media, viewScale: viewScale);
    final matrix = filter;
    if (matrix != null && !matrix.isIdentity) {
      child = ColorFiltered(
        colorFilter: ColorFilter.matrix(matrix.matrix),
        child: child,
      );
    }
    if (media.mirrored) {
      child = Transform.flip(flipX: true, child: child);
    }
    return Stack(
      children: [
        Positioned.fromRect(
          rect: scaled,
          child: IgnorePointer(child: child),
        ),
      ],
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.media, required this.viewScale});

  final StoryMedia media;
  final double viewScale;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Stable decode size (independent of pinch) of about twice the canvas
    // width on screen, never above the source.
    final cacheWidth = math.min(
      media.width,
      (StoryCanvas.width * viewScale * dpr * 2).round(),
    );
    return Image.file(
      File(media.path),
      cacheWidth: cacheWidth > 0 ? cacheWidth : null,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) => Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: StoryScope.of(context).theme.onSurfaceMuted,
        ),
      ),
    );
  }
}
