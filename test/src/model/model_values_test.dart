import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/src/model/drawing_stroke.dart';
import 'package:story_creator_kit/src/model/media_placement.dart';
import 'package:story_creator_kit/src/model/music_selection.dart';
import 'package:story_creator_kit/src/model/overlay_transform.dart';
import 'package:story_creator_kit/src/model/story_media.dart';
import 'package:story_creator_kit/src/model/story_overlay.dart';
import 'package:story_creator_kit/src/model/trim_range.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

TrimRange trim(int startSeconds, int endSeconds) =>
    TrimRange(Duration(seconds: startSeconds), Duration(seconds: endSeconds));

void main() {
  group('OverlayTransform.normalizedRotation', () {
    double norm(double r) =>
        OverlayTransform(position: Offset.zero, rotation: r).normalizedRotation;

    test('keeps angles already in (-π, π]', () {
      expect(norm(0), 0);
      expect(norm(1), closeTo(1, 1e-12));
      expect(norm(-1), closeTo(-1, 1e-12));
      expect(norm(math.pi), closeTo(math.pi, 1e-12));
    });

    test('maps -π to π (the interval is open at -π)', () {
      expect(norm(-math.pi), closeTo(math.pi, 1e-12));
    });

    test('wraps angles above π to negative', () {
      expect(norm(3 * math.pi / 2), closeTo(-math.pi / 2, 1e-12));
      expect(norm(2 * math.pi), closeTo(0, 1e-12));
    });

    test('wraps several full turns in both directions', () {
      expect(norm(5 * math.pi + 0.25), closeTo(-math.pi + 0.25, 1e-9));
      expect(norm(-7 * math.pi / 2), closeTo(math.pi / 2, 1e-9));
      expect(norm(-4 * math.pi - 0.5), closeTo(-0.5, 1e-9));
    });

    test('result is always in (-π, π]', () {
      for (var r = -20.0; r <= 20; r += 0.37) {
        final n = norm(r);
        expect(n, greaterThan(-math.pi));
        expect(n, lessThanOrEqualTo(math.pi));
        expect(math.cos(n), closeTo(math.cos(r), 1e-9));
        expect(math.sin(n), closeTo(math.sin(r), 1e-9));
      }
    });
  });

  group('OverlayTransform', () {
    test('copyWith and equality', () {
      const t = OverlayTransform(
        position: Offset(1, 2),
        scale: 2,
        rotation: 0.5,
      );

      expect(t.copyWith(), t);
      expect(t.copyWith().hashCode, t.hashCode);
      expect(
        t.copyWith(position: const Offset(3, 4)).position,
        const Offset(3, 4),
      );
      expect(t.copyWith(scale: 3).scale, 3);
      expect(t.copyWith(rotation: 1).rotation, 1);
      expect(t.copyWith(scale: 3), isNot(t));
    });
  });

  group('TrimRange', () {
    final range = trim(2, 7);

    test('duration is end minus start', () {
      expect(range.duration, const Duration(seconds: 5));
    });

    test('contains is inclusive at both ends', () {
      expect(range.contains(const Duration(seconds: 2)), isTrue);
      expect(range.contains(const Duration(seconds: 7)), isTrue);
      expect(range.contains(const Duration(seconds: 4)), isTrue);
      expect(range.contains(const Duration(milliseconds: 1999)), isFalse);
      expect(range.contains(const Duration(milliseconds: 7001)), isFalse);
    });

    test('equality', () {
      expect(range, trim(2, 7));
      expect(range.hashCode, trim(2, 7).hashCode);
      expect(range, isNot(trim(2, 8)));
      expect(range.toString(), contains('TrimRange('));
    });

    test('asserts (debug) that end is after start', () {
      expect(
        () => TrimRange(const Duration(seconds: 3), const Duration(seconds: 3)),
        throwsAssertionError,
      );
      expect(
        () => TrimRange(const Duration(seconds: 3), const Duration(seconds: 1)),
        throwsAssertionError,
      );
    });
  });

  group('MediaPlacement / StoryBackground', () {
    test('defaults', () {
      const p = MediaPlacement();
      expect(p.scale, 1);
      expect(p.offset, Offset.zero);
      const b = StoryBackground();
      expect(b.top, const Color(0xFF000000));
      expect(b.bottom, const Color(0xFF000000));
    });

    test('copyWith and equality', () {
      const p = MediaPlacement(scale: 1.5, offset: Offset(4, 5));
      expect(p.copyWith(), p);
      expect(
        p.copyWith(scale: 2),
        const MediaPlacement(scale: 2, offset: Offset(4, 5)),
      );
      expect(p.copyWith(offset: Offset.zero), const MediaPlacement(scale: 1.5));
      expect(
        const StoryBackground(top: Color(0xFF111111)),
        isNot(const StoryBackground()),
      );
    });
  });

  group('StoryMedia', () {
    const video = StoryMedia(
      path: '/v.mp4',
      type: StoryMediaType.video,
      width: 1920,
      height: 1080,
      source: StorySourceKind.gallery,
      duration: Duration(seconds: 3),
      mimeType: 'video/mp4',
    );

    test('isVideo and aspectRatio', () {
      expect(video.isVideo, isTrue);
      expect(video.aspectRatio, closeTo(16 / 9, 1e-9));
    });

    test('copyWith keeps type, source and mimeType', () {
      final copy = video.copyWith(
        path: '/w.mp4',
        mirrored: true,
        rotationDegrees: 90,
      );

      expect(copy.path, '/w.mp4');
      expect(copy.mirrored, isTrue);
      expect(copy.rotationDegrees, 90);
      expect(copy.type, StoryMediaType.video);
      expect(copy.source, StorySourceKind.gallery);
      expect(copy.mimeType, 'video/mp4');
      expect(copy.duration, const Duration(seconds: 3));
    });

    test('equality', () {
      expect(video.copyWith(), video);
      expect(video.copyWith().hashCode, video.hashCode);
      expect(video.copyWith(hasAudio: true), isNot(video));
    });
  });

  group('overlays', () {
    const transform = OverlayTransform(position: Offset(10, 10));
    const moved = OverlayTransform(position: Offset(20, 20), scale: 2);
    const style = TextOverlayStyle(fontId: 'f', color: Color(0xFFFFFFFF));

    test('TextOverlayStyle defaults and copyWith', () {
      expect(style.align, TextAlign.center);
      expect(style.background, TextBackgroundStyle.none);
      expect(style.fontSize, TextOverlayStyle.defaultFontSize);
      expect(style.copyWith(), style);
      final changed = style.copyWith(
        fontId: 'g',
        color: const Color(0xFF000000),
        align: TextAlign.left,
        background: TextBackgroundStyle.highlight,
        fontSize: 40,
      );
      expect(changed.fontId, 'g');
      expect(changed.color, const Color(0xFF000000));
      expect(changed.align, TextAlign.left);
      expect(changed.background, TextBackgroundStyle.highlight);
      expect(changed.fontSize, 40);
      expect(changed, isNot(style));
    });

    test('TextOverlay withTransform and copyWith keep the other fields', () {
      const text = TextOverlay(
        id: 't',
        transform: transform,
        text: 'a',
        style: style,
      );

      final m = text.withTransform(moved);
      expect(m.transform, moved);
      expect(m.id, 't');
      expect(m.text, 'a');
      expect(m.style, style);

      final c = text.copyWith(text: 'b');
      expect(c.text, 'b');
      expect(c.transform, transform);
      expect(c, isNot(text));
      expect(text.copyWith(), text);
    });

    test('StickerOverlay withTransform keeps sticker id and base size', () {
      const sticker = StickerOverlay(
        id: 's',
        transform: transform,
        stickerId: 'star',
        baseSize: 200,
      );

      final m = sticker.withTransform(moved);
      expect(m.transform, moved);
      expect(m.stickerId, 'star');
      expect(m.baseSize, 200);
      expect(m, isNot(sticker));
      expect(sticker.withTransform(transform), sticker);
      expect(
        const StickerOverlay(
          id: 's',
          transform: transform,
          stickerId: 'x',
        ).baseSize,
        StickerOverlay.defaultBaseSize,
      );
    });

    test('EmojiOverlay withTransform keeps emoji and size', () {
      const emoji = EmojiOverlay(id: 'e', transform: transform, emoji: '🔥');

      final m = emoji.withTransform(moved);
      expect(m.emoji, '🔥');
      expect(m.fontSize, EmojiOverlay.defaultFontSize);
      expect(m.transform, moved);
      expect(emoji.withTransform(transform), emoji);
      expect(emoji.withTransform(transform).hashCode, emoji.hashCode);
    });

    test('overlays of different kinds are never equal', () {
      const text = TextOverlay(
        id: 'x',
        transform: transform,
        text: '🔥',
        style: style,
      );
      const emoji = EmojiOverlay(id: 'x', transform: transform, emoji: '🔥');

      expect(text == emoji, isFalse);
    });
  });

  group('DrawingStroke', () {
    test('equality compares points by value', () {
      final a = DrawingStroke(
        points: List.of(const [StrokePoint(1, 2), StrokePoint(3, 4, 0.9)]),
        color: const Color(0xFFFFFFFF),
        size: 10,
      );
      final b = DrawingStroke(
        points: List.of(const [StrokePoint(1, 2), StrokePoint(3, 4, 0.9)]),
        color: const Color(0xFFFFFFFF),
        size: 10,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.tool, StrokeTool.pen);
      expect(const StrokePoint(1, 2).pressure, 0.5);
    });

    test('tool, size, colour and points all matter', () {
      const base = DrawingStroke(
        points: [StrokePoint(1, 2)],
        color: Color(0xFFFFFFFF),
        size: 10,
      );

      expect(
        const DrawingStroke(
          points: [StrokePoint(1, 2)],
          color: Color(0xFFFFFFFF),
          size: 10,
          tool: StrokeTool.eraser,
        ),
        isNot(base),
      );
      expect(
        const DrawingStroke(
          points: [StrokePoint(1, 2)],
          color: Color(0xFFFFFFFF),
          size: 11,
        ),
        isNot(base),
      );
      expect(
        const DrawingStroke(
          points: [StrokePoint(1, 2)],
          color: Color(0xFF000000),
          size: 10,
        ),
        isNot(base),
      );
      expect(
        const DrawingStroke(
          points: [StrokePoint(1, 3)],
          color: Color(0xFFFFFFFF),
          size: 10,
        ),
        isNot(base),
      );
    });
  });

  group('MusicSelection', () {
    const track = MusicTrack(
      id: 'a',
      title: 'A',
      artist: 'B',
      duration: Duration(minutes: 2),
    );
    const selection = MusicSelection(
      track: track,
      start: Duration(seconds: 10),
      duration: Duration(seconds: 15),
    );

    test('defaults to full volume and no local file', () {
      expect(selection.volume, 1);
      expect(selection.localPath, isNull);
    });

    test('copyWith keeps the track', () {
      final copy = selection.copyWith(
        start: const Duration(seconds: 1),
        duration: const Duration(seconds: 2),
        localPath: '/m.m4a',
        volume: 0.3,
      );

      expect(copy.track.id, 'a');
      expect(copy.start, const Duration(seconds: 1));
      expect(copy.duration, const Duration(seconds: 2));
      expect(copy.localPath, '/m.m4a');
      expect(copy.volume, 0.3);
      expect(selection.copyWith(), selection);
    });

    test('equality uses the track id, not the bookmark flag', () {
      final bookmarked = MusicSelection(
        track: track.copyWith(bookmarked: true),
        start: selection.start,
        duration: selection.duration,
      );

      expect(bookmarked, selection);
      expect(bookmarked.hashCode, selection.hashCode);
      expect(selection.copyWith(volume: 0.5), isNot(selection));
    });
  });
}
