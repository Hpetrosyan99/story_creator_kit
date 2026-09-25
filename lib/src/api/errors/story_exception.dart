/// Categories of failures reported by the story creator.
enum StoryErrorCode {
  /// No usable camera, or the camera failed to start.
  cameraUnavailable,

  /// The user denied camera access.
  cameraPermissionDenied,

  /// The user denied microphone access.
  microphonePermissionDenied,

  /// The user denied photo library access.
  photosPermissionDenied,

  /// Taking a photo or recording failed.
  captureFailed,

  /// The camera session was interrupted (backgrounding, a call, another app).
  captureInterrupted,

  /// The media format cannot be decoded on this device.
  mediaUnsupported,

  /// The media cannot be read (deleted, not downloaded, no access).
  mediaUnavailable,

  /// A video is shorter than `MediaConstraints.minVideoDuration`.
  mediaTooShort,

  /// The media is larger than `MediaConstraints.maxImportFileSizeBytes`.
  mediaTooLarge,

  /// A music track could not be resolved, downloaded or decoded.
  musicUnavailable,

  /// Rendering or encoding the story failed.
  exportFailed,

  /// Not enough free storage to export.
  insufficientStorage,

  /// Saving to the device gallery failed.
  saveToGalleryFailed,

  /// Anything else.
  unknown,
}

/// An error raised or reported by the story creator.
class StoryException implements Exception {
  /// Creates an exception.
  const StoryException(this.code, [this.message, this.cause, this.stackTrace]);

  /// Failure category.
  final StoryErrorCode code;

  /// Developer-facing description (not localised, not for display).
  final String? message;

  /// Underlying error, if any.
  final Object? cause;

  /// Stack trace of [cause], if any.
  final StackTrace? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer('StoryException(${code.name}');
    if (message != null) {
      buffer.write(': $message');
    }
    if (cause != null) {
      buffer.write(', cause: $cause');
    }
    buffer.write(')');
    return buffer.toString();
  }
}
