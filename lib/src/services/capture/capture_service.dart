import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../api/config/capture_options.dart';
import '../../api/result/story_result.dart';

/// Flash behaviour for photos. Videos use the torch when [on].
enum StoryFlashMode {
  /// No flash.
  off,

  /// Flash when the scene is dark (photos only; videos treat it as off).
  auto,

  /// Always flash (photos) / torch on (videos).
  on,
}

/// What the current camera can do.
@immutable
class CaptureCapabilities {
  /// Creates capabilities.
  const CaptureCapabilities({
    required this.lens,
    required this.availableLenses,
    required this.hasFlash,
    required this.minZoom,
    required this.maxZoom,
    required this.previewAspectRatio,
  });

  /// Lens in use.
  final StoryCameraLens lens;

  /// Lenses the device has.
  final Set<StoryCameraLens> availableLenses;

  /// Whether the lens in use has a hardware flash / torch.
  final bool hasFlash;

  /// Minimum zoom factor.
  final double minZoom;

  /// Maximum zoom factor.
  final double maxZoom;

  /// Preview aspect ratio in portrait (width / height).
  final double previewAspectRatio;

  /// Whether a lens switch is possible.
  bool get canSwitchLens => availableLenses.length > 1;
}

/// A file produced by the camera.
@immutable
class CapturedFile {
  /// Creates a captured file.
  const CapturedFile({
    required this.path,
    required this.type,
    required this.lens,
    this.duration,
    this.mirrored = false,
  });

  /// Absolute path.
  final String path;

  /// Photo or video.
  final StoryMediaType type;

  /// Lens used.
  final StoryCameraLens lens;

  /// Recorded length (measured by the service; the file's real duration is
  /// read again during import).
  final Duration? duration;

  /// Whether the saved pixels must be mirrored to match the preview.
  final bool mirrored;
}

/// Something that happened to the camera session outside a direct call.
@immutable
sealed class CaptureEvent {
  const CaptureEvent();
}

/// The session stopped (backgrounded, a call, another app took the camera,
/// camera disconnected). The service must be initialised again.
final class CaptureInterrupted extends CaptureEvent {
  /// Creates an interruption event.
  const CaptureInterrupted(this.reason, {this.partialRecording});

  /// Developer-facing reason.
  final String reason;

  /// The part recorded before the interruption, if any was saved.
  final CapturedFile? partialRecording;
}

/// The camera failed irrecoverably.
final class CaptureFailed extends CaptureEvent {
  /// Creates a failure event.
  const CaptureFailed(this.error);

  /// The error (a `StoryException`).
  final Object error;
}

/// Camera access.
///
/// Implementations wrap a camera plugin; UI code only uses this interface.
/// All methods throw `StoryException` on failure.
abstract class CaptureService {
  /// Starts the camera with [lens].
  Future<CaptureCapabilities> initialize(
    StoryCameraLens lens, {
    required CaptureResolution resolution,
    required bool enableAudio,
  });

  /// Capabilities after [initialize], or `null`.
  CaptureCapabilities? get capabilities;

  /// Whether a preview is available.
  bool get isInitialized;

  /// Whether a recording is in progress.
  bool get isRecording;

  /// Session events (interruptions, failures).
  Stream<CaptureEvent> get events;

  /// The live preview, filling its parent with cover semantics.
  Widget buildPreview();

  /// Switches to the other lens; allowed while recording when the platform
  /// supports it.
  Future<CaptureCapabilities> switchLens();

  /// Sets the flash mode.
  Future<void> setFlashMode(StoryFlashMode mode);

  /// Sets the zoom factor, clamped to the capabilities.
  Future<void> setZoom(double zoom);

  /// Focuses and meters at [point] (0–1 in preview coordinates).
  Future<void> focusAt(Offset point);

  /// Takes a photo.
  Future<CapturedFile> takePhoto();

  /// Starts recording a video.
  Future<void> startRecording();

  /// Stops recording and returns the video.
  Future<CapturedFile> stopRecording();

  /// Releases the camera (app going to background). Call [initialize] to
  /// resume.
  Future<void> release();

  /// Releases everything. The service is unusable afterwards.
  Future<void> dispose();
}
