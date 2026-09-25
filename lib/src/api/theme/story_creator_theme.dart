import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Visual styling of the story creator.
///
/// The library never reads the host's `ThemeData`; every colour and text style
/// used by its screens comes from here. The defaults are a dark UI with an
/// orange accent.
@immutable
class StoryCreatorTheme {
  /// Creates a theme. Every value has a dark-UI default.
  const StoryCreatorTheme({
    this.background = const Color(0xFF000000),
    this.surface = const Color(0xFF161616),
    this.surfaceVariant = const Color(0xFF262626),
    this.onSurface = const Color(0xFFFFFFFF),
    this.onSurfaceMuted = const Color(0xFF9A9A9A),
    this.outline = const Color(0xFF3A3A3A),
    this.accent = const Color(0xFFE4572E),
    this.onAccent = const Color(0xFFFFFFFF),
    this.error = const Color(0xFFFF453A),
    this.scrim = const Color(0x99000000),
    this.controlBackground = const Color(0x66000000),
    this.fontFamily,
    this.fontPackage,
    this.cornerRadius = 12,
    this.chipRadius = 20,
  });

  /// Page background behind the canvas.
  final Color background;

  /// Sheets, panels and list backgrounds.
  final Color surface;

  /// Chips, search fields, selected rows.
  final Color surfaceVariant;

  /// Primary text and icon colour.
  final Color onSurface;

  /// Secondary text (artists, durations, hints).
  final Color onSurfaceMuted;

  /// Borders and dividers.
  final Color outline;

  /// Accent for primary actions, selection and progress.
  final Color accent;

  /// Content drawn on top of [accent].
  final Color onAccent;

  /// Destructive actions and error text.
  final Color error;

  /// Dimming layer behind dialogs and the export overlay.
  final Color scrim;

  /// Round translucent background behind icon buttons on the canvas.
  final Color controlBackground;

  /// Font family for the library's own UI text. `null` uses the platform font.
  final String? fontFamily;

  /// Package that bundles [fontFamily], if any.
  final String? fontPackage;

  /// Corner radius of sheets, tiles and thumbnails.
  final double cornerRadius;

  /// Corner radius of chips and pill-shaped controls.
  final double chipRadius;

  /// Large titles (sheet headers).
  TextStyle get titleStyle => _style(17, FontWeight.w600, onSurface);

  /// Body text (track titles, dialog text).
  TextStyle get bodyStyle => _style(14, FontWeight.w500, onSurface);

  /// Secondary text (artists, durations).
  TextStyle get captionStyle => _style(12, FontWeight.w400, onSurfaceMuted);

  /// Small labels on chips and buttons.
  TextStyle get labelStyle => _style(12, FontWeight.w600, onSurface);

  TextStyle _style(double size, FontWeight weight, Color color) => TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color,
    fontFamily: fontFamily,
    package: fontPackage,
    decoration: TextDecoration.none,
  );

  /// Returns a copy with the given values replaced.
  StoryCreatorTheme copyWith({
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? onSurface,
    Color? onSurfaceMuted,
    Color? outline,
    Color? accent,
    Color? onAccent,
    Color? error,
    Color? scrim,
    Color? controlBackground,
    String? fontFamily,
    String? fontPackage,
    double? cornerRadius,
    double? chipRadius,
  }) => StoryCreatorTheme(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceVariant: surfaceVariant ?? this.surfaceVariant,
    onSurface: onSurface ?? this.onSurface,
    onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
    outline: outline ?? this.outline,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    error: error ?? this.error,
    scrim: scrim ?? this.scrim,
    controlBackground: controlBackground ?? this.controlBackground,
    fontFamily: fontFamily ?? this.fontFamily,
    fontPackage: fontPackage ?? this.fontPackage,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    chipRadius: chipRadius ?? this.chipRadius,
  );
}
