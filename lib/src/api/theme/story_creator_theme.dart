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
    this.background = const Color(0xFF141414),
    this.surface = const Color(0xFF1F1F21),
    this.surfaceVariant = const Color(0xFF2D2D30),
    this.onSurface = const Color(0xFFFFFFFF),
    this.onSurfaceSecondary = const Color(0xFFC2C2C2),
    this.onSurfaceMuted = const Color(0xFF737373),
    this.outline = const Color(0xFF525257),
    this.accent = const Color(0xFFCF5835),
    this.onAccent = const Color(0xFFFFFFFF),
    this.error = const Color(0xFFD92D20),
    this.scrim = const Color(0x66000000),
    this.controlBackground = const Color(0x661F1F21),
    this.pillBackground = const Color(0x80141414),
    this.isLiquidGlassEnabled = false,
    this.fontFamily,
    this.fontPackage,
    this.cornerRadius = 16,
    this.chipRadius = 999,
  });

  /// Page background behind the canvas.
  final Color background;

  /// Sheets, panels, list highlights and the music chip.
  final Color surface;

  /// Raised surfaces: unselected chips, the gallery camera tile.
  final Color surfaceVariant;

  /// Primary text and icon colour.
  final Color onSurface;

  /// Secondary text (the unselected Video/Photo option).
  final Color onSurfaceSecondary;

  /// Muted text (artists, durations, placeholders).
  final Color onSurfaceMuted;

  /// Borders and dividers.
  final Color outline;

  /// Accent for primary actions, selection and progress.
  final Color accent;

  /// Content drawn on top of [accent].
  final Color onAccent;

  /// Destructive actions, error text and the recording shutter.
  final Color error;

  /// Dimming layer behind dialogs, the export overlay and the segment
  /// selector.
  final Color scrim;

  /// Round translucent background behind the 44 px canvas buttons
  /// (close, confirm).
  final Color controlBackground;

  /// Translucent background of pills on the canvas (Video/Photo toggle,
  /// lens switch, save button).
  final Color pillBackground;

  /// Renders the translucent controls on the canvas (close/confirm buttons,
  /// Video/Photo toggle, lens switch, music chip) as "liquid
  /// glass": a frosted, saturated blur of what is behind them with a light
  /// rim and sheen. When `false` they use the flat [controlBackground] /
  /// [pillBackground] fills.
  final bool isLiquidGlassEnabled;

  /// Font family for the library's own UI text. `null` uses the platform font.
  final String? fontFamily;

  /// Package that bundles [fontFamily], if any.
  final String? fontPackage;

  /// Corner radius of the story canvas card and thumbnails.
  final double cornerRadius;

  /// Corner radius of chips and pill-shaped controls.
  final double chipRadius;

  /// Emphasised body text, 16/22 semibold (titles, selected mode).
  TextStyle get titleStyle => _style(16, 22, FontWeight.w600, onSurface);

  /// Body text, 16/22 regular (search field, unselected mode).
  TextStyle get bodyLargeStyle => _style(16, 22, FontWeight.w400, onSurface);

  /// Body text, 14/20 regular (track titles, dialog text).
  TextStyle get bodyStyle => _style(14, 20, FontWeight.w400, onSurface);

  /// Emphasised small body text, 14/20 semibold (album selector).
  TextStyle get bodyEmphasisStyle => _style(14, 20, FontWeight.w600, onSurface);

  /// Secondary text, 12/16 regular muted (artists, durations).
  TextStyle get captionStyle => _style(12, 16, FontWeight.w400, onSurfaceMuted);

  /// Small labels, 12/16 regular (chips, buttons).
  TextStyle get labelStyle => _style(12, 16, FontWeight.w400, onSurface);

  TextStyle _style(double size, double line, FontWeight weight, Color color) =>
      TextStyle(
        fontSize: size,
        height: line / size,
        fontWeight: weight,
        // Variable fonts (e.g. Onest) need the axis set explicitly.
        fontVariations: [FontVariation.weight(weight.value.toDouble())],
        color: color,
        fontFamily: fontFamily,
        package: fontPackage,
        decoration: TextDecoration.none,
        leadingDistribution: TextLeadingDistribution.even,
      );

  /// Returns a copy with the given values replaced.
  StoryCreatorTheme copyWith({
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? onSurface,
    Color? onSurfaceSecondary,
    Color? onSurfaceMuted,
    Color? outline,
    Color? accent,
    Color? onAccent,
    Color? error,
    Color? scrim,
    Color? controlBackground,
    Color? pillBackground,
    bool? isLiquidGlassEnabled,
    String? fontFamily,
    String? fontPackage,
    double? cornerRadius,
    double? chipRadius,
  }) => StoryCreatorTheme(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceVariant: surfaceVariant ?? this.surfaceVariant,
    onSurface: onSurface ?? this.onSurface,
    onSurfaceSecondary: onSurfaceSecondary ?? this.onSurfaceSecondary,
    onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
    outline: outline ?? this.outline,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    error: error ?? this.error,
    scrim: scrim ?? this.scrim,
    controlBackground: controlBackground ?? this.controlBackground,
    pillBackground: pillBackground ?? this.pillBackground,
    isLiquidGlassEnabled: isLiquidGlassEnabled ?? this.isLiquidGlassEnabled,
    fontFamily: fontFamily ?? this.fontFamily,
    fontPackage: fontPackage ?? this.fontPackage,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    chipRadius: chipRadius ?? this.chipRadius,
  );
}
