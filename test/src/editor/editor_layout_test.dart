import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/services.dart';
import 'package:story_creator_kit/src/editor/editor_keys.dart';
import 'package:story_creator_kit/src/music/music_picker_screen.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

import '../../fakes/fake_services.dart';
import 'editor_test_harness.dart';

const _track = MusicTrack(
  id: 'breath',
  title: 'Every breath you take',
  artist: 'The police',
  duration: Duration(minutes: 3, seconds: 49),
);

StoryDocument Function(StoryMedia) _withMusic() =>
    (media) => StoryDocument(
      media: media,
      music: const MusicSelection(
        track: _track,
        start: Duration.zero,
        duration: Duration(seconds: 15),
        localPath: '/tmp/breath.m4a',
      ),
    );

StoryDocument Function(StoryMedia) _withText(String text) =>
    (media) => StoryDocument(
      media: media,
      overlays: [
        TextOverlay(
          id: 'text-$text',
          transform: const OverlayTransform(position: Offset(540, 600)),
          text: text,
          style: const TextOverlayStyle(
            fontId: 'system',
            color: Color(0xFFFFFFFF),
          ),
        ),
      ],
    );

void main() {
  group('tool column', () {
    testWidgets('shows music, text and stickers; More reveals the rest', (
      tester,
    ) async {
      await pumpEditor(tester, musicProvider: FakeMusicProvider());
      final editor = strings.editor;
      expect(find.bySemanticsLabel(editor.music), findsOneWidget);
      expect(find.bySemanticsLabel(editor.text), findsOneWidget);
      expect(find.bySemanticsLabel(editor.stickers), findsOneWidget);
      expect(find.bySemanticsLabel(editor.draw), findsNothing);
      expect(find.bySemanticsLabel(editor.undo), findsNothing);

      final musicBefore = tester.getCenter(find.bySemanticsLabel(editor.music));
      await tester.tap(find.byKey(EditorKeys.moreTools));
      await tester.pump();
      // Mid-animation the main icons stay where they were.
      await tester.pump(const Duration(milliseconds: 140));
      expect(
        tester.getCenter(find.bySemanticsLabel(editor.music)),
        musicBefore,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.getCenter(find.bySemanticsLabel(editor.music)),
        musicBefore,
      );
      expect(find.bySemanticsLabel(editor.draw), findsOneWidget);
      expect(find.bySemanticsLabel(editor.filters), findsOneWidget);
      expect(find.bySemanticsLabel(editor.undo), findsOneWidget);
      expect(find.bySemanticsLabel(editor.redo), findsOneWidget);
      expect(find.bySemanticsLabel(editor.fewerTools), findsOneWidget);
      // Tools stay 42 px apart (36 px circle + 6 px gap).
      final music = tester.getCenter(find.bySemanticsLabel(editor.music));
      final text = tester.getCenter(find.bySemanticsLabel(editor.text));
      expect(text.dy - music.dy, 42);

      await tester.tap(find.byKey(EditorKeys.moreTools));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.bySemanticsLabel(editor.draw), findsNothing);
      expect(find.bySemanticsLabel(editor.moreTools), findsOneWidget);
    });

    testWidgets('undo and redo work from the expanded column', (tester) async {
      final h = await pumpEditor(tester, document: _withText('A'));
      await openMoreTools(tester);
      await tester.tap(find.bySemanticsLabel(strings.editor.adjust));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(strings.editor.delete));
      await tester.pump();
      expect((await h.export(tester)).overlays, isEmpty);
      await tester.tap(find.bySemanticsLabel(strings.editor.undo));
      await tester.pump();
      expect((await h.export(tester)).overlays, hasLength(1));
      await tester.tap(find.bySemanticsLabel(strings.editor.redo));
      await tester.pump();
      expect((await h.export(tester)).overlays, isEmpty);
    });
  });

  group('music chip', () {
    testWidgets('hidden without music', (tester) async {
      await pumpEditor(tester, musicProvider: FakeMusicProvider());
      expect(find.byKey(EditorKeys.musicChip), findsNothing);
    });

    testWidgets('shows title and "Artist | mm:ss" and opens the picker', (
      tester,
    ) async {
      final h = await pumpEditor(
        tester,
        musicProvider: FakeMusicProvider(),
        document: _withMusic(),
      );
      expect(find.text('Every breath you take'), findsOneWidget);
      expect(find.text('The police | 03:49'), findsOneWidget);
      expect(
        find.bySemanticsLabel(strings.editor.selectedMusic),
        findsOneWidget,
      );
      await tester.tap(find.byKey(EditorKeys.musicChip));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(MusicPickerScreen), findsOneWidget);
      expect(
        h.events.where(
          (e) =>
              e.type == StoryEventType.toolOpened &&
              e.properties['tool'] == 'music',
        ),
        isNotEmpty,
      );
    });

    testWidgets('an open tool panel hides the thumbnail and the chip', (
      tester,
    ) async {
      await pumpEditor(
        tester,
        musicProvider: FakeMusicProvider(),
        document: _withMusic(),
      );
      expect(find.byKey(EditorKeys.replaceMedia), findsOneWidget);
      await openMoreTools(tester);
      await tester.tap(find.bySemanticsLabel(strings.editor.filters));
      await tester.pump();
      expect(find.byKey(EditorKeys.musicChip), findsNothing);
      expect(find.byKey(EditorKeys.replaceMedia), findsNothing);
    });
  });

  group('gallery thumbnail', () {
    testWidgets('hidden when the gallery is disabled', (tester) async {
      await pumpEditor(
        tester,
        capture: const CaptureOptions(galleryMode: GalleryMode.disabled),
      );
      expect(find.byKey(EditorKeys.replaceMedia), findsNothing);
    });

    testWidgets('replaces the media, keeps the text, and undoes', (
      tester,
    ) async {
      final pickDir = Directory.systemTemp.createTempSync('editor_pick');
      addTearDown(() => pickDir.deleteSync(recursive: true));
      final picked = File('${pickDir.path}/new.png')
        ..writeAsBytesSync(kTransparentPng);
      final gallery =
          FakeGallerySource(grid: false, resolvePath: (_) async => picked.path)
            ..systemPick = PickedMedia(
              path: picked.path,
              type: StoryMediaType.photo,
            );
      final h = await pumpEditor(
        tester,
        document: _withText('Keep me'),
        gallery: gallery,
        capture: const CaptureOptions(galleryMode: GalleryMode.systemPicker),
      );
      h.inspector.defaultProbe = const MediaProbe(
        width: 1920,
        height: 1080,
        fileSizeBytes: 70,
      );
      final original = (await h.export(tester)).media;

      await tester.tap(find.byKey(EditorKeys.replaceMedia));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(gallery.systemPickCalls, 1);
      final replaced = await h.export(tester);
      expect(replaced.media.path, isNot(original.path));
      expect(replaced.media.path, startsWith(h.dir.path));
      expect(replaced.media.width, 1920);
      expect(replaced.overlays.single, isA<TextOverlay>());
      expect((replaced.overlays.single as TextOverlay).text, 'Keep me');
      expect(
        h.events.where((e) => e.type == StoryEventType.mediaPicked),
        hasLength(1),
      );

      await openMoreTools(tester);
      await tester.tap(find.bySemanticsLabel(strings.editor.undo));
      await tester.pump();
      final undone = await h.export(tester);
      expect(undone.media, original);
      expect((undone.overlays.single as TextOverlay).text, 'Keep me');
    });
  });
}
