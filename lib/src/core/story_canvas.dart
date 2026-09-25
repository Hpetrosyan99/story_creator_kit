import 'dart:math' as math;
import 'dart:ui';

import '../model/media_placement.dart';
import '../model/story_media.dart';

/// Geometry of the fixed story canvas.
///
/// Every edit is stored in canvas units on a 1080×1920 (9:16) canvas. The
/// editor scales the canvas to the screen; export renders it at 1:1.
abstract final class StoryCanvas {
  /// Canvas width in canvas units (and output pixels).
  static const double width = 1080;

  /// Canvas height in canvas units (and output pixels).
  static const double height = 1920;

  /// Canvas size.
  static const Size size = Size(width, height);

  /// Canvas bounds.
  static const Rect bounds = Rect.fromLTWH(0, 0, width, height);

  /// Canvas centre.
  static const Offset center = Offset(width / 2, height / 2);

  /// Output pixel size.
  static const int outputWidth = 1080;

  /// Output pixel size.
  static const int outputHeight = 1920;

  /// Media whose aspect ratio is within this fraction of 9:16 fills the
  /// canvas by default.
  static const double fillTolerance = 0.18;

  /// Size of media with [aspectRatio] fitted inside the canvas.
  static Size containSize(double aspectRatio) {
    const canvasAspect = width / height;
    return aspectRatio > canvasAspect
        ? Size(width, width / aspectRatio)
        : Size(height * aspectRatio, height);
  }

  /// Scale (relative to contain) at which media with [aspectRatio] covers
  /// the whole canvas.
  static double coverScale(double aspectRatio) {
    final contain = containSize(aspectRatio);
    return math.max(width / contain.width, height / contain.height);
  }

  /// Default placement: fill the canvas when the media is close to 9:16,
  /// otherwise show it whole on the background.
  static MediaPlacement defaultPlacement(StoryMedia media) {
    const canvasAspect = width / height;
    final ratio = media.aspectRatio / canvasAspect;
    final nearStory = (ratio - 1).abs() <= fillTolerance;
    return MediaPlacement(scale: nearStory ? coverScale(media.aspectRatio) : 1);
  }

  /// Where media with [aspectRatio] is drawn, in canvas units.
  static Rect mediaRect(double aspectRatio, MediaPlacement placement) {
    final contain = containSize(aspectRatio);
    return Rect.fromCenter(
      center: center + placement.offset,
      width: contain.width * placement.scale,
      height: contain.height * placement.scale,
    );
  }

  /// Scale factor from canvas units to a viewport of [viewport] size that
  /// shows the whole canvas (contain).
  static double viewScale(Size viewport) =>
      math.min(viewport.width / width, viewport.height / height);
}
