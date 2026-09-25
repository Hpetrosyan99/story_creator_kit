import 'package:flutter/foundation.dart';

import '../api/music/music_models.dart';

/// Music chosen for the story.
@immutable
class MusicSelection {
  /// Creates a selection.
  const MusicSelection({
    required this.track,
    required this.start,
    required this.duration,
    this.localPath,
    this.volume = 1,
  });

  /// The track.
  final MusicTrack track;

  /// Offset into the track where the segment starts.
  final Duration start;

  /// Segment length. For videos this follows the trimmed video length.
  final Duration duration;

  /// Local audio file, once resolved/downloaded; required for export.
  final String? localPath;

  /// Music volume 0–1.
  final double volume;

  /// Returns a copy with the given values replaced.
  MusicSelection copyWith({
    Duration? start,
    Duration? duration,
    String? localPath,
    double? volume,
  }) => MusicSelection(
    track: track,
    start: start ?? this.start,
    duration: duration ?? this.duration,
    localPath: localPath ?? this.localPath,
    volume: volume ?? this.volume,
  );

  @override
  bool operator ==(Object other) =>
      other is MusicSelection &&
      other.track.id == track.id &&
      other.start == start &&
      other.duration == duration &&
      other.localPath == localPath &&
      other.volume == volume;

  @override
  int get hashCode => Object.hash(track.id, start, duration, localPath, volume);
}
