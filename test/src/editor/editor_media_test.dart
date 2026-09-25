import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/services.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

import '../../fakes/fake_services.dart';
import 'editor_test_harness.dart';

MusicSelection _music(
  Directory dir, {
  Duration duration = const Duration(seconds: 20),
}) => MusicSelection(
  track: const MusicTrack(
    id: 'song',
    title: 'Song',
    artist: 'Artist',
    duration: Duration(minutes: 3),
  ),
  start: const Duration(seconds: 12),
  duration: duration,
  localPath: '${dir.path}/song.m4a',
  volume: 0.8,
);

StoryMedia Function(Directory) _video({
  Duration duration = const Duration(seconds: 20),
  bool hasAudio = true,
}) =>
    (dir) => videoMedia(dir, duration: duration, hasAudio: hasAudio);

void main() {
  group('video playback (AC13)', () {
    testWidgets('autoplays looped in the trim range at the original volume', (
      tester,
    ) async {
      final h = await pumpEditor(
        tester,
        media: _video(duration: const Duration(seconds: 90)),
        videoDuration: const Duration(seconds: 90),
        document: (media) => StoryDocument(
          media: media,
          trim: TrimRange(Duration.zero, const Duration(seconds: 60)),
          originalVolume: 0.6,
        ),
      );
      final video = h.video.single;
      expect(video.openedPath, endsWith('missing_video.mp4'));
      expect(
        video.range,
        TrimRange(Duration.zero, const Duration(seconds: 60)),
      );
      expect(video.state.value.playing, isTrue);
      expect(video.volume, 0.6);
    });

    testWidgets('a video without audio plays muted', (tester) async {
      final h = await pumpEditor(tester, media: _video(hasAudio: false));
      expect(h.video.single.volume, 0);
      // No original audio and no music: no audio mixer.
      expect(find.bySemanticsLabel(strings.editor.audio), findsNothing);
    });

    testWidgets('play/pause button and inactive editor pause playback', (
      tester,
    ) async {
      final h = await pumpEditor(
        tester,
        media: _video(),
        document: (media) =>
            StoryDocument(media: media, music: _music(media.path.dirOf)),
      );
      final video = h.video.single;
      final music = h.music.single;
      expect(video.state.value.playing, isTrue);
      expect(music.playing.value, isTrue);

      await tester.tap(find.bySemanticsLabel(strings.editor.pause));
      await tester.pump();
      expect(video.state.value.playing, isFalse);
      expect(music.playing.value, isFalse);

      await tester.tap(find.bySemanticsLabel(strings.editor.play));
      await tester.pump();
      expect(video.state.value.playing, isTrue);
      expect(music.playing.value, isTrue);

      h.active.value = false;
      await tester.pump();
      await tester.pump();
      expect(video.state.value.playing, isFalse);
      expect(music.playing.value, isFalse);

      h.active.value = true;
      await tester.pump();
      await tester.pump();
      expect(video.state.value.playing, isTrue);
      expect(music.playing.value, isTrue);
    });

    testWidgets('music restarts at its start when the video loops', (
      tester,
    ) async {
      final h = await pumpEditor(
        tester,
        media: _video(),
        document: (media) =>
            StoryDocument(media: media, music: _music(media.path.dirOf)),
      );
      final video = h.video.single;
      final music = h.music.single;
      expect(music.loaded, isA<MusicFileSource>());
      expect((music.loaded! as MusicFileSource).path, endsWith('song.m4a'));
      expect(music.segment, (
        const Duration(seconds: 12),
        const Duration(seconds: 20),
      ));
      expect(music.volume, 0.8);
      final plays = music.playCount;

      await video.seekTo(const Duration(seconds: 5));
      await tester.pump();
      expect(music.playCount, plays);
      // Back to the loop start.
      await video.seekTo(Duration.zero);
      await tester.pump();
      await tester.pump();
      expect(music.playCount, plays + 1);
      expect(music.segment!.$1, const Duration(seconds: 12));
    });

    testWidgets('photo with music loops the segment', (tester) async {
      final h = await pumpEditor(
        tester,
        document: (media) => StoryDocument(
          media: media,
          music: _music(
            media.path.dirOf,
            duration: const Duration(seconds: 15),
          ),
        ),
      );
      expect(h.video, isEmpty);
      final music = h.music.single;
      expect(music.segment, (
        const Duration(seconds: 12),
        const Duration(seconds: 15),
      ));
      expect(music.lastLoop, isTrue);
      expect(music.playing.value, isTrue);
    });
  });

  group('trim (AC13)', () {
    Future<EditorHarness> openTrim(
      WidgetTester tester, {
      MusicSelection? Function(Directory dir)? music,
    }) async {
      final h = await pumpEditor(
        tester,
        media: _video(duration: const Duration(seconds: 90)),
        videoDuration: const Duration(seconds: 90),
        constraints: const MediaConstraints(
          minVideoDuration: Duration(seconds: 3),
        ),
        document: (media) => StoryDocument(
          media: media,
          trim: TrimRange(Duration.zero, const Duration(seconds: 60)),
          music: music?.call(media.path.dirOf),
        ),
      );
      await tester.tap(find.bySemanticsLabel(strings.editor.trim));
      await tester.pump();
      return h;
    }

    testWidgets('shows ~10 frames from the inspector', (tester) async {
      await openTrim(tester);
      await tester.pump();
      expect(find.byType(Image), findsNWidgets(10));
    });

    testWidgets('the end handle cannot exceed the maximum length', (
      tester,
    ) async {
      final h = await openTrim(
        tester,
        music: (dir) => _music(dir, duration: const Duration(seconds: 60)),
      );
      await tester.drag(
        find.byKey(const ValueKey('trimEnd')),
        const Offset(300, 0),
      );
      await tester.pump();
      var doc = await h.export(tester);
      expect(doc.trim, TrimRange(Duration.zero, const Duration(seconds: 60)));

      await tester.tap(find.bySemanticsLabel(strings.editor.trim));
      await tester.pump();
      // Move the start right: the end may follow up to the maximum.
      await tester.drag(
        find.byKey(const ValueKey('trimStart')),
        const Offset(60, 0),
      );
      await tester.pump();
      await tester.drag(
        find.byKey(const ValueKey('trimEnd')),
        const Offset(300, 0),
      );
      await tester.pump();
      doc = await h.export(tester);
      final trim = doc.trim!;
      expect(trim.start, greaterThan(Duration.zero));
      expect(trim.duration, lessThanOrEqualTo(const Duration(seconds: 60)));
      expect(trim.duration, greaterThan(const Duration(seconds: 55)));
      // Music follows the trimmed length; the video loops in the new range.
      expect(doc.music!.duration, trim.duration);
      expect(h.video.single.range, trim);
    });

    testWidgets('the start handle keeps the minimum length', (tester) async {
      final h = await openTrim(tester);
      await tester.drag(
        find.byKey(const ValueKey('trimStart')),
        const Offset(600, 0),
      );
      await tester.pump();
      final trim = (await h.export(tester)).trim!;
      expect(trim.end, const Duration(seconds: 60));
      expect(trim.duration, const Duration(seconds: 3));
    });

    testWidgets('handles are adjustable with a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await openTrim(tester);
      tester.semantics.decrease(find.semantics.byLabel(strings.editor.trimEnd));
      await tester.pump();
      var trim = (await h.export(tester)).trim!;
      expect(trim.end, const Duration(milliseconds: 59500));

      await tester.tap(find.bySemanticsLabel(strings.editor.trim));
      await tester.pump();
      tester.semantics.increase(
        find.semantics.byLabel(strings.editor.trimStart),
      );
      await tester.pump();
      trim = (await h.export(tester)).trim!;
      expect(trim.start, const Duration(milliseconds: 500));
      handle.dispose();
    });

    testWidgets('trim is hidden for photos', (tester) async {
      await pumpEditor(tester);
      expect(find.bySemanticsLabel(strings.editor.trim), findsNothing);
    });
  });

  group('audio mix (AC13)', () {
    testWidgets('original volume, mute and music volume reach the players', (
      tester,
    ) async {
      final h = await pumpEditor(
        tester,
        media: _video(),
        document: (media) =>
            StoryDocument(media: media, music: _music(media.path.dirOf)),
      );
      await tester.tap(find.bySemanticsLabel(strings.editor.audio));
      await tester.pump();
      expect(find.byType(Slider), findsNWidgets(2));

      // Drag the original-audio slider to the left end.
      await tester.drag(find.byType(Slider).first, const Offset(-400, 0));
      await tester.pump();
      await tester.pump();
      expect(h.video.single.volume, 0);
      expect(find.bySemanticsLabel(strings.editor.unmute), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(strings.editor.unmute));
      await tester.pump();
      await tester.pump();
      expect(h.video.single.volume, 1);
      await tester.tap(find.bySemanticsLabel(strings.editor.mute));
      await tester.pump();
      await tester.pump();
      expect(h.video.single.volume, 0);

      await tester.drag(find.byType(Slider).last, const Offset(-400, 0));
      await tester.pump();
      await tester.pump();
      expect(h.music.single.volume, 0);

      final doc = await h.export(tester);
      expect(doc.originalVolume, 0);
      expect(doc.music!.volume, 0);
    });

    testWidgets('music slider hidden without music', (tester) async {
      await pumpEditor(tester, media: _video());
      await tester.tap(find.bySemanticsLabel(strings.editor.audio));
      await tester.pump();
      expect(find.byType(Slider), findsOneWidget);
    });
  });

  group('music button', () {
    testWidgets('hidden without a music provider', (tester) async {
      await pumpEditor(tester);
      expect(find.bySemanticsLabel(strings.editor.music), findsNothing);
    });

    testWidgets('opens the picker and pauses playback meanwhile', (
      tester,
    ) async {
      final h = await pumpEditor(
        tester,
        media: _video(),
        musicProvider: FakeMusicProvider(),
      );
      final video = h.video.single;
      expect(video.state.value.playing, isTrue);
      await tester.tap(find.bySemanticsLabel(strings.editor.music));
      await tester.pump();
      await tester.pump();
      expect(video.state.value.playing, isFalse);
      expect(
        h.events.where((e) => e.type == StoryEventType.toolOpened),
        isNotEmpty,
      );
    });
  });

  testWidgets('filter previews of a video use its first frame', (tester) async {
    final h = await pumpEditor(tester, media: _video());
    await tester.tap(find.bySemanticsLabel(strings.editor.filters).first);
    await tester.pump();
    final previews = tester
        .widgetList<Image>(find.byType(Image))
        .map((i) => i.image)
        .whereType<ResizeImage>()
        .map((r) => (r.imageProvider as FileImage).file.path)
        .toSet();
    // The fake inspector "extracts" frames by returning the video path.
    expect(previews, {h.video.single.openedPath});
  });

  testWidgets('background colours come from the photo, without an undo step', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('palette');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/two_tone.png';
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
        ..drawRect(
          const Rect.fromLTWH(0, 0, 40, 30),
          Paint()..color = const Color(0xFFD03030),
        )
        ..drawRect(
          const Rect.fromLTWH(0, 30, 40, 30),
          Paint()..color = const Color(0xFF3050D0),
        );
      final image = await recorder.endRecording().toImage(40, 60);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File(path).writeAsBytesSync(png!.buffer.asUint8List());
    });
    final h = await pumpEditor(
      tester,
      media: (_) => StoryMedia(
        path: path,
        type: StoryMediaType.photo,
        width: 40,
        height: 60,
        source: StorySourceKind.gallery,
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    final doc = await h.export(tester);
    expect(doc.background, isNot(const StoryBackground()));
    final top = HSVColor.fromColor(doc.background.top);
    final bottom = HSVColor.fromColor(doc.background.bottom);
    expect(top.hue, anyOf(lessThan(30), greaterThan(330)));
    expect(bottom.hue, inInclusiveRange(200, 260));
    // Darkened.
    expect(
      top.value,
      lessThan(HSVColor.fromColor(const Color(0xFFD03030)).value),
    );
    expect(
      bottom.value,
      lessThan(HSVColor.fromColor(const Color(0xFF3050D0)).value),
    );
    // Not an edit: undo stays disabled and back does not ask.
    await tester.tap(find.bySemanticsLabel(strings.common.close));
    await tester.pump();
    expect(h.backs, 1);
  });
}

extension on String {
  Directory get dirOf => File(this).parent;
}
