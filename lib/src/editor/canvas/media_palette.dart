import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_color_utilities/material_color_utilities.dart';

import '../../model/media_placement.dart';

/// Derives the canvas background gradient from the media's colours: the
/// top and bottom halves of a small copy are quantized and scored
/// separately, then darkened so overlays stay legible.
abstract final class MediaPalette {
  /// Width images are decoded at before quantizing.
  static const int sampleWidth = 48;

  /// Highest HCT tone of the background colours.
  static const double maxTone = 32;

  /// Background from encoded image bytes (JPEG, PNG, …).
  static Future<StoryBackground> fromEncoded(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: sampleWidth,
    );
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final data = await image.toByteData();
        if (data == null) {
          return const StoryBackground();
        }
        return await fromRgba(data, image.width, image.height);
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  /// Background from raw RGBA pixels.
  static Future<StoryBackground> fromRgba(
    ByteData rgba,
    int width,
    int height,
  ) async {
    final half = math.max(1, height ~/ 2);
    final top = <int>[];
    final bottom = <int>[];
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        final a = rgba.getUint8(i + 3);
        if (a < 128) {
          continue;
        }
        final argb =
            (0xFF << 24) |
            (rgba.getUint8(i) << 16) |
            (rgba.getUint8(i + 1) << 8) |
            rgba.getUint8(i + 2);
        (y < half ? top : bottom).add(argb);
      }
    }
    final topColor = await _dominant(top);
    final bottomColor = await _dominant(bottom.isEmpty ? top : bottom);
    return StoryBackground(
      top: ui.Color(_darken(topColor)),
      bottom: ui.Color(_darken(bottomColor)),
    );
  }

  static Future<int> _dominant(List<int> pixels) async {
    if (pixels.isEmpty) {
      return 0xFF000000;
    }
    final result = await QuantizerCelebi().quantize(pixels, 16);
    final counts = result.colorToCount;
    if (counts.isEmpty) {
      return pixels.first;
    }
    var mostCommon = counts.keys.first;
    for (final entry in counts.entries) {
      if (entry.value > counts[mostCommon]!) {
        mostCommon = entry.key;
      }
    }
    final scored = Score.score(
      counts,
      desired: 1,
      fallbackColorARGB: mostCommon,
      filter: false,
    );
    return scored.isEmpty ? mostCommon : scored.first;
  }

  static int _darken(int argb) {
    final hct = Hct.fromInt(argb);
    if (hct.tone > maxTone) {
      hct.tone = maxTone;
    }
    return hct.toInt();
  }
}
