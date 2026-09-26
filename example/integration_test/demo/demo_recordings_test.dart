// Scripted demo journeys for the pub.dev recordings.
//
// Not an assertion suite. It prints `REC_START <name>` / `REC_STOP` markers
// that tool/record_demos.sh turns into `simctl recordVideo` sessions. A
// silent warm-up pass runs every journey first in the same app session, so
// the recorded passes are free of first-use stutter (debug JIT, caches).
//
//   ./tool/record_demos.sh
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:story_creator_kit_example/main.dart';

const _shutter = ValueKey<String>('story_camera_shutter');
const _gallery = ValueKey<String>('story_camera_gallery');
const _grid = ValueKey<String>('story_gallery_grid');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> wait(WidgetTester tester, [int ms = 700]) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> until(
    WidgetTester tester,
    Finder finder, {
    int seconds = 60,
  }) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 16));
      if (finder.evaluate().isNotEmpty) {
        return;
      }
    }
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .take(25)
        .toList();
    fail('Timed out waiting for $finder. Visible texts: $texts');
  }

  Finder label(String text) => find.bySemanticsLabel(text);

  Future<void> tapLabel(
    WidgetTester tester,
    String text, [
    int after = 700,
  ]) async {
    for (var i = 0; i < 20 && label(text).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (label(text).evaluate().isEmpty &&
        label('More tools').evaluate().isNotEmpty) {
      await tester.tap(label('More tools').last);
      await wait(tester, 600);
    }
    await until(tester, label(text));
    await tester.tap(label(text).last);
    await wait(tester, after);
  }

  Offset screenCenter(WidgetTester tester) {
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    return size.center(Offset.zero);
  }

  /// A smooth one-finger drag through [points] (relative to [from]).
  Future<void> glide(
    WidgetTester tester,
    Offset from,
    List<Offset> points, {
    int stepMs = 16,
    int steps = 8,
  }) async {
    final g = await tester.startGesture(from);
    var at = from;
    for (final p in points) {
      final target = from + p;
      final delta = (target - at) / steps.toDouble();
      for (var i = 0; i < steps; i++) {
        at += delta;
        await g.moveTo(at);
        await tester.pump(Duration(milliseconds: stepMs));
      }
    }
    await g.up();
    await tester.pump();
  }

  /// Two-finger pinch + rotate around [center].
  Future<void> pinch(
    WidgetTester tester,
    Offset center, {
    required double scale,
    required double turns,
  }) async {
    const start = 70.0;
    final a = await tester.startGesture(center + const Offset(-start, 0));
    final b = await tester.startGesture(center + const Offset(start, 0));
    const steps = 30;
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final r = start * (1 + (scale - 1) * t);
      final angle = turns * 2 * 3.1415926 * t;
      final d = Offset.fromDirection(angle, r);
      await a.moveTo(center - d);
      await b.moveTo(center + d);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await a.up();
    await b.up();
    await tester.pump();
  }

  Future<void> exportAndPreview(WidgetTester tester) async {
    await tapLabel(tester, 'Share story', 300);
    await until(tester, label('Use story'), seconds: 180);
    await wait(tester, 2800);
    await tester.tap(label('Use story').last);
    await until(tester, find.byKey(const ValueKey('result-page')));
    await wait(tester, 1500);
  }

  /// Fresh example app with the "Liquid glass buttons" switch on, back at
  /// the top of the home page.
  Future<void> launchWithGlass(WidgetTester tester) async {
    await tester.pumpWidget(const StoryKitExampleApp());
    await until(tester, find.byKey(const ValueKey('create-story')));
    await wait(tester, 600);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('liquid-glass')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('liquid-glass')));
    await wait(tester, 300);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('create-story')),
      -200,
    );
    await wait(tester, 500);
  }

  Future<void> openCreator(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('create-story')));
    await until(
      tester,
      find.byKey(const ValueKey<String>('story_camera_preview')),
    );
    await wait(tester, 1200);
  }

  // 1. Capture & create: camera, text styles, gestures, sticker, drawing.
  Future<void> captureAndCreate(WidgetTester tester) async {
    await openCreator(tester);
    // Show the sliding Video | Photo capsule.
    await tester.tap(find.text('Video'));
    await wait(tester, 900);
    await tester.tap(find.text('Photo'));
    await wait(tester, 900);
    await tester.tap(find.byKey(_shutter));
    await until(tester, label('Share story'));
    await wait(tester, 1200);

    await tapLabel(tester, 'Text', 900);
    await tester.enterText(find.byType(EditableText), 'Hello\nstory kit');
    await wait(tester, 900);
    await tapLabel(tester, 'Script', 800);
    // Cycle the background style to the per-line highlight.
    for (final style in [
      'No background',
      'Solid background',
      'Translucent background',
    ]) {
      await tapLabel(tester, style, 700);
    }
    await tapLabel(tester, 'Colour 4', 900);
    await tapLabel(tester, 'Done', 1000);

    final c = screenCenter(tester);
    await glide(tester, c, [const Offset(0, -170)], steps: 30);
    await wait(tester, 500);
    await pinch(tester, c + const Offset(0, -170), scale: 1.35, turns: -0.03);
    await wait(tester, 900);

    await tapLabel(tester, 'Stickers', 900);
    await tapLabel(tester, 'star', 1000);
    await glide(tester, c, [const Offset(90, 170)], steps: 25);
    await wait(tester, 700);

    await tapLabel(tester, 'Draw', 900);
    await glide(tester, c + const Offset(-120, 40), const [
      Offset(-60, -40),
      Offset(0, -60),
      Offset(60, -40),
      Offset(120, 0),
      Offset(170, 40),
    ], steps: 6);
    await wait(tester, 600);
    await tapLabel(tester, 'Done', 900);
    await exportAndPreview(tester);
  }

  // 2. Gallery & music: gallery photo, filter, music list, waveform segment.
  Future<void> galleryAndMusic(WidgetTester tester) async {
    await openCreator(tester);
    await tester.tap(find.byKey(_gallery));
    await until(tester, find.byKey(_grid));
    await wait(tester, 1500);
    // The grid is newest first: the simulator's built-in sample photos are
    // the oldest items, at the end. Never pick the user's own photos.
    final sample = find.bySemanticsLabel('Photo').last;
    await tester.ensureVisible(sample);
    await wait(tester, 900);
    await tester.tap(sample);
    await until(tester, label('Share story'));
    await wait(tester, 1300);

    await tapLabel(tester, 'Filters', 900);
    await tapLabel(tester, 'Warm', 900);
    await tapLabel(tester, 'Vivid', 900);
    await tapLabel(tester, 'Filters', 700);

    await tapLabel(tester, 'Music', 1200);
    await until(tester, find.text('Paper Planes'));
    await wait(tester, 800);
    await tester.tap(find.text('Leaderboard'));
    await wait(tester, 1200);
    await tester.tap(find.text('All'));
    await wait(tester, 900);
    await tester.tap(find.text('Paper Planes'));
    await until(tester, find.byKey(const ValueKey('music-waveform-strip')));
    await wait(tester, 1500);
    final strip = tester.getCenter(
      find.byKey(const ValueKey('music-waveform-strip')),
    );
    await glide(tester, strip, [const Offset(-160, 0)], steps: 40);
    await wait(tester, 2200);
    await tester.tap(find.byKey(const ValueKey('music-segment-done')));
    await until(tester, label('Share story'));
    await wait(tester, 2200);
    await exportAndPreview(tester);
  }

  // 3. Video: record, trim, mute, emoji.
  Future<void> videoAndGlass(WidgetTester tester) async {
    await openCreator(tester);
    await tester.tap(find.text('Video'));
    await wait(tester, 900);
    await tester.tap(find.byKey(_shutter));
    await wait(tester, 3000);
    await tester.tap(find.byKey(_shutter));
    await until(tester, label('Share story'));
    await wait(tester, 1800);

    await tapLabel(tester, 'Trim', 1000);
    final start = tester.getCenter(find.byKey(const ValueKey('trimStart')));
    await glide(tester, start, [const Offset(45, 0)], steps: 25);
    await wait(tester, 1300);
    await tapLabel(tester, 'Trim', 700);

    await tapLabel(tester, 'Audio', 1000);
    await tapLabel(tester, 'Mute', 1000);
    await tapLabel(tester, 'Audio', 700);

    await tapLabel(tester, 'Stickers', 900);
    await tapLabel(tester, 'Emoji', 800);
    // Adding an emoji closes the picker by itself.
    await tester.tap(find.text('🎉').first);
    await wait(tester, 1200);
    await exportAndPreview(tester);
  }

  final journeys = <String, Future<void> Function(WidgetTester)>{
    'demo_1_capture_and_create': captureAndCreate,
    'demo_2_gallery_and_music': galleryAndMusic,
    'demo_3_video_trim_and_audio': videoAndGlass,
  };

  testWidgets('warm-up', (tester) async {
    for (final journey in journeys.values) {
      await launchWithGlass(tester);
      await journey(tester);
    }
  });

  for (final MapEntry(key: name, value: journey) in journeys.entries) {
    testWidgets(name, (tester) async {
      await launchWithGlass(tester);
      print('REC_START $name');
      await wait(tester, 600);
      await journey(tester);
      print('REC_STOP');
      await wait(tester, 800);
    });
  }
}
