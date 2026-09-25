import 'dart:io';

import '../api/config/media_constraints.dart';
import '../api/errors/story_exception.dart';
import '../api/result/story_result.dart';
import '../model/story_media.dart';
import '../services/capture/capture_service.dart';
import '../services/gallery/gallery_source.dart';
import '../services/media/media_inspector.dart';
import 'session_files.dart';

/// A video shorter than `MediaConstraints.minVideoDuration`.
///
/// Carries [StoryErrorCode.mediaTooShort] plus the measured and required
/// lengths.
class MediaTooShortException extends StoryException {
  /// Creates the exception for a video of [duration].
  MediaTooShortException(this.duration, this.minimum)
    : super(
        StoryErrorCode.mediaTooShort,
        'Video is ${duration.inMilliseconds} ms long; the minimum is '
        '${minimum.inMilliseconds} ms.',
      );

  /// Length of the rejected video.
  final Duration duration;

  /// The configured minimum.
  final Duration minimum;
}

/// Turns captured and picked files into validated [StoryMedia] inside the
/// session directory.
///
/// Rules:
/// * the media type must be allowed by [constraints];
/// * the file must exist and be readable (`mediaUnavailable`);
/// * it must not exceed `maxImportFileSizeBytes` (`mediaTooLarge`);
/// * the native probe must succeed (`mediaUnsupported` otherwise);
/// * videos shorter than `minVideoDuration` are rejected with
///   [MediaTooShortException]; videos longer than `maxVideoDuration` are
///   accepted (the flow opens the trimmer).
///
/// Captures are moved into the session (they are our own temp files).
/// Gallery files are copied, because on Android `originFile` can be the
/// user's original file in shared storage and must never be moved.
class MediaImporter {
  /// Creates an importer.
  const MediaImporter({
    required this.inspector,
    required this.session,
    required this.constraints,
  });

  /// Reads dimensions, duration and tracks.
  final MediaInspector inspector;

  /// Where imported files go.
  final SessionFiles session;

  /// Type, size and duration limits.
  final MediaConstraints constraints;

  /// Imports a camera capture. The capture file is moved into the session
  /// and deleted when validation fails.
  Future<StoryMedia> importCaptured(CapturedFile file) async {
    final String path;
    try {
      _checkType(file.type);
      await _checkFile(file.path);
      path = await session.adopt(file.path);
    } on Object {
      await _deleteQuietly(file.path);
      rethrow;
    }
    return _probe(
      path,
      type: file.type,
      source: StorySourceKind.camera,
      mirrored: file.mirrored,
      fallbackDuration: file.duration,
      mimeType: _mimeFor(path),
    );
  }

  /// Imports a picked gallery item. The file is copied into the session;
  /// the original is never touched.
  Future<StoryMedia> importPicked(PickedMedia media) async {
    _checkType(media.type);
    await _checkFile(media.path);
    final ext = _extensionOf(media.path) ?? _defaultExtension(media.type);
    final target = session.newPath(ext, prefix: 'src');
    try {
      await File(media.path).copy(target);
    } on FileSystemException catch (e, s) {
      await _deleteQuietly(target);
      throw StoryException(
        StoryErrorCode.mediaUnavailable,
        'Could not copy the picked file into the session.',
        e,
        s,
      );
    }
    return _probe(
      target,
      type: media.type,
      source: StorySourceKind.gallery,
      mirrored: false,
      fallbackDuration: null,
      mimeType: media.mimeType ?? _mimeFor(target),
    );
  }

  void _checkType(StoryMediaType type) {
    final allowed = switch (type) {
      StoryMediaType.photo => constraints.allowPhotos,
      StoryMediaType.video => constraints.allowVideos,
    };
    if (!allowed) {
      throw StoryException(
        StoryErrorCode.mediaUnsupported,
        '${type.name} is not allowed by MediaConstraints.',
      );
    }
  }

  Future<void> _checkFile(String path) async {
    final file = File(path);
    final int length;
    try {
      length = await file.length();
    } on FileSystemException catch (e, s) {
      throw StoryException(
        StoryErrorCode.mediaUnavailable,
        'The file cannot be read.',
        e,
        s,
      );
    }
    final max = constraints.maxImportFileSizeBytes;
    if (max != null && length > max) {
      throw StoryException(
        StoryErrorCode.mediaTooLarge,
        'The file has $length bytes; the limit is $max.',
      );
    }
  }

  Future<StoryMedia> _probe(
    String path, {
    required StoryMediaType type,
    required StorySourceKind source,
    required bool mirrored,
    required Duration? fallbackDuration,
    required String? mimeType,
  }) async {
    try {
      final MediaProbe probe;
      try {
        probe = await inspector.probe(path);
      } on StoryException {
        rethrow;
      } on Object catch (e, s) {
        throw StoryException(
          StoryErrorCode.mediaUnsupported,
          'The file could not be inspected.',
          e,
          s,
        );
      }
      if (probe.width <= 0 || probe.height <= 0) {
        throw const StoryException(
          StoryErrorCode.mediaUnsupported,
          'The file has no displayable size.',
        );
      }
      Duration? duration;
      if (type == StoryMediaType.video) {
        // The probed length is the truth; the capture timer is only a
        // fallback when the platform cannot report it.
        duration = probe.duration ?? fallbackDuration;
        if (duration == null) {
          throw const StoryException(
            StoryErrorCode.mediaUnsupported,
            'The video has no readable duration.',
          );
        }
        if (duration < constraints.minVideoDuration) {
          throw MediaTooShortException(duration, constraints.minVideoDuration);
        }
      }
      return StoryMedia(
        path: path,
        type: type,
        width: probe.width,
        height: probe.height,
        source: source,
        duration: duration,
        rotationDegrees: probe.rotationDegrees,
        hasAudio: type == StoryMediaType.video && probe.hasAudio,
        mirrored: mirrored,
        mimeType: mimeType,
      );
    } on Object {
      await _deleteQuietly(path);
      rethrow;
    }
  }

  /// Best-effort removal of a rejected file. A failure here leaves the file
  /// in the session directory, which is deleted when the session ends.
  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) {
        await file.delete();
      }
    } on FileSystemException {
      return;
    }
  }

  static String? _extensionOf(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) {
      return null;
    }
    return name.substring(dot + 1).toLowerCase();
  }

  static String _defaultExtension(StoryMediaType type) =>
      type == StoryMediaType.photo ? 'jpg' : 'mp4';

  static String? _mimeFor(String path) => switch (_extensionOf(path)) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'mp4' || 'm4v' => 'video/mp4',
    'mov' => 'video/quicktime',
    '3gp' => 'video/3gpp',
    'webm' => 'video/webm',
    'mkv' => 'video/x-matroska',
    _ => null,
  };
}
