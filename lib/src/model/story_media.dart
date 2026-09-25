import 'package:flutter/foundation.dart';

import '../api/result/story_result.dart';

/// The source photo or video being edited.
///
/// [width] and [height] are the *display* size, i.e. after applying the
/// file's rotation metadata; [rotationDegrees] is kept for the native export.
@immutable
class StoryMedia {
  /// Creates source media.
  const StoryMedia({
    required this.path,
    required this.type,
    required this.width,
    required this.height,
    required this.source,
    this.duration,
    this.rotationDegrees = 0,
    this.hasAudio = false,
    this.mirrored = false,
    this.mimeType,
  });

  /// Absolute path of a local, readable file.
  final String path;

  /// Photo or video.
  final StoryMediaType type;

  /// Display width in pixels.
  final int width;

  /// Display height in pixels.
  final int height;

  /// Camera or gallery.
  final StorySourceKind source;

  /// Video length; `null` for photos.
  final Duration? duration;

  /// Clockwise rotation stored in the file's metadata (0, 90, 180, 270).
  final int rotationDegrees;

  /// Whether the video has an audio track.
  final bool hasAudio;

  /// Whether the pixels must be flipped horizontally to match what the user
  /// saw (front-camera captures on some platforms).
  final bool mirrored;

  /// MIME type, if known.
  final String? mimeType;

  /// Whether this is a video.
  bool get isVideo => type == StoryMediaType.video;

  /// Display aspect ratio (width / height).
  double get aspectRatio => width / height;

  /// Returns a copy with the given values replaced.
  StoryMedia copyWith({
    String? path,
    int? width,
    int? height,
    Duration? duration,
    int? rotationDegrees,
    bool? hasAudio,
    bool? mirrored,
  }) => StoryMedia(
    path: path ?? this.path,
    type: type,
    width: width ?? this.width,
    height: height ?? this.height,
    source: source,
    duration: duration ?? this.duration,
    rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    hasAudio: hasAudio ?? this.hasAudio,
    mirrored: mirrored ?? this.mirrored,
    mimeType: mimeType,
  );

  @override
  bool operator ==(Object other) =>
      other is StoryMedia &&
      other.path == path &&
      other.type == type &&
      other.width == width &&
      other.height == height &&
      other.source == source &&
      other.duration == duration &&
      other.rotationDegrees == rotationDegrees &&
      other.hasAudio == hasAudio &&
      other.mirrored == mirrored;

  @override
  int get hashCode => Object.hash(
    path,
    type,
    width,
    height,
    source,
    duration,
    rotationDegrees,
    hasAudio,
    mirrored,
  );
}
