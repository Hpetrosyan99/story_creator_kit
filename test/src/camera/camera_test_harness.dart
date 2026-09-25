import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/services.dart';
import 'package:story_creator_kit/src/camera/camera_screen.dart';
import 'package:story_creator_kit/src/core/story_scope.dart';
import 'package:story_creator_kit/src/render/painters/story_paint_resources_loader.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

import '../../fakes/fake_services.dart';

/// Video probe used by most recording tests.
MediaProbe videoProbe(Duration duration, {bool hasAudio = true}) => MediaProbe(
  width: 1080,
  height: 1920,
  fileSizeBytes: 10,
  duration: duration,
  hasVideo: true,
  hasAudio: hasAudio,
);

/// Builds a camera screen over fakes and records what it reports.
class CameraHarness {
  CameraHarness({
    this.config = const StoryCreatorConfig(),
    FakeCaptureService? capture,
    FakePermissionService? permissions,
    FakeGallerySource? gallery,
    FakeMediaInspector? inspector,
  }) : root = Directory.systemTemp.createTempSync('story_camera_test_') {
    captures = Directory('${root.path}/captures')..createSync();
    session = SessionFiles.at(Directory('${root.path}/session')..createSync());
    this.capture = capture ?? FakeCaptureService(makeFile: makeCaptureFile);
    this.permissions = permissions ?? FakePermissionService();
    this.gallery =
        gallery ??
        FakeGallerySource(resolvePath: (a) => makeCaptureFile(a.type));
    this.inspector = inspector ?? FakeMediaInspector();
  }

  final StoryCreatorConfig config;
  final Directory root;
  late final Directory captures;
  late final SessionFiles session;
  late final FakeCaptureService capture;
  late final FakePermissionService permissions;
  late final FakeGallerySource gallery;
  late final FakeMediaInspector inspector;

  final List<StoryMedia> media = [];
  final List<StoryEvent> events = [];
  int closed = 0;
  int _files = 0;

  /// Creates a small file synchronously (works inside fake async zones).
  Future<String> makeCaptureFile(StoryMediaType type) async {
    _files++;
    final ext = type == StoryMediaType.photo ? 'jpg' : 'mp4';
    final file = File('${captures.path}/capture_$_files.$ext')
      ..writeAsBytesSync(const [1, 2, 3, 4]);
    return file.path;
  }

  StoryServices get services => fakeServices(
    tempDir: root,
    capture: capture,
    gallery: gallery,
    permissions: permissions,
    inspector: inspector,
  );

  /// The scope around [child], inside a MaterialApp (for routes).
  Widget wrap(Widget child) {
    final configured = StoryCreatorConfig(
      theme: config.theme,
      strings: config.strings,
      capture: config.capture,
      constraints: config.constraints,
      editor: config.editor,
      output: config.output,
      musicProvider: config.musicProvider,
      onEvent: events.add,
    );
    return MaterialApp(
      home: Material(
        child: StoryScope(
          config: configured,
          services: services,
          session: session,
          resources: createStoryPaintResources(configured.editor),
          child: child,
        ),
      ),
    );
  }

  Widget screen() =>
      wrap(CameraScreen(onMediaReady: media.add, onClose: () => closed++));

  /// Pumps the camera screen on a phone-sized view and lets it start.
  Future<void> pump(WidgetTester tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(screen());
    await settle(tester);
  }

  void dispose() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  }
}

/// A 360×780 logical-pixel portrait view (1080×2340 at 3×).
void usePhoneView(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1080, 2340)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Runs a route transition to its end.
Future<void> finishTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await settle(tester);
}

/// Lets real file I/O started inside the fake async zone finish, then
/// flushes microtasks and frames. Repeats for chained operations.
Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
}

/// Presses the shutter long enough to start a recording and returns the
/// gesture (still down).
Future<TestGesture> holdShutter(WidgetTester tester, Finder shutter) async {
  final gesture = await tester.startGesture(tester.getCenter(shutter));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  return gesture;
}
