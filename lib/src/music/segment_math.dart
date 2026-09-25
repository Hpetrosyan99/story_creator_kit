import 'package:flutter/foundation.dart';

/// A part of a track: where it starts and how long it plays.
@immutable
class MusicSegment {
  /// Creates a segment.
  const MusicSegment({required this.start, required this.duration});

  /// Offset into the track.
  final Duration start;

  /// Length of the segment.
  final Duration duration;

  /// Offset where the segment ends.
  Duration get end => start + duration;

  @override
  bool operator ==(Object other) =>
      other is MusicSegment &&
      other.start == start &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(start, duration);

  @override
  String toString() => 'MusicSegment($start, $duration)';
}

/// Clamps a segment of [segmentLength] starting at [start] into a track of
/// [trackDuration].
///
/// * The start is clamped to `[0, trackDuration − segmentLength]`, so the
///   segment never runs past the end of the track.
/// * When the track is shorter than [segmentLength] (or [segmentLength] is not
///   positive), the segment covers the whole track: the start is zero and the
///   duration is [trackDuration]. The selection then carries the shorter
///   duration and the exporter plays the music only for that long; the rest
///   of the story is silent rather than looping the track.
/// * When [trackDuration] is unknown (zero or negative), the start is zero and
///   the duration is [segmentLength] (never negative).
MusicSegment clampMusicSegment({
  required Duration start,
  required Duration segmentLength,
  required Duration trackDuration,
}) {
  if (trackDuration <= Duration.zero) {
    return MusicSegment(
      start: Duration.zero,
      duration: segmentLength < Duration.zero ? Duration.zero : segmentLength,
    );
  }
  final length = segmentLength <= Duration.zero || segmentLength > trackDuration
      ? trackDuration
      : segmentLength;
  final maxStart = trackDuration - length;
  final clamped = start < Duration.zero
      ? Duration.zero
      : start > maxStart
      ? maxStart
      : start;
  return MusicSegment(start: clamped, duration: length);
}

/// The fraction (0–1) of [trackDuration] at [position].
double musicFractionOf(Duration position, Duration trackDuration) {
  if (trackDuration <= Duration.zero) {
    return 0;
  }
  return (position.inMicroseconds / trackDuration.inMicroseconds).clamp(0, 1);
}

/// The position at [fraction] (clamped to 0–1) of [trackDuration].
Duration musicPositionAt(double fraction, Duration trackDuration) => Duration(
  microseconds: (trackDuration.inMicroseconds * fraction.clamp(0, 1)).round(),
);

/// Formats [value] as `m:ss`, e.g. `3:07`. Negative values show as `0:00`.
String formatMusicTime(Duration value) {
  final seconds = value.isNegative ? 0 : value.inSeconds;
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$rest';
}
