import 'package:flutter/foundation.dart';

/// Limits applied to captured and picked media.
@immutable
class MediaConstraints {
  /// Creates media constraints.
  const MediaConstraints({
    this.maxVideoDuration = const Duration(seconds: 60),
    this.minVideoDuration = const Duration(seconds: 1),
    this.photoWithMusicDuration = const Duration(seconds: 15),
    this.allowPhotos = true,
    this.allowVideos = true,
    this.maxImportFileSizeBytes,
  }) : assert(allowPhotos || allowVideos, 'Allow photos, videos or both.');

  /// Longest story video. Recording stops here; longer gallery videos open
  /// in the trimmer.
  final Duration maxVideoDuration;

  /// Shortest story video. Shorter recordings are discarded with a notice.
  final Duration minVideoDuration;

  /// Length of the video produced from a photo with music. Clamped to
  /// [maxVideoDuration] and to the track length.
  final Duration photoWithMusicDuration;

  /// Whether photos can be captured and picked.
  final bool allowPhotos;

  /// Whether videos can be recorded and picked.
  final bool allowVideos;

  /// Rejects picked files larger than this, if set.
  final int? maxImportFileSizeBytes;
}
