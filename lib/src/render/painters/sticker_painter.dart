import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../model/story_overlay.dart';

/// Paints sticker images and emoji, and measures them.
abstract final class StickerPainter {
  static const int _emojiCacheSize = 32;
  static final LinkedHashMap<(String, double), TextPainter> _emoji =
      LinkedHashMap();

  /// Size of a sticker at scale 1: the longer side is
  /// [StickerOverlay.baseSize]. A square while the image is not decoded.
  static Size stickerSize(StickerOverlay overlay, ui.Image? image) {
    final base = overlay.baseSize;
    if (image == null || image.width == 0 || image.height == 0) {
      return Size(base, base);
    }
    final aspect = image.width / image.height;
    return aspect >= 1 ? Size(base, base / aspect) : Size(base * aspect, base);
  }

  /// Paints [image] filling [size] with its top-left at [origin]. Nothing is
  /// drawn while the image is not decoded.
  static void paintSticker(
    Canvas canvas,
    ui.Image? image,
    Offset origin,
    Size size,
  ) {
    if (image == null) {
      return;
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      origin & size,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..isAntiAlias = true,
    );
  }

  /// Laid-out emoji (cached).
  static TextPainter emojiPainter(EmojiOverlay overlay) {
    final key = (overlay.emoji, overlay.fontSize);
    final cached = _emoji.remove(key);
    if (cached != null) {
      _emoji[key] = cached;
      return cached;
    }
    final painter = TextPainter(
      text: TextSpan(
        text: overlay.emoji,
        style: TextStyle(
          fontSize: overlay.fontSize,
          height: 1.15,
          color: const Color(0xFF000000),
          decoration: TextDecoration.none,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout();
    _emoji[key] = painter;
    while (_emoji.length > _emojiCacheSize) {
      _emoji.remove(_emoji.keys.first)!.dispose();
    }
    return painter;
  }

  /// Size of an emoji at scale 1.
  static Size emojiSize(EmojiOverlay overlay) => emojiPainter(overlay).size;

  /// Paints an emoji with its top-left at [origin].
  static void paintEmoji(Canvas canvas, EmojiOverlay overlay, Offset origin) =>
      emojiPainter(overlay).paint(canvas, origin);
}
