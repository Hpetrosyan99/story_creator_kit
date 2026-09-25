import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../assets/story_filter.dart';
import '../assets/story_font.dart';
import '../assets/story_sticker.dart';

/// Editor tools and the choices they offer.
@immutable
class EditorOptions {
  /// Creates editor options.
  const EditorOptions({
    this.enableText = true,
    this.enableDrawing = true,
    this.enableStickers = true,
    this.enableFilters = true,
    this.enableMusic = true,
    this.enableTrim = true,
    this.enableAudioMix = true,
    this.fonts = const [StoryFont.system],
    this.textColors = defaultColors,
    this.brushColors = defaultColors,
    this.brushSizes = const [8, 16, 28, 44],
    this.stickers = const [],
    this.emojis = defaultEmojis,
    this.filters = StoryFilter.defaults,
    this.maxOverlays = 30,
    this.confirmDiscard = true,
  });

  /// Show the text tool.
  final bool enableText;

  /// Show the drawing tool.
  final bool enableDrawing;

  /// Show the sticker and emoji tool.
  final bool enableStickers;

  /// Show filters.
  final bool enableFilters;

  /// Show the music tool. Also needs `StoryCreatorConfig.musicProvider`.
  final bool enableMusic;

  /// Show the video trimmer.
  final bool enableTrim;

  /// Show original-audio and music volume controls.
  final bool enableAudioMix;

  /// Fonts in the text tool, first one is the default. Must not be empty.
  final List<StoryFont> fonts;

  /// Text colour palette.
  final List<Color> textColors;

  /// Brush colour palette.
  final List<Color> brushColors;

  /// Brush widths in canvas units (the canvas is 1080 wide).
  final List<double> brushSizes;

  /// Stickers offered by the host.
  final List<StorySticker> stickers;

  /// Emoji offered in the sticker picker.
  final List<String> emojis;

  /// Filters, first one is the default.
  final List<StoryFilter> filters;

  /// Maximum number of text and sticker overlays.
  final int maxOverlays;

  /// Ask before discarding edits.
  final bool confirmDiscard;

  /// Default colour palette.
  static const List<Color> defaultColors = [
    Color(0xFFFFFFFF),
    Color(0xFF000000),
    Color(0xFFE4572E),
    Color(0xFFFFC53D),
    Color(0xFF52C41A),
    Color(0xFF13C2C2),
    Color(0xFF1677FF),
    Color(0xFF722ED1),
    Color(0xFFEB2F96),
    Color(0xFF8C8C8C),
  ];

  /// Default emoji set.
  static const List<String> defaultEmojis = [
    '😀', '😂', '😍', '🥳', '😎', '🤩', '😭', '😡', //
    '👍', '👏', '🙏', '💪', '🔥', '✨', '💯', '❤️',
    '💔', '🎉', '🎶', '🌙', '☀️', '🌈', '🌸', '🍕',
    '☕', '⚽', '🚀', '📍', '✈️', '🐶', '🐱', '👀',
  ];
}
