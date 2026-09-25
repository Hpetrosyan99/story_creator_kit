import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/src/model/drawing_stroke.dart';
import 'package:story_creator_kit/src/model/media_placement.dart';
import 'package:story_creator_kit/src/model/music_selection.dart';
import 'package:story_creator_kit/src/model/overlay_transform.dart';
import 'package:story_creator_kit/src/model/story_document.dart';
import 'package:story_creator_kit/src/model/story_media.dart';
import 'package:story_creator_kit/src/model/story_overlay.dart';
import 'package:story_creator_kit/src/model/trim_range.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

const _photo = StoryMedia(
  path: '/tmp/photo.jpg',
  type: StoryMediaType.photo,
  width: 3024,
  height: 4032,
  source: StorySourceKind.gallery,
);

const _video = StoryMedia(
  path: '/tmp/video.mp4',
  type: StoryMediaType.video,
  width: 1080,
  height: 1920,
  source: StorySourceKind.camera,
  duration: Duration(seconds: 20),
  hasAudio: true,
);

const _track = MusicTrack(
  id: 'track-1',
  title: 'Loop',
  artist: 'Synth',
  duration: Duration(minutes: 1),
);

const _music = MusicSelection(
  track: _track,
  start: Duration(seconds: 5),
  duration: Duration(seconds: 15),
);

TrimRange _trim(int startSeconds, int endSeconds) =>
    TrimRange(Duration(seconds: startSeconds), Duration(seconds: endSeconds));

const _text = TextOverlay(
  id: 'text-1',
  transform: OverlayTransform(position: Offset(540, 960)),
  text: 'Hello',
  style: TextOverlayStyle(fontId: 'system', color: Color(0xFFFFFFFF)),
);

const _stroke = DrawingStroke(
  points: [StrokePoint(1, 2), StrokePoint(3, 4, 0.8)],
  color: Color(0xFFE4572E),
  size: 16,
);

void main() {
  group('StoryDocument.copyWith', () {
    test('keeps every value when called without arguments', () {
      final doc = StoryDocument(
        media: _video,
        filterId: 'warm',
        overlays: const [_text],
        strokes: const [_stroke],
        trim: _trim(1, 5),
        originalVolume: 0.4,
        music: _music,
      );

      final copy = doc.copyWith();

      expect(copy, doc);
      expect(copy.filterId, 'warm');
      expect(copy.trim, _trim(1, 5));
      expect(copy.music, _music);
      expect(copy.originalVolume, 0.4);
    });

    test('replaces the given values', () {
      const doc = StoryDocument(media: _photo);

      final copy = doc.copyWith(
        placement: const MediaPlacement(scale: 2, offset: Offset(10, 20)),
        background: const StoryBackground(top: Color(0xFF112233)),
        filterId: 'mono',
        overlays: const [_text],
        strokes: const [_stroke],
        originalVolume: 0,
        music: _music,
      );

      expect(copy.media, _photo);
      expect(copy.placement.scale, 2);
      expect(copy.placement.offset, const Offset(10, 20));
      expect(copy.background.top, const Color(0xFF112233));
      expect(copy.filterId, 'mono');
      expect(copy.overlays, [_text]);
      expect(copy.strokes, [_stroke]);
      expect(copy.originalVolume, 0);
      expect(copy.music, _music);
    });

    test('clear flags set filter, trim and music to null', () {
      final doc = StoryDocument(
        media: _video,
        filterId: 'warm',
        trim: _trim(0, 3),
        music: _music,
      );

      final cleared = doc.copyWith(
        clearFilter: true,
        clearTrim: true,
        clearMusic: true,
      );

      expect(cleared.filterId, isNull);
      expect(cleared.trim, isNull);
      expect(cleared.music, isNull);
    });

    test('a clear flag wins over a value passed in the same call', () {
      const doc = StoryDocument(media: _video);

      final copy = doc.copyWith(
        filterId: 'warm',
        clearFilter: true,
        music: _music,
        clearMusic: true,
        trim: _trim(0, 2),
        clearTrim: true,
      );

      expect(copy.filterId, isNull);
      expect(copy.music, isNull);
      expect(copy.trim, isNull);
    });
  });

  group('StoryDocument equality', () {
    test('equal documents with separately built lists are equal', () {
      final a = StoryDocument(
        media: _video,
        overlays: List.of(const [_text]),
        strokes: List.of(const [_stroke]),
      );
      final b = StoryDocument(
        media: _video,
        overlays: List.of(const [_text]),
        strokes: List.of(const [_stroke]),
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('any changed field makes documents different', () {
      const base = StoryDocument(media: _video);

      expect(base.copyWith(media: _photo), isNot(base));
      expect(
        base.copyWith(placement: const MediaPlacement(scale: 2)),
        isNot(base),
      );
      expect(
        base.copyWith(
          background: const StoryBackground(top: Color(0xFF010101)),
        ),
        isNot(base),
      );
      expect(base.copyWith(filterId: 'warm'), isNot(base));
      expect(base.copyWith(overlays: const [_text]), isNot(base));
      expect(base.copyWith(strokes: const [_stroke]), isNot(base));
      expect(base.copyWith(trim: _trim(0, 1)), isNot(base));
      expect(base.copyWith(originalVolume: 0.5), isNot(base));
      expect(base.copyWith(music: _music), isNot(base));
    });

    test('overlay order matters', () {
      const sticker = StickerOverlay(
        id: 's',
        transform: OverlayTransform(position: Offset.zero),
        stickerId: 'star',
      );
      const a = StoryDocument(media: _photo, overlays: [_text, sticker]);
      const b = StoryDocument(media: _photo, overlays: [sticker, _text]);

      expect(a, isNot(b));
    });
  });

  group('StoryDocument output', () {
    test('a photo without music exports a photo with no duration', () {
      const doc = StoryDocument(media: _photo);

      expect(doc.exportsVideo, isFalse);
      expect(doc.outputType, StoryMediaType.photo);
      expect(doc.outputDuration, isNull);
    });

    test('a photo with music exports a video of the music length', () {
      const doc = StoryDocument(media: _photo, music: _music);

      expect(doc.exportsVideo, isTrue);
      expect(doc.outputType, StoryMediaType.video);
      expect(doc.outputDuration, const Duration(seconds: 15));
    });

    test('an untrimmed video exports its full length', () {
      const doc = StoryDocument(media: _video);

      expect(doc.outputType, StoryMediaType.video);
      expect(doc.outputDuration, const Duration(seconds: 20));
    });

    test('a trimmed video exports the trim length, ignoring music length', () {
      final doc = StoryDocument(
        media: _video,
        trim: _trim(2, 9),
        music: _music,
      );

      expect(doc.outputDuration, const Duration(seconds: 7));
    });
  });
}
