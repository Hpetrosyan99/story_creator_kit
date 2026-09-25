import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../api/assets/story_font.dart';
import '../../api/assets/story_sticker.dart';
import '../../api/config/editor_options.dart';
import '../../api/errors/story_exception.dart';
import '../../model/story_document.dart';
import '../../model/story_overlay.dart';
import 'story_paint_resources.dart';
import 'story_text_layout.dart';

/// Resources with fonts and filters from [options] and no stickers decoded
/// yet.
StoryPaintResources createStoryPaintResources(EditorOptions options) =>
    StoryPaintResources(
      fonts: options.fonts,
      stickerImages: {},
      filters: options.filters,
    );

/// Runs the loaders of fonts used in [document] and decodes its stickers
/// into [resources]. Export awaits this before painting.
///
/// Throws [StoryException] (`mediaUnavailable`) when a font loader fails, a
/// sticker id is unknown or a sticker image cannot be decoded.
Future<void> ensureStoryPaintResources(
  StoryPaintResources resources,
  StoryDocument document,
  EditorOptions options, {
  ImageConfiguration configuration = ImageConfiguration.empty,
}) async {
  final pending = <Future<void>>[];
  final fontIds = {
    for (final overlay in document.overlays)
      if (overlay is TextOverlay) overlay.style.fontId,
  };
  for (final id in fontIds) {
    final font = _fontById(options.fonts, id);
    if (font != null && font.loader != null) {
      pending.add(loadStoryFont(font));
    }
  }
  final stickerIds = {
    for (final overlay in document.overlays)
      if (overlay is StickerOverlay) overlay.stickerId,
  };
  for (final id in stickerIds) {
    if (resources.sticker(id) != null) {
      continue;
    }
    final sticker = _stickerById(options.stickers, id);
    if (sticker == null) {
      throw StoryException(
        StoryErrorCode.mediaUnavailable,
        'Sticker "$id" is not in EditorOptions.stickers.',
      );
    }
    pending.add(
      loadStorySticker(resources, sticker, configuration: configuration),
    );
  }
  await Future.wait(pending);
}

final Map<String, Future<void>> _fontLoads = {};

/// Runs [font]'s loader once per font id; later calls reuse the result.
/// Clears cached text layouts when the font becomes available.
///
/// Throws [StoryException] (`mediaUnavailable`) when the loader fails; a
/// later call tries again.
Future<void> loadStoryFont(StoryFont font) {
  final loader = font.loader;
  if (loader == null) {
    return Future.value();
  }
  return _fontLoads[font.id] ??= () async {
    try {
      await loader();
      _loadedFonts.add(font.id);
      StoryTextLayout.clearCache();
    } on Object catch (e, s) {
      _fontLoads.removeWhere((id, _) => id == font.id);
      throw StoryException(
        StoryErrorCode.mediaUnavailable,
        'Font "${font.id}" could not be loaded.',
        e,
        s,
      );
    }
  }();
}

/// Whether [font] can be painted now (no loader, or its loader finished).
bool isStoryFontReady(StoryFont font) =>
    font.loader == null || _loadedFonts.contains(font.id);

final Set<String> _loadedFonts = {};

/// Forgets which fonts were loaded (tests).
@visibleForTesting
void resetStoryFontLoads() {
  _fontLoads.clear();
  _loadedFonts.clear();
}

final Expando<Map<String, Future<void>>> _stickerLoads = Expando(
  'storyStickerLoads',
);

/// Decodes [sticker] into [resources] once; later calls reuse the result.
///
/// Throws [StoryException] (`mediaUnavailable`) when decoding fails; a later
/// call tries again.
Future<void> loadStorySticker(
  StoryPaintResources resources,
  StorySticker sticker, {
  ImageConfiguration configuration = ImageConfiguration.empty,
}) {
  if (resources.sticker(sticker.id) != null) {
    return Future.value();
  }
  final loads = _stickerLoads[resources] ??= {};
  return loads[sticker.id] ??= () async {
    try {
      final image = await decodeStoryImage(sticker.image, configuration);
      resources.putSticker(sticker.id, image);
    } on Object catch (e, s) {
      loads.removeWhere((id, _) => id == sticker.id);
      throw StoryException(
        StoryErrorCode.mediaUnavailable,
        'Sticker "${sticker.id}" could not be decoded.',
        e,
        s,
      );
    }
  }();
}

/// Resolves [provider] and returns its first frame. The caller owns the
/// returned image.
Future<ui.Image> decodeStoryImage(
  ImageProvider provider, [
  ImageConfiguration configuration = ImageConfiguration.empty,
]) {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(configuration);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      if (!completer.isCompleted) {
        completer.complete(info.image.clone());
      }
      info.dispose();
    },
    onError: (error, stackTrace) {
      stream.removeListener(listener);
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    },
  );
  stream.addListener(listener);
  return completer.future;
}

StoryFont? _fontById(List<StoryFont> fonts, String id) {
  for (final font in fonts) {
    if (font.id == id) {
      return font;
    }
  }
  return null;
}

StorySticker? _stickerById(List<StorySticker> stickers, String id) {
  for (final sticker in stickers) {
    if (sticker.id == id) {
      return sticker;
    }
  }
  return null;
}
