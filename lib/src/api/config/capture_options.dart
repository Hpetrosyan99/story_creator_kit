import 'package:flutter/foundation.dart';

/// Which camera the story creator opens with.
enum StoryCameraLens {
  /// The rear (world-facing) camera.
  back,

  /// The front (selfie) camera.
  front,
}

/// How the user picks existing media.
enum GalleryMode {
  /// In-app grid of recent photos and videos with album switching.
  ///
  /// Needs photo library permission. On Android this means `READ_MEDIA_*`
  /// permissions, which Google Play only allows with a policy declaration.
  inApp,

  /// The system photo picker. No permission needed.
  systemPicker,

  /// No gallery access; camera only.
  disabled,
}

/// Capture resolution requested from the camera.
enum CaptureResolution {
  /// About 720p.
  medium,

  /// About 1080p. Matches the 1080×1920 story output.
  high,

  /// The highest the device offers.
  max,
}

/// Camera and gallery options.
@immutable
class CaptureOptions {
  /// Creates capture options.
  const CaptureOptions({
    this.initialLens = StoryCameraLens.back,
    this.enablePhoto = true,
    this.enableVideo = true,
    this.enableAudio = true,
    this.enableFlash = true,
    this.enableLensSwitch = true,
    this.enableZoom = true,
    this.galleryMode = GalleryMode.inApp,
    this.resolution = CaptureResolution.high,
  }) : assert(
         enablePhoto || enableVideo || galleryMode != GalleryMode.disabled,
         'Enable at least one way to get media.',
       );

  /// Lens used when the camera opens.
  final StoryCameraLens initialLens;

  /// Tap the shutter to take a photo.
  final bool enablePhoto;

  /// Hold the shutter to record a video.
  final bool enableVideo;

  /// Record sound with videos (needs microphone permission).
  final bool enableAudio;

  /// Show the flash control when the lens has a flash (screen flash for the
  /// front camera).
  final bool enableFlash;

  /// Show the lens switch when more than one lens exists.
  final bool enableLensSwitch;

  /// Pinch and drag-to-zoom.
  final bool enableZoom;

  /// How existing media is picked.
  final GalleryMode galleryMode;

  /// Requested capture resolution.
  final CaptureResolution resolution;
}
