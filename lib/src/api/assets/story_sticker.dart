import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// A sticker offered in the sticker picker.
///
/// Any [ImageProvider] works (asset, file, network, memory). Network images
/// must be reachable when the user exports.
@immutable
class StorySticker {
  /// Creates a sticker entry.
  const StorySticker({
    required this.id,
    required this.image,
    required this.label,
  });

  /// Stable identifier, reported in `StoryMetadata`.
  final String id;

  /// The sticker image; transparent PNG or WebP recommended.
  final ImageProvider image;

  /// Accessible name of the sticker.
  final String label;

  @override
  bool operator ==(Object other) => other is StorySticker && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
