// ignore_for_file: unused_element, unused_import, unused_local_variable
// Screenshot tour (visual review, not an assertion suite).
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

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, 1200);
    debugPrint('SHOT:$name');
    await settle(tester, 2500);
  }

  testWidgets('screenshot tour', (tester) async {
    await openCreator(tester);
    await shot(tester, '01_camera');
    await tester.tap(find.byKey(const ValueKey('story_camera_gallery')));
    await pumpUntil(tester, find.byKey(const ValueKey('story_gallery_grid')));
    await shot(tester, '02_gallery');
    final video = find.bySemanticsLabel(RegExp(r'^Video'));
    await pumpUntil(tester, video);
    await tester.tap(video.first);
    await pumpUntil(tester, label('Share story'), reason: 'editor');
    await shot(tester, '03_editor_video');
    await tapLabel(tester, 'Trim');
    await shot(tester, '04_trim');
    await tapLabel(tester, 'Trim');
    await tapLabel(tester, 'Audio');
    await shot(tester, '05_audio');
    await tapLabel(tester, 'Audio');
    await tapLabel(tester, 'Text');
    await pumpUntil(tester, find.byType(EditableText));
    await tester.enterText(find.byType(EditableText), 'Moon night\nstory');
    await shot(tester, '06_text_edit');
    await tapLabel(tester, 'Done');
    await shot(tester, '07_text_placed');
    await tapLabel(tester, 'Draw');
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final c = screen.center(Offset.zero);
    await tester.dragFrom(c.translate(-120, 200), const Offset(240, -60));
    await shot(tester, '08_draw');
    await tapLabel(tester, 'Done');
    await tapLabel(tester, 'Stickers');
    await shot(tester, '09_stickers');
    await tester.tap(find.bySemanticsLabel(RegExp('star')).first);
    await settle(tester);
    await tapLabel(tester, 'Filters');
    await shot(tester, '10_filters');
    await tapLabel(tester, 'Filters');
    await tapLabel(tester, 'Music');
    await pumpUntil(tester, find.byTooltip('Use this track'));
    await shot(tester, '11_music');
    await tester.tap(find.byTooltip('Use this track').first);
    await pumpUntil(tester, find.byKey(const ValueKey('music-segment-window')));
    await shot(tester, '12_segment');
    await tester.tap(find.byTooltip('Done').last);
    await pumpUntil(tester, label('Share story'));
    await shot(tester, '13_editor_done');
    await tapLabel(tester, 'Share story');
    await settle(tester, 300);
    debugPrint('SHOT:14_exporting');
    await pumpUntil(
      tester,
      find.text('Use story'),
      timeout: const Duration(seconds: 240),
    );
    await shot(tester, '15_preview');
    await tester.tap(find.text('Use story'));
    await pumpUntil(tester, find.byKey(const ValueKey('result-page')));
    await shot(tester, '16_result');
  });
}
