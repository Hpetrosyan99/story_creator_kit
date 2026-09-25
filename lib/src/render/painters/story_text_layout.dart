import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../api/assets/story_font.dart';
import '../../model/story_overlay.dart';
import 'text_background_painter.dart';

/// Layout of one text overlay in canvas units.
///
/// The same layout is used by the editor's live canvas, the text editing
/// field (which is laid out at [maxTextWidth] in canvas units and scaled to
/// the screen) and the export rasterizer, so line breaks are identical
/// everywhere. OS text scaling never applies: overlay text is content, not
/// UI chrome.
///
/// Layouts are cached; call [clearCache] after fonts finish loading.
class StoryTextLayout {
  StoryTextLayout._({
    required this.painter,
    required this.style,
    required this.lineRects,
  });

  /// Width available to the text, in canvas units, before wrapping.
  static const double maxTextWidth = 900;

  /// Horizontal padding between the text and the overlay bounds, as a
  /// fraction of the font size.
  static const double horizontalPaddingFactor = 0.32;

  /// Vertical padding between the text and the overlay bounds, as a
  /// fraction of the font size.
  static const double verticalPaddingFactor = 0.16;

  /// Corner radius of backgrounds, as a fraction of the font size.
  static const double radiusFactor = 0.26;

  static const int _cacheSize = 48;
  static final LinkedHashMap<_LayoutKey, StoryTextLayout> _cache =
      LinkedHashMap();
  static bool _listening = false;

  /// Lays out [overlay] with [font] (cached).
  factory StoryTextLayout.of(TextOverlay overlay, StoryFont font) =>
      StoryTextLayout.forText(overlay.text, overlay.style, font);

  /// Lays out [text] with [style] and [font] (cached).
  factory StoryTextLayout.forText(
    String text,
    TextOverlayStyle style,
    StoryFont font,
  ) {
    _listenToSystemFonts();
    final key = _LayoutKey(text, style, font);
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    final layout = StoryTextLayout._create(text, style, font);
    _cache[key] = layout;
    while (_cache.length > _cacheSize) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest)!.painter.dispose();
    }
    return layout;
  }

  /// Drops every cached layout (e.g. after a font loaded).
  static void clearCache() {
    for (final layout in _cache.values) {
      layout.painter.dispose();
    }
    _cache.clear();
  }

  static void _listenToSystemFonts() {
    if (_listening) {
      return;
    }
    _listening = true;
    PaintingBinding.instance.systemFonts.addListener(clearCache);
  }

  /// The laid-out text, positioned at [textOffset] inside the bounds.
  final TextPainter painter;

  /// The overlay style.
  final TextOverlayStyle style;

  /// Per-line highlight rectangles in overlay-local coordinates (top-left of
  /// the bounds is the origin); `null` entries are empty lines.
  final List<Rect?> lineRects;

  /// Horizontal padding in canvas units.
  double get horizontalPadding => style.fontSize * horizontalPaddingFactor;

  /// Vertical padding in canvas units.
  double get verticalPadding => style.fontSize * verticalPaddingFactor;

  /// Corner radius of the background in canvas units.
  double get radius => style.fontSize * radiusFactor;

  /// Where the text starts inside the bounds.
  Offset get textOffset => Offset(horizontalPadding, verticalPadding);

  /// Width of the longest line.
  double get textWidth => painter.width;

  /// Size of the overlay at scale 1, before rotation.
  Size get size => Size(
    painter.width + 2 * horizontalPadding,
    painter.height + 2 * verticalPadding,
  );

  /// Paints background and text with the bounds' top-left at [origin].
  void paint(Canvas canvas, Offset origin) {
    TextBackgroundPainter.paint(canvas, this, origin);
    painter.paint(canvas, origin + textOffset);
  }

  /// The text as rendered (upper-cased for display fonts).
  static String displayText(String text, StoryFont font) {
    if (!font.uppercase) {
      return text;
    }
    final upper = text.toUpperCase();
    // Keep offsets stable for the editing field (e.g. 'ß' → 'SS').
    return upper.length == text.length ? upper : text;
  }

  /// The colour the glyphs are drawn in.
  static Color foregroundColor(TextOverlayStyle style) =>
      switch (style.background) {
        TextBackgroundStyle.solid ||
        TextBackgroundStyle.highlight => contrastColor(style.color),
        TextBackgroundStyle.none ||
        TextBackgroundStyle.translucent => style.color,
      };

  /// Black or white, whichever reads better on [background].
  static Color contrastColor(Color background) =>
      background.computeLuminance() > 0.45
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);

  /// Text style of the glyphs, in canvas units. Pass [color] to override the
  /// glyph colour (the editing field draws transparent glyphs).
  static TextStyle textStyle(
    TextOverlayStyle style,
    StoryFont font, {
    Color? color,
  }) => TextStyle(
    color: color ?? foregroundColor(style),
    fontSize: style.fontSize,
    fontFamily: font.family,
    package: font.package,
    height: font.height,
    letterSpacing:
        font.letterSpacing * style.fontSize / TextOverlayStyle.defaultFontSize,
    decoration: TextDecoration.none,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Strut that fixes the line height, so emoji or fallback glyphs do not
  /// change line spacing.
  static StrutStyle strutStyle(TextOverlayStyle style, StoryFont font) =>
      StrutStyle(
        fontFamily: font.family,
        package: font.package,
        fontSize: style.fontSize,
        height: font.height,
        leadingDistribution: TextLeadingDistribution.even,
        forceStrutHeight: true,
      );

  factory StoryTextLayout._create(
    String text,
    TextOverlayStyle style,
    StoryFont font,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: displayText(text, font),
        style: textStyle(style, font),
      ),
      textAlign: style.align,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      strutStyle: strutStyle(style, font),
      textWidthBasis: TextWidthBasis.longestLine,
    )..layout(maxWidth: maxTextWidth);
    final padH = style.fontSize * horizontalPaddingFactor;
    final padV = style.fontSize * verticalPaddingFactor;
    final rects = <Rect?>[
      for (final ui.LineMetrics line in painter.computeLineMetrics())
        if (line.width <= 0.5)
          null
        else
          Rect.fromLTRB(
            line.left,
            padV + line.baseline - line.ascent,
            line.left + line.width + 2 * padH,
            padV + line.baseline + line.descent,
          ),
    ];
    return StoryTextLayout._(painter: painter, style: style, lineRects: rects);
  }
}

class _LayoutKey {
  const _LayoutKey(this.text, this.style, this.font);

  final String text;
  final TextOverlayStyle style;
  final StoryFont font;

  @override
  bool operator ==(Object other) =>
      other is _LayoutKey &&
      other.text == text &&
      other.style == style &&
      other.font.id == font.id &&
      other.font.family == font.family &&
      other.font.package == font.package &&
      other.font.height == font.height &&
      other.font.letterSpacing == font.letterSpacing &&
      other.font.uppercase == font.uppercase;

  @override
  int get hashCode => Object.hash(
    text,
    style,
    font.id,
    font.family,
    font.package,
    font.height,
    font.letterSpacing,
    font.uppercase,
  );
}
