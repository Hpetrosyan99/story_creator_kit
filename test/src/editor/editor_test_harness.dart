import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/services.dart';
import 'package:story_creator_kit/src/core/story_canvas.dart';
import 'package:story_creator_kit/src/core/story_scope.dart';
import 'package:story_creator_kit/src/editor/canvas/story_canvas_view.dart';
import 'package:story_creator_kit/src/editor/editor_screen.dart';
import 'package:story_creator_kit/src/render/painters/story_paint_resources_loader.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

import '../../fakes/fake_services.dart';

/// Default strings, for finders.
const strings = StoryCreatorStrings();

/// A photo that fills the canvas.
StoryMedia photoMedia(Directory dir) => StoryMedia(
  path: '${dir.path}/missing_photo.jpg',
  type: StoryMediaType.photo,
  width: 1080,
  height: 1920,
  source: StorySourceKind.gallery,
);

/// A video with audio.
StoryMedia videoMedia(
  Directory dir, {
  Duration duration = const Duration(seconds: 20),
  bool hasAudio = true,
}) => StoryMedia(
  path: '${dir.path}/missing_video.mp4',
  type: StoryMediaType.video,
  width: 1080,
  height: 1920,
  source: StorySourceKind.gallery,
  duration: duration,
  hasAudio: hasAudio,
);

/// What happened in a pumped editor.
class EditorHarness {
  EditorHarness({
    required this.dir,
    required this.resources,
    required this.video,
    required this.music,
    required this.inspector,
    required this.active,
  });

  /// Session / temp directory.
  final Directory dir;

  /// Paint resources used by the editor.
  final StoryPaintResources resources;

  /// The video session, if one was created.
  final List<FakeVideoSession> video;

  /// The music sessions created.
  final List<FakeMusicSession> music;

  /// Media inspector.
  final FakeMediaInspector inspector;

  /// Toggles `EditorScreen.active`.
  final ValueNotifier<bool> active;

  /// Documents passed to `onExport`.
  final List<StoryDocument> exported = [];

  /// Number of `onBack` calls.
  int backs = 0;

  /// Reported events.
  final List<StoryEvent> events = [];

  /// Haptic feedback calls (`HapticFeedbackType.*`).
  final List<String> haptics = [];

  /// Taps ✓ and returns the exported document.
  Future<StoryDocument> export(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel(strings.editor.export));
    await tester.pump();
    return exported.last;
  }
}

/// Screen pixels per canvas unit of the pumped canvas.
double viewScaleOf(WidgetTester tester) =>
    tester.getSize(find.byType(StoryCanvasView)).width / StoryCanvas.width;

/// Global position of the canvas point [p].
Offset canvasPoint(WidgetTester tester, Offset p) =>
    tester.getTopLeft(find.byType(StoryCanvasView)) + p * viewScaleOf(tester);

/// Pumps the editor with fakes.
Future<EditorHarness> pumpEditor(
  WidgetTester tester, {
  StoryMedia Function(Directory dir)? media,
  StoryDocument Function(StoryMedia media)? document,
  EditorOptions editor = const EditorOptions(),
  MediaConstraints constraints = const MediaConstraints(),
  StoryMusicProvider? musicProvider,
  Duration videoDuration = const Duration(seconds: 20),
  Size size = const Size(390, 844),
  bool disableAnimations = false,
  bool accessibleNavigation = false,
}) async {
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  resetStoryFontLoads();

  final dir = Directory.systemTemp.createTempSync('editor_test');
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  final sourceMedia = (media ?? photoMedia)(dir);
  final initial =
      document?.call(sourceMedia) ??
      StoryDocument(
        media: sourceMedia,
        placement: StoryCanvas.defaultPlacement(sourceMedia),
      );
  final videos = <FakeVideoSession>[];
  final musics = <FakeMusicSession>[];
  final inspector = FakeMediaInspector();
  final config = StoryCreatorConfig(
    editor: editor,
    constraints: constraints,
    musicProvider: musicProvider,
  );
  final resources = createStoryPaintResources(editor);
  final harness = EditorHarness(
    dir: dir,
    resources: resources,
    video: videos,
    music: musics,
    inspector: inspector,
    active: ValueNotifier(true),
  );
  final configWithEvents = StoryCreatorConfig(
    editor: config.editor,
    constraints: config.constraints,
    musicProvider: config.musicProvider,
    onEvent: harness.events.add,
  );
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        harness.haptics.add('${call.arguments}');
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  final services = fakeServices(
    tempDir: dir,
    inspector: inspector,
    video: () {
      final session = FakeVideoSession(duration: videoDuration);
      videos.add(session);
      return session;
    },
    music: () {
      final session = FakeMusicSession();
      musics.add(session);
      return session;
    },
  );
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          devicePixelRatio: 3,
          disableAnimations: disableAnimations,
          accessibleNavigation: accessibleNavigation,
        ),
        child: StoryScope(
          config: configWithEvents,
          services: services,
          session: SessionFiles.at(dir),
          resources: resources,
          child: ValueListenableBuilder<bool>(
            valueListenable: harness.active,
            builder: (context, active, _) => EditorScreen(
              initialDocument: initial,
              active: active,
              onExport: harness.exported.add,
              onBack: () => harness.backs++,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return harness;
}

/// Opens the text editor by tapping the empty canvas at [at], types [text]
/// and taps Done.
Future<void> addText(
  WidgetTester tester,
  String text, {
  Offset at = const Offset(540, 300),
}) async {
  await tester.tapAt(canvasPoint(tester, at));
  await tester.pump();
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.bySemanticsLabel(strings.common.done));
  await tester.pump();
}
