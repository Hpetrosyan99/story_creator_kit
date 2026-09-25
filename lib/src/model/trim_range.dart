import 'package:flutter/foundation.dart';

/// The part of the source video that is kept.
@immutable
class TrimRange {
  /// Creates a range. [end] must be after [start].
  // Not const: the assert compares Durations, which const evaluation cannot.
  // ignore: prefer_const_constructors_in_immutables
  TrimRange(this.start, this.end)
    : assert(start < end, 'Trim end must be after start.');

  /// Start in the source video.
  final Duration start;

  /// End in the source video.
  final Duration end;

  /// Kept length.
  Duration get duration => end - start;

  /// Whether [position] is inside the range.
  bool contains(Duration position) => position >= start && position <= end;

  @override
  bool operator ==(Object other) =>
      other is TrimRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TrimRange($start–$end)';
}
