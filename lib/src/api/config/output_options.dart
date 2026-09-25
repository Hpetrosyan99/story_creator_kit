import 'package:flutter/foundation.dart';

/// When the finished story is written to the device gallery.
enum SaveToGalleryMode {
  /// Never; the host handles the file.
  never,

  /// Offer a save button in the preview.
  button,

  /// Save automatically when the user confirms the story.
  always,
}

/// Export settings.
@immutable
class OutputOptions {
  /// Creates output options.
  const OutputOptions({
    this.jpegQuality = 90,
    this.videoBitrate = 8000000,
    this.frameRate = 30,
    this.saveToGallery = SaveToGalleryMode.button,
    this.galleryAlbum,
    this.showPreview = true,
    this.outputDirectory,
  }) : assert(jpegQuality > 0 && jpegQuality <= 100, 'JPEG quality is 1–100.');

  /// JPEG quality for photo stories, 1–100.
  final int jpegQuality;

  /// H.264 target bitrate in bits per second.
  final int videoBitrate;

  /// Output frame rate.
  final int frameRate;

  /// Gallery saving behaviour.
  final SaveToGalleryMode saveToGallery;

  /// Album name used when saving to the gallery, if any.
  final String? galleryAlbum;

  /// Show the exported file for confirmation before returning it.
  final bool showPreview;

  /// Directory for the exported file. Defaults to a `story_creator_exports`
  /// folder in the app's temporary directory; move the file if you need to
  /// keep it.
  final String? outputDirectory;
}
