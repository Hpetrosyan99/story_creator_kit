import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/src/api/config/editor_options.dart';
import 'package:story_creator_kit/src/api/config/output_options.dart';
import 'package:story_creator_kit/src/api/config/story_creator_config.dart';
import 'package:story_creator_kit/src/api/errors/story_exception.dart';
import 'package:story_creator_kit/src/api/events/story_event.dart';
import 'package:story_creator_kit/src/api/result/story_result.dart';
import 'package:story_creator_kit/src/api/strings/story_creator_strings.dart';
import 'package:story_creator_kit/src/core/session_files.dart';
import 'package:story_creator_kit/src/core/story_scope.dart';
import 'package:story_creator_kit/src/preview/preview_screen.dart';
import 'package:story_creator_kit/src/render/painters/story_paint_resources_loader.dart';
import 'package:story_creator_kit/src/services/export/story_exporter.dart';

import '../../fakes/fake_services.dart';

const _strings = ExportStrings();

void main() {
  late Directory dir;
  late FakeGallerySaver saver;
  late FakeVideoSession video;
  late List<bool> confirms;
  late int backs;
  late List<StoryEvent> events;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('preview');
    saver = FakeGallerySaver();
    video = FakeVideoSession();
    confirms = [];
    backs = 0;
    events = [];
  });

  tearDown(() async => dir.delete(recursive: true));

  ExportedStory photo() {
    final file = File('${dir.path}/story.png')
      ..writeAsBytesSync(kTransparentPng);
    return ExportedStory(
      path: file.path,
      type: StoryMediaType.photo,
      width: 1080,
      height: 1920,
      fileSizeBytes: kTransparentPng.length,
    );
  }

  ExportedStory clip() => ExportedStory(
    path: '${dir.path}/story.mp4',
    type: StoryMediaType.video,
    width: 1080,
    height: 1920,
    fileSizeBytes: 10,
    duration: const Duration(seconds: 3),
  );

  Future<void> pump(
    WidgetTester tester,
    ExportedStory story, {
    SaveToGalleryMode mode = SaveToGalleryMode.button,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StoryScope(
          config: StoryCreatorConfig(
            output: OutputOptions(saveToGallery: mode, galleryAlbum: 'Album'),
            onEvent: events.add,
          ),
          services: fakeServices(
            tempDir: dir,
            saver: saver,
            video: () => video,
          ),
          session: SessionFiles.at(dir),
          resources: createStoryPaintResources(const EditorOptions()),
          child: PreviewScreen(
            story: story,
            onConfirm: ({required savedToGallery}) =>
                confirms.add(savedToGallery),
            onBack: () => backs++,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('photo: "Use story" confirms without a save', (tester) async {
    await pump(tester, photo());
    expect(find.bySemanticsLabel(_strings.photoPreview), findsOneWidget);
    await tester.tap(find.text(_strings.useStory));
    await tester.pump();
    expect(confirms, [false]);
    // A second tap does nothing.
    await tester.tap(find.text(_strings.useStory));
    expect(confirms, [false]);
  });

  testWidgets('"Edit" goes back', (tester) async {
    await pump(tester, photo());
    await tester.tap(find.bySemanticsLabel(_strings.backToEditor));
    await tester.pump();
    expect(backs, 1);
    expect(confirms, isEmpty);
  });

  testWidgets('system back goes back to the editor', (tester) async {
    await pump(tester, photo());
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(backs, 1);
  });

  testWidgets('save succeeds: toast, button disabled, confirm reports it', (
    tester,
  ) async {
    final story = photo();
    await pump(tester, story);
    await tester.tap(find.bySemanticsLabel(_strings.saveToGallery));
    await tester.pump();
    expect(saver.saved, [story.path]);
    expect(find.text(_strings.savedToGallery), findsOneWidget);
    expect(find.bySemanticsLabel(_strings.savedLabel), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(_strings.savedLabel));
    await tester.pump();
    expect(saver.saved, hasLength(1));
    await tester.tap(find.text(_strings.useStory));
    expect(confirms, [true]);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text(_strings.savedToGallery), findsNothing);
  });

  testWidgets('save fails: error toast, reported, can retry', (tester) async {
    saver.error = const StoryException(StoryErrorCode.saveToGalleryFailed);
    await pump(tester, photo());
    await tester.tap(find.bySemanticsLabel(_strings.saveToGallery));
    await tester.pump();
    expect(find.text(_strings.saveFailed), findsOneWidget);
    expect(events.single.error?.code, StoryErrorCode.saveToGalleryFailed);
    saver.error = null;
    await tester.tap(find.bySemanticsLabel(_strings.saveToGallery));
    await tester.pump();
    expect(saver.saved, hasLength(1));
    await tester.tap(find.text(_strings.useStory));
    expect(confirms, [true]);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('no save button unless the mode is button', (tester) async {
    await pump(tester, photo(), mode: SaveToGalleryMode.always);
    expect(find.bySemanticsLabel(_strings.saveToGallery), findsNothing);
  });

  testWidgets('video: plays the exported file in a loop', (tester) async {
    final story = clip();
    await pump(tester, story);
    await tester.pump();
    expect(video.openedPath, story.path);
    expect(video.range, isNull);
    expect(video.state.value.playing, isTrue);
    expect(find.bySemanticsLabel(_strings.videoPreview), findsOneWidget);
    await tester.tap(find.text(_strings.useStory));
    expect(confirms, [false]);
    expect(video.state.value.playing, isFalse);
  });

  testWidgets('controls meet tap-target guidelines', (tester) async {
    await pump(tester, photo());
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });
}
