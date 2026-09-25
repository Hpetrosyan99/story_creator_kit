import 'dart:ui';

import 'package:flutter/foundation.dart';

/// How the media sits on the 1080×1920 canvas.
///
/// The media is first fitted *inside* the canvas (contain), then scaled by
/// [scale] around the canvas centre and moved by [offset]. See
/// `StoryCanvas.mediaRect`.
@immutable
class MediaPlacement {
  /// Creates a placement.
  const MediaPlacement({this.scale = 1, this.offset = Offset.zero});

  /// Scale relative to the contain-fit size.
  final double scale;

  /// Translation of the media centre from the canvas centre, canvas units.
  final Offset offset;

  /// Returns a copy with the given values replaced.
  MediaPlacement copyWith({double? scale, Offset? offset}) =>
      MediaPlacement(scale: scale ?? this.scale, offset: offset ?? this.offset);

  @override
  bool operator ==(Object other) =>
      other is MediaPlacement && other.scale == scale && other.offset == offset;

  @override
  int get hashCode => Object.hash(scale, offset);
}

/// Canvas background behind media that does not fill the canvas: a vertical
/// gradient from [top] to [bottom].
@immutable
class StoryBackground {
  /// Creates a background.
  const StoryBackground({
    this.top = const Color(0xFF000000),
    this.bottom = const Color(0xFF000000),
  });

  /// Colour at the top edge.
  final Color top;

  /// Colour at the bottom edge.
  final Color bottom;

  @override
  bool operator ==(Object other) =>
      other is StoryBackground && other.top == top && other.bottom == bottom;

  @override
  int get hashCode => Object.hash(top, bottom);
}
