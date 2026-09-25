import 'dart:ui' as ui;

import '../../api/assets/story_filter.dart';
import '../../api/assets/story_font.dart';

/// Everything the painters need that is not in the `StoryDocument`: fonts by
/// id, decoded sticker images by id and filters by id.
///
/// Sticker images must be decoded before painting because a `Canvas` cannot
/// wait for an `ImageProvider`. Build one with `StoryPaintResources.load`
/// (see `story_paint_resources_loader.dart`).
class StoryPaintResources {
  /// Creates resources.
  StoryPaintResources({
    required List<StoryFont> fonts,
    required Map<String, ui.Image> stickerImages,
    required List<StoryFilter> filters,
  }) : _fonts = {for (final f in fonts) f.id: f},
       _defaultFont = fonts.isEmpty ? StoryFont.system : fonts.first,
       _stickers = stickerImages,
       _filters = {for (final f in filters) f.id: f};

  final Map<String, StoryFont> _fonts;
  final StoryFont _defaultFont;
  final Map<String, ui.Image> _stickers;
  final Map<String, StoryFilter> _filters;

  /// The font with [id], or the first configured font.
  StoryFont font(String id) => _fonts[id] ?? _defaultFont;

  /// The decoded sticker with [id], if loaded.
  ui.Image? sticker(String id) => _stickers[id];

  /// The filter with [id], or `null` for none/unknown.
  StoryFilter? filter(String? id) => id == null ? null : _filters[id];

  /// Registers a decoded sticker (editor loads them lazily).
  void putSticker(String id, ui.Image image) => _stickers[id] = image;
}
