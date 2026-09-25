import 'package:flutter/foundation.dart';

/// A colour filter applied to the photo or video.
///
/// [matrix] is a 4×5 row-major colour matrix with the same semantics as
/// Flutter's `ColorFilter.matrix`: the fifth column is an offset in the
/// 0–255 range. The same matrix is applied natively when exporting video, so
/// preview and export match.
@immutable
class StoryFilter {
  /// Creates a filter. [matrix] must have 20 entries; this is checked when
  /// the creator opens.
  const StoryFilter({
    required this.id,
    required this.label,
    required this.matrix,
  });

  /// Stable identifier, reported in `StoryMetadata`.
  final String id;

  /// Name shown in the filter strip.
  final String label;

  /// 4×5 colour matrix.
  final List<double> matrix;

  /// Whether this filter leaves colours unchanged.
  bool get isIdentity => listEquals(matrix, _identity);

  /// No filter.
  static const StoryFilter original = StoryFilter(
    id: 'original',
    label: 'Original',
    matrix: _identity,
  );

  /// The built-in filters, starting with [original].
  static const List<StoryFilter> defaults = [
    original,
    StoryFilter(
      id: 'warm',
      label: 'Warm',
      matrix: [
        1.10, 0, 0, 0, 10, //
        0, 1.02, 0, 0, 4,
        0, 0, 0.88, 0, -6,
        0, 0, 0, 1, 0,
      ],
    ),
    StoryFilter(
      id: 'cool',
      label: 'Cool',
      matrix: [
        0.90, 0, 0, 0, -4, //
        0, 1.00, 0, 0, 2,
        0, 0, 1.12, 0, 12,
        0, 0, 0, 1, 0,
      ],
    ),
    StoryFilter(
      id: 'vivid',
      label: 'Vivid',
      matrix: [
        1.30, -0.15, -0.15, 0, 0, //
        -0.15, 1.30, -0.15, 0, 0,
        -0.15, -0.15, 1.30, 0, 0,
        0, 0, 0, 1, 0,
      ],
    ),
    StoryFilter(
      id: 'fade',
      label: 'Fade',
      matrix: [
        0.85, 0.05, 0.05, 0, 24, //
        0.05, 0.85, 0.05, 0, 24,
        0.05, 0.05, 0.85, 0, 24,
        0, 0, 0, 1, 0,
      ],
    ),
    StoryFilter(
      id: 'mono',
      label: 'Mono',
      matrix: [
        0.2126, 0.7152, 0.0722, 0, 0, //
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0, 0, 0, 1, 0,
      ],
    ),
    StoryFilter(
      id: 'noir',
      label: 'Noir',
      matrix: [
        0.30, 0.90, 0.10, 0, -40, //
        0.30, 0.90, 0.10, 0, -40,
        0.30, 0.90, 0.10, 0, -40,
        0, 0, 0, 1, 0,
      ],
    ),
    StoryFilter(
      id: 'sepia',
      label: 'Sepia',
      matrix: [
        0.393, 0.769, 0.189, 0, 0, //
        0.349, 0.686, 0.168, 0, 0,
        0.272, 0.534, 0.131, 0, 0,
        0, 0, 0, 1, 0,
      ],
    ),
  ];

  static const List<double> _identity = [
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ];

  @override
  bool operator ==(Object other) => other is StoryFilter && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
