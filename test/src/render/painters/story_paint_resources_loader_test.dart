import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/services.dart';
import 'package:story_creator_kit/src/core/story_canvas.dart';
import 'package:story_creator_kit/src/render/painters/story_paint_resources_loader.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

import '../../../fakes/fake_services.dart';

const _media = StoryMedia(
  path: '/tmp/photo.jpg',
  type: StoryMediaType.photo,
  width: 1080,
  height: 1920,
  source: StorySourceKind.gallery,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetStoryFontLoads);

  test('runs only the loaders of fonts used by text overlays, once', () async {
    var usedLoads = 0;
    var unusedLoads = 0;
    final options = EditorOptions(
      fonts: [
        StoryFont(id: 'used', label: 'Used', loader: () async => usedLoads++),
        StoryFont(
          id: 'unused',
          label: 'Unused',
          loader: () async => unusedLoads++,
        ),
      ],
    );
    const document = StoryDocument(
      media: _media,
      overlays: [
        TextOverlay(
          id: 't1',
          transform: OverlayTransform(position: StoryCanvas.center),
          text: 'a',
          style: TextOverlayStyle(fontId: 'used', color: Color(0xFFFFFFFF)),
        ),
        TextOverlay(
          id: 't2',
          transform: OverlayTransform(position: StoryCanvas.center),
          text: 'b',
          style: TextOverlayStyle(fontId: 'used', color: Color(0xFFFFFFFF)),
        ),
      ],
    );
    final resources = createStoryPaintResources(options);

    await ensureStoryPaintResources(resources, document, options);
    await ensureStoryPaintResources(resources, document, options);

    expect(usedLoads, 1);
    expect(unusedLoads, 0);
    expect(isStoryFontReady(options.fonts.first), isTrue);
    expect(isStoryFontReady(options.fonts.last), isFalse);
  });

  test('a failing font loader is a typed error and can be retried', () async {
    var attempts = 0;
    final font = StoryFont(
      id: 'flaky',
      label: 'Flaky',
      loader: () async {
        attempts++;
        if (attempts == 1) {
          throw StateError('offline');
        }
      },
    );
    await expectLater(
      loadStoryFont(font),
      throwsA(
        isA<StoryException>().having(
          (e) => e.code,
          'code',
          StoryErrorCode.mediaUnavailable,
        ),
      ),
    );
    await loadStoryFont(font);
    expect(attempts, 2);
  });

  test('decodes stickers used by the document into the resources', () async {
    final options = EditorOptions(
      stickers: [
        StorySticker(
          id: 'dot',
          image: MemoryImage(kTransparentPng),
          label: 'Dot',
        ),
        StorySticker(
          id: 'other',
          image: MemoryImage(kTransparentPng),
          label: 'Other',
        ),
      ],
    );
    const document = StoryDocument(
      media: _media,
      overlays: [
        StickerOverlay(
          id: 's',
          transform: OverlayTransform(position: StoryCanvas.center),
          stickerId: 'dot',
        ),
      ],
    );
    final resources = createStoryPaintResources(options);

    await ensureStoryPaintResources(resources, document, options);

    expect(resources.sticker('dot'), isNotNull);
    expect(resources.sticker('dot')!.width, 1);
    expect(resources.sticker('other'), isNull);
  });

  test('an unknown sticker id is a typed error', () async {
    const options = EditorOptions();
    const document = StoryDocument(
      media: _media,
      overlays: [
        StickerOverlay(
          id: 's',
          transform: OverlayTransform(position: StoryCanvas.center),
          stickerId: 'gone',
        ),
      ],
    );
    await expectLater(
      ensureStoryPaintResources(
        createStoryPaintResources(options),
        document,
        options,
      ),
      throwsA(isA<StoryException>()),
    );
  });

  test('an undecodable sticker is a typed error', () async {
    final options = EditorOptions(
      stickers: [
        StorySticker(
          id: 'bad',
          image: MemoryImage(Uint8List.fromList(const [1, 2, 3])),
          label: 'Bad',
        ),
      ],
    );
    const document = StoryDocument(
      media: _media,
      overlays: [
        StickerOverlay(
          id: 's',
          transform: OverlayTransform(position: StoryCanvas.center),
          stickerId: 'bad',
        ),
      ],
    );
    await expectLater(
      ensureStoryPaintResources(
        createStoryPaintResources(options),
        document,
        options,
      ),
      throwsA(isA<StoryException>()),
    );
  });
}
