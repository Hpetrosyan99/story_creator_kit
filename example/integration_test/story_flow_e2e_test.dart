// End-to-end journeys through the real example app on a simulator/emulator:
// real permission, gallery, video, music and native export services; only
// the camera is simulated on the iOS Simulator (it has no camera).
//
// Grant permissions first on the iOS Simulator so no system dialog blocks:
//   xcrun simctl privacy <udid> grant camera com.mabrook.storyCreatorKitExample
//   (and microphone, photos, photos-add)
//
//   cd example && flutter test integration_test/story_flow_e2e_test.dart -d <device>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:story_creator_kit/services.dart';
import 'package:story_creator_kit/story_creator_kit.dart';
import 'package:story_creator_kit/src/services/media/native_media_inspector.dart';
import 'package:story_creator_kit_example/main.dart';
import 'package:story_creator_kit_example/result_page.dart';

const _shutter = ValueKey<String>('story_camera_shutter');
const _cameraClose = ValueKey<String>('story_camera_close');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final MediaInspector inspector = NativeMediaInspector();
  var step = 'start';
  AppLifecycleListener(
    onStateChange: (state) =>
        debugPrint('LIFECYCLE ${state.name} during "$step"'),
  );

  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 30),
    String? reason,
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) {
        return;
      }
    }
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? t.textSpan?.toPlainText())
        .whereType<String>()
        .toList();
    final keys = find
        .byWidgetPredicate((w) => w.key is ValueKey<String>)
        .evaluate()
        .map((e) => (e.widget.key! as ValueKey<String>).value)
        .toSet();
    fail(
      'Timed out waiting for ${reason ?? finder}. Visible texts: $texts. '
      'Keys: $keys. Lifecycle: ${WidgetsBinding.instance.lifecycleState}',
    );
  }

  Future<void> settle(WidgetTester tester, [int ms = 600]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openCreator(WidgetTester tester) async {
    await tester.pumpWidget(const StoryKitExampleApp());
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('create-story')));
    await pumpUntil(tester, find.byKey(_shutter), reason: 'camera shutter');
    // Wait for the (simulated) camera to be ready.
    await pumpUntil(
      tester,
      find.byKey(const ValueKey<String>('story_camera_preview')),
      reason: 'camera preview',
    );
    await settle(tester);
  }

  Finder label(String text) => find.bySemanticsLabel(text);

  Future<void> tapLabel(WidgetTester tester, String text) async {
    step = 'tap $text';
    await pumpUntil(tester, label(text), reason: 'control "$text"');
    await tester.tap(label(text).last);
    await settle(tester);
  }

  Future<void> exportAndConfirm(
    WidgetTester tester, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    await tapLabel(tester, 'Share story');
    await pumpUntil(
      tester,
      find.text('Use story'),
      timeout: timeout,
      reason: 'preview after export',
    );
    await settle(tester, 1000);
    await tester.tap(find.text('Use story'));
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('result-page')),
      reason: 'result page',
    );
    await settle(tester);
  }

  StoryResult result(WidgetTester tester) =>
      tester.widget<ResultPage>(find.byType(ResultPage)).result;

  String resultPath(WidgetTester tester) => result(tester).path;

  testWidgets('photo with text, emoji and drawing exports a 1080x1920 JPEG', (
    tester,
  ) async {
    await openCreator(tester);
    await tester.tap(find.byKey(_shutter));
    await pumpUntil(tester, label('Share story'), reason: 'editor');
    await settle(tester, 1000);

    // Text overlay.
    await tapLabel(tester, 'Text');
    await pumpUntil(tester, find.byType(EditableText), reason: 'text field');
    await tester.enterText(find.byType(EditableText), 'Hello story');
    await settle(tester);
    await tapLabel(tester, 'Done');

    // Emoji.
    await tapLabel(tester, 'Stickers');
    await tapLabel(tester, 'Emoji');
    await tester.tap(find.text('🔥').first);
    await settle(tester);

    // Drawing.
    await tapLabel(tester, 'Draw');
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final canvas = screen.center(Offset.zero);
    await tester.dragFrom(canvas.translate(-80, 120), const Offset(160, 60));
    await settle(tester);
    await tapLabel(tester, 'Done');

    await exportAndConfirm(tester);

    final path = resultPath(tester);
    expect(File(path).existsSync(), isTrue, reason: path);
    final bytes = await File(path).readAsBytes();
    expect(bytes.sublist(0, 2), [0xFF, 0xD8], reason: 'JPEG magic');
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1080);
    expect(frame.image.height, 1920);
    final metadata = result(tester).metadata;
    expect(metadata.texts.map((t) => t.text), ['Hello story']);
    expect(metadata.emojis, ['🔥']);
    expect(metadata.hasDrawing, isTrue);
    expect(metadata.source, StorySourceKind.camera);
  });

  testWidgets('photo with music exports an MP4 with audio', (tester) async {
    await openCreator(tester);
    await tester.tap(find.byKey(_shutter));
    await pumpUntil(tester, label('Share story'), reason: 'editor');
    await settle(tester, 1000);

    await tapLabel(tester, 'Music');
    await pumpUntil(
      tester,
      find.byTooltip('Use this track'),
      reason: 'music tracks',
    );
    await tester.tap(find.byTooltip('Use this track').first);
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('music-segment-window')),
      reason: 'segment selector',
    );
    await settle(tester, 1000);
    await tester.tap(find.byTooltip('Done').last);
    await pumpUntil(tester, label('Share story'), reason: 'editor again');
    await settle(tester);

    await exportAndConfirm(tester);
    final probe = await inspector.probe(resultPath(tester));
    expect(probe.hasVideo, isTrue);
    expect(probe.hasAudio, isTrue);
    expect(probe.width, 1080);
    expect(probe.height, 1920);
    // Default photo-with-music length is 15 s.
    expect(probe.duration!.inMilliseconds, closeTo(15000, 150));
  });

  testWidgets('recorded video with muted original audio exports an MP4', (
    tester,
  ) async {
    await openCreator(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_shutter)),
    );
    await settle(tester, 2500);
    await gesture.up();
    await pumpUntil(tester, label('Share story'), reason: 'editor with video');
    await settle(tester, 1500);

    await tapLabel(tester, 'Audio');
    await tapLabel(tester, 'Mute');
    await settle(tester);

    await exportAndConfirm(tester);
    final probe = await inspector.probe(resultPath(tester));
    expect(probe.hasVideo, isTrue);
    // Muted original and no music: no audio track.
    expect(probe.hasAudio, isFalse);
    // The simulated clip is 6 s.
    expect(probe.duration!.inMilliseconds, closeTo(6000, 150));
    final metadata = result(tester).metadata;
    expect(metadata.sourceType, StoryMediaType.video);
    expect(metadata.originalAudioVolume, 0);
    expect(metadata.music, isNull);
  });

  testWidgets('back from preview returns to the editor with edits kept', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await openCreator(tester);
    await tester.tap(find.byKey(_shutter));
    await pumpUntil(tester, label('Share story'), reason: 'editor');
    await settle(tester, 1000);
    await tapLabel(tester, 'Text');
    await pumpUntil(tester, find.byType(EditableText));
    await tester.enterText(find.byType(EditableText), 'Keep me');
    await tapLabel(tester, 'Done');

    await tapLabel(tester, 'Share story');
    await pumpUntil(
      tester,
      find.text('Use story'),
      timeout: const Duration(seconds: 90),
      reason: 'preview',
    );
    await settle(tester, 800);
    await tapLabel(tester, 'Edit');
    await pumpUntil(tester, label('Share story'), reason: 'editor after back');
    await settle(tester, 800);
    expect(find.semantics.byValue('Keep me'), findsOne);
    // Undo still has the history from before the export.
    await tapLabel(tester, 'Undo');
    expect(find.semantics.byValue('Keep me'), findsNothing);
    semantics.dispose();
  });

  testWidgets('gallery: a 70 s video opens trimmed to 60 s and exports 60 s', (
    tester,
  ) async {
    await openCreator(tester);
    await tester.tap(find.byKey(const ValueKey('story_camera_gallery')));
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('story_gallery_grid')),
      reason: 'gallery grid (photo access must be granted)',
    );
    final video = find.bySemanticsLabel(RegExp(r'^Video, 1:10'));
    await pumpUntil(tester, video, reason: '70 s video tile');
    await tester.tap(video.first);
    await pumpUntil(tester, label('Share story'), reason: 'editor');
    await settle(tester, 1500);

    await exportAndConfirm(tester, timeout: const Duration(seconds: 240));
    final r = result(tester);
    expect(r.type, StoryMediaType.video);
    expect(r.metadata.source, StorySourceKind.gallery);
    expect(r.metadata.trimStart, Duration.zero);
    expect(r.metadata.trimEnd, const Duration(seconds: 60));
    final probe = await inspector.probe(r.path);
    expect(probe.duration!.inMilliseconds, closeTo(60000, 150));
    expect(probe.hasAudio, isTrue);
  });

  testWidgets('gallery: a photo exports as JPEG', (tester) async {
    await openCreator(tester);
    await tester.tap(find.byKey(const ValueKey('story_camera_gallery')));
    await pumpUntil(tester, find.byKey(const ValueKey('story_gallery_grid')));
    final photo = find.bySemanticsLabel('Photo');
    await pumpUntil(tester, photo, reason: 'photo tile');
    await tester.tap(photo.first);
    await pumpUntil(tester, label('Share story'), reason: 'editor');
    await settle(tester, 1000);
    await exportAndConfirm(tester);
    final r = result(tester);
    expect(r.type, StoryMediaType.photo);
    expect(r.metadata.source, StorySourceKind.gallery);
    expect(r.width, 1080);
    expect(r.height, 1920);
  });

  testWidgets('closing the camera returns StoryCancelled', (tester) async {
    await openCreator(tester);
    await tester.tap(find.byKey(_cameraClose));
    await pumpUntil(
      tester,
      find.text('Cancelled (userCancelled)'),
      reason: 'cancelled outcome',
    );
  });
}
