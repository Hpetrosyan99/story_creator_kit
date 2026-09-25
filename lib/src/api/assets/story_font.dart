import 'package:flutter/foundation.dart';

/// Loads a font before it is used, for fonts that are not bundled as assets.
///
/// Typically wraps a `FontLoader` fed with downloaded bytes. Must complete
/// before the font renders correctly; the editor awaits it before first use
/// and export waits for it too.
typedef StoryFontLoader = Future<void> Function();

/// A font offered in the text tool.
///
/// The host bundles or loads the font; the library only refers to it by
/// [family] (and [package] for fonts shipped in a package).
@immutable
class StoryFont {
  /// Creates a font entry.
  const StoryFont({
    required this.id,
    required this.label,
    this.family,
    this.package,
    this.loader,
    this.height = 1.2,
    this.letterSpacing = 0,
    this.uppercase = false,
  });

  /// The platform's default font.
  static const StoryFont system = StoryFont(id: 'system', label: 'Classic');

  /// Stable identifier, reported in `StoryMetadata`.
  final String id;

  /// Name shown in the font carousel.
  final String label;

  /// Font family name; `null` means the platform default.
  final String? family;

  /// Package that declares [family], if any.
  final String? package;

  /// Optional loader run before the font is first used.
  final StoryFontLoader? loader;

  /// Line height multiplier.
  final double height;

  /// Letter spacing in canvas units at the default text size.
  final double letterSpacing;

  /// Renders text in upper case (display styles).
  final bool uppercase;

  @override
  bool operator ==(Object other) => other is StoryFont && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
