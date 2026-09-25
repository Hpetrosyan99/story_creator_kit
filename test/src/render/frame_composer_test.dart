import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/src/api/assets/story_filter.dart';
import 'package:story_creator_kit/src/api/assets/story_font.dart';
import 'package:story_creator_kit/src/api/result/story_result.dart';
import 'package:story_creator_kit/src/model/media_placement.dart';
import 'package:story_creator_kit/src/model/story_document.dart';
import 'package:story_creator_kit/src/model/story_media.dart';
import 'package:story_creator_kit/src/render/frame_composer.dart';
import 'package:story_creator_kit/src/render/overlay_rasterizer.dart';
import 'package:story_creator_kit/src/render/painters/story_paint_resources.dart';

final _resources = StoryPaintResources(
  fonts: const [StoryFont.system],
  stickerImages: {},
  filters: StoryFilter.defaults,
);

const _background = StoryBackground(
  top: Color(0xFF00FF00),
  bottom: Color(0xFF00FF00),
);

/// Left half red, right half blue.
Future<String> _halvesPng(Directory dir, int w, int h) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
    ..drawRect(
      ui.Rect.fromLTWH(0, 0, w / 2, h.toDouble()),
      ui.Paint()..color = const Color(0xFFFF0000),
    )
    ..drawRect(
      ui.Rect.fromLTWH(w / 2, 0, w / 2, h.toDouble()),
      ui.Paint()..color = const Color(0xFF0000FF),
    );
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${dir.path}/halves_$w.png');
  await file.writeAsBytes(data!.buffer.asUint8List());
  return file.path;
}

(int, int, int, int) _pixel(Uint8List rgba, int x, int y, {int width = 1080}) {
  final o = (y * width + x) * 4;
  return (rgba[o], rgba[o + 1], rgba[o + 2], rgba[o + 3]);
}

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('composer'));
  tearDown(() async => dir.delete(recursive: true));

  StoryMedia photo(String path, {bool mirrored = false}) => StoryMedia(
    path: path,
    type: StoryMediaType.photo,
    width: 400,
    height: 300,
    source: StorySourceKind.gallery,
    mirrored: mirrored,
  );

  testWidgets('photo frame: background, photo in its rect, edits on top', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final path = await _halvesPng(dir, 400, 300);
      var editsPainted = false;
      final composer = FrameComposer(
        paintEdits: (canvas, document, resources) {
          editsPainted = true;
          canvas.drawRect(
            const Rect.fromLTWH(0, 1800, 100, 100),
            Paint()..color = const Color(0xFFFFFFFF),
          );
        },
      );
      // 4:3 contained: 1080×810, top at 555.
      final image = await composer.composePhotoFrame(
        StoryDocument(media: photo(path), background: _background),
        _resources,
      );
      final rgba = await OverlayRasterizer.encodeRgba(image);
      expect((image.width, image.height), (1080, 1920));
      image.dispose();
      expect(editsPainted, isTrue);
      expect(_pixel(rgba, 540, 100), (0, 255, 0, 255));
      expect(_pixel(rgba, 270, 960), (255, 0, 0, 255));
      expect(_pixel(rgba, 810, 960), (0, 0, 255, 255));
      expect(_pixel(rgba, 50, 1850), (255, 255, 255, 255));
    });
  });

  testWidgets('photo frame: mirrored and filtered', (tester) async {
    await tester.runAsync(() async {
      final path = await _halvesPng(dir, 400, 300);
      final image = await const FrameComposer(paintEdits: _noEdits)
          .composePhotoFrame(
            StoryDocument(
              media: photo(path, mirrored: true),
              background: _background,
              filterId: 'mono',
            ),
            _resources,
          );
      final rgba = await OverlayRasterizer.encodeRgba(image);
      image.dispose();
      // Mirrored: blue on the left. Mono: 0.0722 * 255 ≈ 18 grey.
      final left = _pixel(rgba, 270, 960);
      expect(left.$1, closeTo(18, 3));
      expect(left.$1, left.$3);
      final right = _pixel(rgba, 810, 960);
      expect(right.$1, closeTo(54, 3));
      // The background is not filtered.
      expect(_pixel(rgba, 540, 100), (0, 255, 0, 255));
    });
  });

  testWidgets('photo frame: zoomed media is clipped to the canvas', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final path = await _halvesPng(dir, 400, 300);
      final image = await const FrameComposer(paintEdits: _noEdits)
          .composePhotoFrame(
            StoryDocument(
              media: photo(path),
              background: _background,
              placement: const MediaPlacement(scale: 3),
            ),
            _resources,
          );
      final rgba = await OverlayRasterizer.encodeRgba(image);
      image.dispose();
      expect(_pixel(rgba, 10, 10), (255, 0, 0, 255));
      expect(_pixel(rgba, 1070, 1910), (0, 0, 255, 255));
    });
  });

  testWidgets('video overlay has a transparent hole where the video shows', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const media = StoryMedia(
        path: '/unused.mp4',
        type: StoryMediaType.video,
        width: 1920,
        height: 1080,
        source: StorySourceKind.gallery,
        duration: Duration(seconds: 3),
      );
      final image =
          await FrameComposer(
            paintEdits: (canvas, document, resources) => canvas.drawRect(
              const Rect.fromLTWH(500, 900, 80, 80),
              Paint()..color = const Color(0xFFFF00FF),
            ),
          ).composeVideoOverlay(
            const StoryDocument(media: media, background: _background),
            _resources,
          );
      final rgba = await OverlayRasterizer.encodeRgba(image);
      image.dispose();
      // 16:9 contained: y 656–1264.
      expect(_pixel(rgba, 540, 100), (0, 255, 0, 255));
      expect(_pixel(rgba, 540, 1800), (0, 255, 0, 255));
      expect(_pixel(rgba, 100, 800).$4, 0);
      expect(_pixel(rgba, 100, 1250).$4, 0);
      // Edits are drawn over the hole.
      expect(_pixel(rgba, 540, 940), (255, 0, 255, 255));
    });
  });
}

void _noEdits(Canvas canvas, StoryDocument document, StoryPaintResources r) {}
