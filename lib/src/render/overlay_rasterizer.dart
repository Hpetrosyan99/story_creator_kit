import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../core/story_canvas.dart';

/// Draws into a canvas whose units are story canvas units (1080×1920).
typedef CanvasPainter = void Function(Canvas canvas);

/// Rasterises story paint code at output resolution.
///
/// Recording and `Picture.toImage` run on the root isolate (dart:ui drawing
/// is root-isolate only). The asynchronous `toImage` is used on purpose:
/// `toImageSync` can return a magenta image on iOS after the app returns
/// from the background (flutter/flutter#191255). Rasterising waits until the
/// app is in the foreground.
class OverlayRasterizer {
  /// Creates a rasterizer producing [width]×[height] images.
  const OverlayRasterizer({
    this.width = StoryCanvas.outputWidth,
    this.height = StoryCanvas.outputHeight,
  });

  /// Output width in pixels.
  final int width;

  /// Output height in pixels.
  final int height;

  /// Paints [paint] scaled from canvas units to the output size and returns
  /// the image. Dispose it after use.
  Future<ui.Image> rasterize(CanvasPainter paint) async {
    await waitForForeground();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    )..scale(width / StoryCanvas.width, height / StoryCanvas.height);
    paint(canvas);
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  /// PNG bytes of [image] (keeps transparency).
  static Future<Uint8List> encodePng(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('PNG encoding returned no data.');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  /// Straight (non-premultiplied) RGBA8888 bytes of [image].
  static Future<Uint8List> encodeRgba(ui.Image image) async {
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (data == null) {
      throw StateError('RGBA readback returned no data.');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  /// Completes when the app is resumed (immediately when it already is, or
  /// when the lifecycle is unknown, e.g. in tests).
  static Future<void> waitForForeground() async {
    final binding = WidgetsBinding.instance;
    final state = binding.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) {
      return;
    }
    final completer = Completer<void>();
    final listener = AppLifecycleListener(
      onResume: () {
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );
    try {
      await completer.future;
    } finally {
      listener.dispose();
    }
  }
}
