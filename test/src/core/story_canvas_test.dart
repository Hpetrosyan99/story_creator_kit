import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/src/core/story_canvas.dart';
import 'package:story_creator_kit/src/model/media_placement.dart';
import 'package:story_creator_kit/src/model/story_media.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

StoryMedia _media(int width, int height) => StoryMedia(
  path: '/m.jpg',
  type: StoryMediaType.photo,
  width: width,
  height: height,
  source: StorySourceKind.gallery,
);

void main() {
  test('canvas constants describe a 1080×1920 canvas', () {
    expect(StoryCanvas.size, const Size(1080, 1920));
    expect(StoryCanvas.bounds, const Rect.fromLTWH(0, 0, 1080, 1920));
    expect(StoryCanvas.center, const Offset(540, 960));
    expect(StoryCanvas.outputWidth, 1080);
    expect(StoryCanvas.outputHeight, 1920);
  });

  group('containSize', () {
    test('9:16 media fills the canvas exactly', () {
      expect(StoryCanvas.containSize(9 / 16), const Size(1080, 1920));
    });

    test('landscape media is full width, letterboxed', () {
      final size = StoryCanvas.containSize(16 / 9);
      expect(size.width, 1080);
      expect(size.height, closeTo(607.5, 1e-9));
    });

    test('square media is full width', () {
      expect(StoryCanvas.containSize(1), const Size(1080, 1080));
    });

    test('media taller than 9:16 is full height, pillarboxed', () {
      final size = StoryCanvas.containSize(9 / 19.5);
      expect(size.height, 1920);
      expect(size.width, closeTo(1920 * 9 / 19.5, 1e-9));
    });
  });

  group('coverScale', () {
    test('is 1 for exact 9:16', () {
      expect(StoryCanvas.coverScale(9 / 16), closeTo(1, 1e-12));
    });

    test('scales landscape media until it covers the height', () {
      expect(StoryCanvas.coverScale(16 / 9), closeTo(1920 / 607.5, 1e-9));
    });

    test('scales very tall media until it covers the width', () {
      const aspect = 9 / 19.5;
      expect(
        StoryCanvas.coverScale(aspect),
        closeTo(1080 / (1920 * aspect), 1e-9),
      );
    });

    test('the covered rect contains the whole canvas', () {
      for (final aspect in [0.3, 9 / 16, 0.75, 1.0, 4 / 3, 16 / 9, 3.0]) {
        final rect = StoryCanvas.mediaRect(
          aspect,
          MediaPlacement(scale: StoryCanvas.coverScale(aspect)),
        );
        expect(rect.width, greaterThanOrEqualTo(1080 - 1e-6));
        expect(rect.height, greaterThanOrEqualTo(1920 - 1e-6));
        expect(
          rect.width == 1080 ||
              rect.height == 1920 ||
              (rect.width - 1080).abs() < 1e-6 ||
              (rect.height - 1920).abs() < 1e-6,
          isTrue,
          reason: 'one side matches the canvas exactly',
        );
      }
    });
  });

  group('defaultPlacement', () {
    test('1080×1920 fills at scale 1', () {
      final p = StoryCanvas.defaultPlacement(_media(1080, 1920));
      expect(p.scale, closeTo(1, 1e-12));
      expect(p.offset, Offset.zero);
    });

    test('a modern phone screen (9:19.5) is near 9:16 and fills', () {
      final p = StoryCanvas.defaultPlacement(_media(1080, 2340));
      expect(p.scale, closeTo(StoryCanvas.coverScale(1080 / 2340), 1e-9));
      expect(p.scale, greaterThan(1));
    });

    test('a 1:2 portrait (within 18% of 9:16) fills', () {
      final p = StoryCanvas.defaultPlacement(_media(1000, 2000));
      expect(p.scale, closeTo(StoryCanvas.coverScale(0.5), 1e-9));
      expect(p.scale, greaterThan(1));
    });

    test(
      'a 2:3 portrait photo is just outside the tolerance and is contained',
      () {
        // (2/3) / (9/16) = 1.185 > 1 + fillTolerance.
        expect(StoryCanvas.defaultPlacement(_media(2000, 3000)).scale, 1);
      },
    );

    test('a 3:4 portrait photo is outside the tolerance and is contained', () {
      final p = StoryCanvas.defaultPlacement(_media(3024, 4032));
      expect(p.scale, 1);
    });

    test('landscape media is contained', () {
      expect(StoryCanvas.defaultPlacement(_media(1920, 1080)).scale, 1);
      expect(StoryCanvas.defaultPlacement(_media(4032, 3024)).scale, 1);
    });

    test('square media is contained', () {
      expect(StoryCanvas.defaultPlacement(_media(1080, 1080)).scale, 1);
    });
  });

  group('mediaRect', () {
    test('default placement centres the contained media', () {
      final rect = StoryCanvas.mediaRect(16 / 9, const MediaPlacement());
      expect(rect.center, StoryCanvas.center);
      expect(rect.left, 0);
      expect(rect.width, 1080);
      expect(rect.height, closeTo(607.5, 1e-9));
    });

    test('scale grows the rect around the moved centre', () {
      final rect = StoryCanvas.mediaRect(
        1,
        const MediaPlacement(scale: 2, offset: Offset(100, -50)),
      );
      expect(rect.center, const Offset(640, 910));
      expect(rect.size, const Size(2160, 2160));
      expect(rect.left, 640 - 1080);
      expect(rect.top, 910 - 1080);
    });

    test('scale below 1 shrinks the media', () {
      final rect = StoryCanvas.mediaRect(
        9 / 16,
        const MediaPlacement(scale: 0.5),
      );
      expect(rect, const Rect.fromLTWH(270, 480, 540, 960));
    });
  });

  group('viewScale', () {
    test('fits the whole canvas into a narrow, tall viewport by width', () {
      expect(
        StoryCanvas.viewScale(const Size(390, 844)),
        closeTo(390 / 1080, 1e-12),
      );
    });

    test('fits the whole canvas into a wide viewport by height', () {
      expect(
        StoryCanvas.viewScale(const Size(1024, 768)),
        closeTo(768 / 1920, 1e-12),
      );
    });

    test('is 1 for a canvas-sized viewport', () {
      expect(StoryCanvas.viewScale(StoryCanvas.size), 1);
    });
  });
}
