import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/services.dart';
import 'package:story_creator_kit/src/core/story_canvas.dart';
import 'package:story_creator_kit/src/editor/editor_controller.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

const _photo = StoryMedia(
  path: '/tmp/p.jpg',
  type: StoryMediaType.photo,
  width: 1080,
  height: 1920,
  source: StorySourceKind.gallery,
);

const _video = StoryMedia(
  path: '/tmp/v.mp4',
  type: StoryMediaType.video,
  width: 1080,
  height: 1920,
  source: StorySourceKind.gallery,
  duration: Duration(seconds: 30),
  hasAudio: true,
);

const _style = TextOverlayStyle(fontId: 'system', color: Color(0xFFFFFFFF));

const _stroke = DrawingStroke(
  points: [StrokePoint(10, 10), StrokePoint(40, 40)],
  color: Color(0xFFFFFFFF),
  size: 16,
);

const _music = MusicSelection(
  track: MusicTrack(
    id: 'm',
    title: 'Song',
    artist: 'Artist',
    duration: Duration(minutes: 3),
  ),
  start: Duration(seconds: 12),
  duration: Duration(seconds: 30),
  localPath: '/tmp/m.m4a',
);

EditorController _controller({
  StoryMedia media = _photo,
  EditorOptions options = const EditorOptions(),
  MusicSelection? music,
}) => EditorController(
  initialDocument: StoryDocument(media: media, music: music),
  options: options,
);

void main() {
  group('text', () {
    test('commitText adds a centred overlay, selects it, and undoes', () {
      final c = _controller();
      final overlay = c.commitText(text: 'Hello', style: _style)!;

      expect(c.document.overlays, [overlay]);
      expect(overlay.transform.position, StoryCanvas.center);
      expect(c.selectedId, overlay.id);
      expect(c.isDirty, isTrue);

      c.undo();
      expect(c.document.overlays, isEmpty);
      expect(c.selectedId, isNull);
      expect(c.isDirty, isFalse);

      c.redo();
      expect(c.document.overlays.single, overlay);
    });

    test('editing updates in place; empty text deletes', () {
      final c = _controller();
      final overlay = c.commitText(text: 'Hello', style: _style)!;
      final updated = c.commitText(
        id: overlay.id,
        text: 'Bye',
        style: _style.copyWith(background: TextBackgroundStyle.highlight),
      )!;
      expect(updated.id, overlay.id);
      expect((c.document.overlays.single as TextOverlay).text, 'Bye');

      expect(c.commitText(id: overlay.id, text: '   ', style: _style), isNull);
      expect(c.document.overlays, isEmpty);
    });

    test('empty new text adds nothing', () {
      final c = _controller();
      expect(c.commitText(text: '', style: _style), isNull);
      expect(c.canUndo, isFalse);
    });
  });

  test('respects maxOverlays across text, stickers and emoji', () {
    final c = _controller(options: const EditorOptions(maxOverlays: 2));
    expect(c.addEmoji('🔥'), isTrue);
    expect(c.addSticker('s'), isTrue);
    expect(c.canAddOverlay, isFalse);
    expect(c.addEmoji('✨'), isFalse);
    expect(c.commitText(text: 'x', style: _style), isNull);
    expect(c.document.overlays, hasLength(2));
  });

  test('a gesture is one undo step', () {
    final c = _controller();
    final overlay = c.commitText(text: 'Hi', style: _style)!;
    c.beginGesture();
    for (var i = 1; i <= 5; i++) {
      c.transformOverlay(
        overlay.id,
        OverlayTransform(position: Offset(100.0 * i, 200), scale: 1.0 + i),
      );
    }
    c.endGesture();
    final moved = c.overlayById(overlay.id)!.transform;
    expect(moved.position, const Offset(500, 200));
    expect(moved.scale, 6);

    c.undo();
    expect(c.overlayById(overlay.id)!.transform.position, StoryCanvas.center);
  });

  test('transform clamps scale and keeps the centre on the canvas', () {
    final c = _controller();
    final id = c.commitText(text: 'Hi', style: _style)!.id;
    c.transformOverlay(
      id,
      const OverlayTransform(position: Offset(-500, 5000), scale: 100),
    );
    final t = c.overlayById(id)!.transform;
    expect(t.position, const Offset(0, StoryCanvas.height));
    expect(t.scale, EditorController.maxOverlayScale);
  });

  test('bringToFront and delete', () {
    final c = _controller()
      ..addEmoji('a')
      ..addEmoji('b');
    final first = c.document.overlays.first.id;
    c.bringToFront(first);
    expect(c.document.overlays.last.id, first);
    c
      ..select(first)
      ..deleteOverlay(first);
    expect(c.selectedId, isNull);
    expect(c.document.overlays, hasLength(1));
  });

  test('undo and redo span every tool (AC9, AC14)', () {
    final c = _controller()
      ..commitText(text: 'Hi', style: _style)
      ..addStroke(_stroke)
      ..setFilter(StoryFilter.defaults[1])
      ..setTool(EditorTool.draw)
      ..addStroke(_stroke.copyWithTool(StrokeTool.eraser));
    expect(c.document.strokes, hasLength(2));
    expect(c.document.filterId, StoryFilter.defaults[1].id);

    c
      ..setTool(EditorTool.filters)
      ..undo()
      ..undo();
    expect(c.document.strokes, hasLength(1));
    expect(c.document.filterId, isNull);
    expect(c.document.overlays, hasLength(1));

    c
      ..redo()
      ..redo();
    expect(c.document.strokes, hasLength(2));
    expect(c.document.filterId, StoryFilter.defaults[1].id);
  });

  test('identity filters clear the filter', () {
    final c = _controller()..setFilter(StoryFilter.defaults[2]);
    expect(c.document.filterId, isNotNull);
    c.setFilter(StoryFilter.original);
    expect(c.document.filterId, isNull);
  });

  test('placement is clamped', () {
    final c = _controller()
      ..setPlacement(
        const MediaPlacement(scale: 100, offset: Offset(1000000, 0)),
      );
    expect(c.document.placement.scale, EditorController.maxMediaScale);
    expect(c.document.placement.offset.dx, StoryCanvas.width);
  });

  group('trim', () {
    test('music length follows the trim', () {
      final c = _controller(media: _video, music: _music)
        ..setTrim(
          TrimRange(const Duration(seconds: 2), const Duration(seconds: 9)),
        );
      expect(c.document.trim!.duration, const Duration(seconds: 7));
      expect(c.document.music!.duration, const Duration(seconds: 7));
      expect(c.document.music!.start, _music.start);
    });

    test('a range over the whole video is stored as no trim', () {
      final c = _controller(media: _video, music: _music)
        ..setTrim(
          TrimRange(const Duration(seconds: 2), const Duration(seconds: 9)),
        )
        ..setTrim(TrimRange(Duration.zero, const Duration(seconds: 30)));
      expect(c.document.trim, isNull);
      expect(c.document.music!.duration, const Duration(seconds: 30));
    });
  });

  test('volumes and music', () {
    final c = _controller(media: _video)..setOriginalVolume(2);
    expect(c.document.originalVolume, 1);
    c.setMusicVolume(0.3);
    expect(c.document.music, isNull);
    c
      ..setMusic(_music)
      ..setMusicVolume(0.3);
    expect(c.document.music!.volume, 0.3);
    c.setMusic(null);
    expect(c.document.music, isNull);
  });

  test('music segment length: trimmed video, or the photo duration', () {
    final video = _controller(media: _video)
      ..setTrim(TrimRange(Duration.zero, const Duration(seconds: 12)));
    expect(
      video.musicSegmentLength(
        photoDuration: const Duration(seconds: 15),
        maxDuration: const Duration(seconds: 60),
      ),
      const Duration(seconds: 12),
    );
    expect(
      _controller().musicSegmentLength(
        photoDuration: const Duration(seconds: 15),
        maxDuration: const Duration(seconds: 10),
      ),
      const Duration(seconds: 10),
    );
  });

  test('applyBackground is not an undo step and not dirty', () {
    final c = _controller();
    var notified = 0;
    c
      ..addListener(() => notified++)
      ..applyBackground(
        const StoryBackground(
          top: Color(0xFF112233),
          bottom: Color(0xFF445566),
        ),
      );
    expect(c.document.background.top, const Color(0xFF112233));
    expect(c.canUndo, isFalse);
    expect(c.isDirty, isFalse);
    expect(notified, 1);
  });

  test('tool and selection changes do not touch history', () {
    final c = _controller()
      ..setTool(EditorTool.draw)
      ..select('x');
    expect(c.tool, EditorTool.draw);
    expect(c.canUndo, isFalse);
  });
}

extension on DrawingStroke {
  DrawingStroke copyWithTool(StrokeTool tool) =>
      DrawingStroke(points: points, color: color, size: size, tool: tool);
}
