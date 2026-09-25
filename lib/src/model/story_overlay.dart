import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'overlay_transform.dart';

/// How the text background is drawn.
enum TextBackgroundStyle {
  /// Text only.
  none,

  /// One rounded rectangle behind all lines, in the text colour; text is
  /// drawn in a contrasting colour.
  solid,

  /// One rounded rectangle, translucent black; text keeps its colour.
  translucent,

  /// A rounded highlight per line, hugging each line's width, in the text
  /// colour; text is drawn in a contrasting colour.
  highlight,
}

/// Style of a text overlay.
@immutable
class TextOverlayStyle {
  /// Creates a text style.
  const TextOverlayStyle({
    required this.fontId,
    required this.color,
    this.align = TextAlign.center,
    this.background = TextBackgroundStyle.none,
    this.fontSize = defaultFontSize,
  });

  /// Default font size in canvas units.
  static const double defaultFontSize = 88;

  /// `StoryFont.id`.
  final String fontId;

  /// Text colour (or background colour for [TextBackgroundStyle.solid] and
  /// [TextBackgroundStyle.highlight]).
  final Color color;

  /// Line alignment: left, center or right.
  final TextAlign align;

  /// Background style.
  final TextBackgroundStyle background;

  /// Font size in canvas units at scale 1.
  final double fontSize;

  /// Returns a copy with the given values replaced.
  TextOverlayStyle copyWith({
    String? fontId,
    Color? color,
    TextAlign? align,
    TextBackgroundStyle? background,
    double? fontSize,
  }) => TextOverlayStyle(
    fontId: fontId ?? this.fontId,
    color: color ?? this.color,
    align: align ?? this.align,
    background: background ?? this.background,
    fontSize: fontSize ?? this.fontSize,
  );

  @override
  bool operator ==(Object other) =>
      other is TextOverlayStyle &&
      other.fontId == fontId &&
      other.color == color &&
      other.align == align &&
      other.background == background &&
      other.fontSize == fontSize;

  @override
  int get hashCode => Object.hash(fontId, color, align, background, fontSize);
}

/// Something placed on top of the media: text, a sticker or an emoji.
///
/// Overlays are ordered bottom to top in `StoryDocument.overlays`.
@immutable
sealed class StoryOverlay {
  const StoryOverlay({required this.id, required this.transform});

  /// Unique within the document.
  final String id;

  /// Placement on the canvas.
  final OverlayTransform transform;

  /// Returns a copy with a new transform.
  StoryOverlay withTransform(OverlayTransform transform);
}

/// A text overlay.
final class TextOverlay extends StoryOverlay {
  /// Creates a text overlay.
  const TextOverlay({
    required super.id,
    required super.transform,
    required this.text,
    required this.style,
  });

  /// The text; may contain line breaks.
  final String text;

  /// Font, colour, alignment and background.
  final TextOverlayStyle style;

  @override
  TextOverlay withTransform(OverlayTransform transform) =>
      TextOverlay(id: id, transform: transform, text: text, style: style);

  /// Returns a copy with the given values replaced.
  TextOverlay copyWith({String? text, TextOverlayStyle? style}) => TextOverlay(
    id: id,
    transform: transform,
    text: text ?? this.text,
    style: style ?? this.style,
  );

  @override
  bool operator ==(Object other) =>
      other is TextOverlay &&
      other.id == id &&
      other.transform == transform &&
      other.text == text &&
      other.style == style;

  @override
  int get hashCode => Object.hash(id, transform, text, style);
}

/// A host-supplied sticker image.
final class StickerOverlay extends StoryOverlay {
  /// Creates a sticker overlay.
  const StickerOverlay({
    required super.id,
    required super.transform,
    required this.stickerId,
    this.baseSize = defaultBaseSize,
  });

  /// Default width of the longer sticker side in canvas units at scale 1.
  static const double defaultBaseSize = 360;

  /// `StorySticker.id`.
  final String stickerId;

  /// Length of the longer side in canvas units at scale 1.
  final double baseSize;

  @override
  StickerOverlay withTransform(OverlayTransform transform) => StickerOverlay(
    id: id,
    transform: transform,
    stickerId: stickerId,
    baseSize: baseSize,
  );

  @override
  bool operator ==(Object other) =>
      other is StickerOverlay &&
      other.id == id &&
      other.transform == transform &&
      other.stickerId == stickerId &&
      other.baseSize == baseSize;

  @override
  int get hashCode => Object.hash(id, transform, stickerId, baseSize);
}

/// An emoji, drawn with the platform emoji font.
final class EmojiOverlay extends StoryOverlay {
  /// Creates an emoji overlay.
  const EmojiOverlay({
    required super.id,
    required super.transform,
    required this.emoji,
    this.fontSize = defaultFontSize,
  });

  /// Default emoji size in canvas units at scale 1.
  static const double defaultFontSize = 220;

  /// The emoji (may be several code points).
  final String emoji;

  /// Size in canvas units at scale 1.
  final double fontSize;

  @override
  EmojiOverlay withTransform(OverlayTransform transform) => EmojiOverlay(
    id: id,
    transform: transform,
    emoji: emoji,
    fontSize: fontSize,
  );

  @override
  bool operator ==(Object other) =>
      other is EmojiOverlay &&
      other.id == id &&
      other.transform == transform &&
      other.emoji == emoji &&
      other.fontSize == fontSize;

  @override
  int get hashCode => Object.hash(id, transform, emoji, fontSize);
}
