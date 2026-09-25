// Export matrix against the real native code (AVFoundation / Media3).
//
// Run: cd example && flutter test integration_test/export_matrix_test.dart -d <device>
//
// Sources are synthetic: PNGs drawn with dart:ui, WAV tones written here and
// the clips in integration_test/assets/ (see tool/make_fixtures.swift).
// Every output is checked with the native probe and decoded frames.
// ignore_for_file: implementation_imports

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:story_creator_kit/src/api/assets/story_filter.dart';
import 'package:story_creator_kit/src/api/assets/story_font.dart';
import 'package:story_creator_kit/src/api/config/output_options.dart';
import 'package:story_creator_kit/src/api/errors/story_exception.dart';
import 'package:story_creator_kit/src/api/music/music_models.dart';
import 'package:story_creator_kit/src/api/result/story_result.dart';
import 'package:story_creator_kit/src/core/session_files.dart';
import 'package:story_creator_kit/src/core/story_canvas.dart';
import 'package:story_creator_kit/src/model/drawing_stroke.dart';
import 'package:story_creator_kit/src/model/media_placement.dart';
import 'package:story_creator_kit/src/model/music_selection.dart';
import 'package:story_creator_kit/src/model/overlay_transform.dart';
import 'package:story_creator_kit/src/model/story_document.dart';
import 'package:story_creator_kit/src/model/story_media.dart';
import 'package:story_creator_kit/src/model/story_overlay.dart';
import 'package:story_creator_kit/src/model/trim_range.dart';
import 'package:story_creator_kit/src/native/story_native_api.g.dart';
import 'package:story_creator_kit/src/render/painters/story_paint_resources.dart';
import 'package:story_creator_kit/src/services/export/native_story_exporter.dart';
import 'package:story_creator_kit/src/services/export/story_exporter.dart';
import 'package:story_creator_kit/src/services/media/native_media_inspector.dart';

import 'support/media_fixtures.dart';

const _magenta = (255, 0, 255);
const _green = (0, 255, 0);
const _red = (255, 0, 0);
const _blue = (0, 0, 255);
const _white = (255, 255, 255);
const _cyan = (0, 255, 255);
// Mono filter of pure red: 0.2126 * 255.
const _monoRed = (54, 54, 54);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final inspector = NativeMediaInspector();
  final exporter = NativeStoryExporter(inspector: inspector);
  late Directory root;
  late Directory outDir;
  late SessionFiles session;
  final resources = StoryPaintResources(
    fonts: const [StoryFont.system],
    stickerImages: {},
    filters: StoryFilter.defaults,
  );

  setUp(() async {
    final tmp = await getTemporaryDirectory();
    root = Directory(
      '${tmp.path}/export_it_${DateTime.now().microsecondsSinceEpoch}',
    );
    outDir = Directory('${root.path}/out')..createSync(recursive: true);
    session = SessionFiles.at(Directory('${root.path}/session')..createSync());
  });

  tearDown(() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  });

  ExportContext exportContext() => ExportContext(
    session: session,
    outputDirectory: outDir.path,
    output: const OutputOptions(),
    resources: resources,
  );

  Future<StoryMedia> videoMedia(String asset) async {
    final path = await copyFixture(asset, root);
    final probe = await inspector.probe(path);
    return StoryMedia(
      path: path,
      type: StoryMediaType.video,
      width: probe.width,
      height: probe.height,
      source: StorySourceKind.gallery,
      duration: probe.duration,
      rotationDegrees: probe.rotationDegrees,
      hasAudio: probe.hasAudio,
    );
  }

  Future<StoryMedia> photoMedia() async {
    final path = await writeQuadrantPng(root);
    final probe = await inspector.probe(path);
    return StoryMedia(
      path: path,
      type: StoryMediaType.photo,
      width: probe.width,
      height: probe.height,
      source: StorySourceKind.gallery,
    );
  }

  /// A thick magenta pen stroke centred on (900, 1800).
  final marker = DrawingStroke(
    points: [for (var x = 820.0; x <= 980; x += 20) StrokePoint(x, 1800)],
    color: const ui.Color(0xFFFF00FF),
    size: 90,
  );

  const caption = TextOverlay(
    id: 'caption',
    transform: OverlayTransform(position: ui.Offset(540, 400)),
    text: 'Export test',
    style: TextOverlayStyle(
      fontId: 'system',
      color: ui.Color(0xFFFFFFFF),
      background: TextBackgroundStyle.solid,
    ),
  );

  StoryDocument document(StoryMedia media, {String? filterId}) => StoryDocument(
    media: media,
    placement: StoryCanvas.defaultPlacement(media),
    background: const StoryBackground(
      top: ui.Color(0xFF00FF00),
      bottom: ui.Color(0xFF00FF00),
    ),
    filterId: filterId,
  );

  MusicSelection music(
    String path, {
    required Duration duration,
    Duration start = Duration.zero,
  }) => MusicSelection(
    track: MusicTrack(
      id: 'tone',
      title: 'Tone',
      artist: 'Test',
      duration: const Duration(seconds: 10),
    ),
    start: start,
    duration: duration,
    localPath: path,
  );

  Future<ExportedStory> export(StoryDocument doc) =>
      exporter.start(doc, exportContext()).result;

  Future<Pixels> frameAt(String video, Duration time) async {
    final paths = await inspector.thumbnails(
      video,
      [time],
      outputDirectory: '${root.path}/frames',
      maxWidth: StoryCanvas.outputWidth,
    );
    return Pixels.read(paths.single);
  }

  void expectColor(
    Pixels p,
    int x,
    int y,
    (int, int, int) color, {
    int tolerance = 45,
  }) {
    final actual = p.at(x, y);
    expect(
      colorClose(actual, color, tolerance),
      isTrue,
      reason: 'pixel ($x, $y) is $actual, expected $color ±$tolerance',
    );
  }

  void expectDuration(Duration? actual, int expectedMs, {int tolerance = 100}) {
    expect(actual, isNotNull);
    expect(
      (actual!.inMilliseconds - expectedMs).abs(),
      lessThanOrEqualTo(tolerance),
      reason: 'duration ${actual.inMilliseconds} ms, expected $expectedMs ms',
    );
  }

  List<File> outputs() => outDir.listSync().whereType<File>().toList();

  testWidgets('photo → JPEG 1080×1920 with filter, drawing and text', (
    tester,
  ) async {
    final media = await photoMedia();
    final doc = document(
      media,
      filterId: 'mono',
    ).copyWith(strokes: [marker], overlays: [caption]);
    final story = await export(doc);
    expect(story.type, StoryMediaType.photo);
    expect(story.path, endsWith('.jpg'));
    final probe = await inspector.probe(story.path);
    expect((probe.width, probe.height), (1080, 1920));
    expect(probe.hasVideo, isFalse);
    final pixels = await Pixels.read(story.path);
    expect((pixels.width, pixels.height), (1080, 1920));
    // Background untouched by the filter, photo filtered, stroke on top.
    expectColor(pixels, 540, 120, _green, tolerance: 20);
    expectColor(pixels, 270, 600, _monoRed, tolerance: 20);
    expectColor(pixels, 810, 1320, _white, tolerance: 20);
    expectColor(pixels, 900, 1800, _magenta, tolerance: 30);
    expect(
      session.directory.listSync(),
      isEmpty,
      reason: 'intermediates removed',
    );
  });

  testWidgets('photo + music → MP4 of the segment length with audio', (
    tester,
  ) async {
    final media = await photoMedia();
    final wav = await writeToneWav(
      root,
      name: 'tone.wav',
      duration: const Duration(seconds: 10),
    );
    final doc = document(media).copyWith(
      strokes: [marker],
      music: music(
        wav,
        start: const Duration(seconds: 2),
        duration: const Duration(seconds: 5),
      ),
    );
    final story = await export(doc);
    expect(story.type, StoryMediaType.video);
    final probe = await inspector.probe(story.path);
    expect((probe.width, probe.height), (1080, 1920));
    expect(probe.hasVideo, isTrue);
    expect(probe.hasAudio, isTrue);
    expectDuration(probe.duration, 5000);
    expect(story.thumbnailPath, isNotNull);
    expect(File(story.thumbnailPath!).existsSync(), isTrue);
    final mid = await frameAt(story.path, const Duration(milliseconds: 2500));
    expectColor(mid, 270, 600, _red);
    expectColor(mid, 900, 1800, _magenta);
  });

  testWidgets('video trim → duration equals the trim length', (tester) async {
    final media = await videoMedia('landscape_h264_stereo.mp4');
    expect(media.hasAudio, isTrue);
    final doc = document(media).copyWith(
      trim: TrimRange(
        const Duration(milliseconds: 1000),
        const Duration(milliseconds: 3000),
      ),
    );
    final story = await export(doc);
    final probe = await inspector.probe(story.path);
    expect((probe.width, probe.height), (1080, 1920));
    expect(probe.hasAudio, isTrue);
    expect(probe.videoCodec, anyOf('avc1', 'video/avc'));
    expectDuration(probe.duration, 2000);
    expectDuration(story.duration, 2000);
    // Second 1 of the source has a cyan centre square.
    final first = await frameAt(story.path, Duration.zero);
    expectColor(first, 540, 960, _cyan);
    expectColor(first, 540, 120, _green, tolerance: 30);
  });

  testWidgets('video muted + music → audio from the music only', (
    tester,
  ) async {
    final media = await videoMedia('landscape_h264_stereo.mp4');
    final wav = await writeToneWav(
      root,
      name: 'music.wav',
      duration: const Duration(seconds: 8),
    );
    final doc = document(media).copyWith(
      trim: TrimRange(
        const Duration(milliseconds: 1000),
        const Duration(milliseconds: 3000),
      ),
      originalVolume: 0,
      music: music(wav, duration: const Duration(seconds: 2)),
    );
    final story = await export(doc);
    final probe = await inspector.probe(story.path);
    expect(probe.hasAudio, isTrue);
    expectDuration(probe.duration, 2000);
    final peaks = await inspector.waveform(story.path, buckets: 20);
    final loud = peaks.sublist(2, 18);
    expect(
      loud.reduce((a, b) => a + b) / loud.length,
      greaterThan(0.3),
      reason: 'music audible: $peaks',
    );
  });

  testWidgets('video muted, no music → no audio track', (tester) async {
    final media = await videoMedia('landscape_h264_stereo.mp4');
    final story = await export(document(media).copyWith(originalVolume: 0));
    final probe = await inspector.probe(story.path);
    expect(probe.hasVideo, isTrue);
    expect(probe.hasAudio, isFalse);
    expectDuration(probe.duration, 4000);
  });

  testWidgets('silent source, no music → no audio track', (tester) async {
    final media = await videoMedia('landscape_h264_silent.mp4');
    expect(media.hasAudio, isFalse);
    final story = await export(document(media));
    final probe = await inspector.probe(story.path);
    expect(probe.hasVideo, isTrue);
    expect(probe.hasAudio, isFalse);
    expectDuration(probe.duration, 4000);
  });

  testWidgets('video with filter + overlay → frames at start, middle, end', (
    tester,
  ) async {
    final media = await videoMedia('landscape_h264_stereo.mp4');
    final doc = document(
      media,
      filterId: 'mono',
    ).copyWith(strokes: [marker], overlays: [caption]);
    final story = await export(doc);
    final probe = await inspector.probe(story.path);
    expectDuration(probe.duration, 4000);
    // The video occupies y 656–1264 (landscape contained in 9:16).
    for (final t in const [0, 2000, 3900]) {
      final p = await frameAt(story.path, Duration(milliseconds: t));
      expectColor(p, 270, 800, _monoRed);
      expectColor(p, 810, 1120, _white);
      expectColor(p, 540, 120, _green, tolerance: 30);
      expectColor(p, 900, 1800, _magenta);
    }
  });

  testWidgets('source rotated 90° → upright output', (tester) async {
    final media = await videoMedia('portrait_rotated90_h264.mp4');
    expect(media.rotationDegrees, 90);
    expect((media.width, media.height), (360, 640));
    final story = await export(document(media));
    final probe = await inspector.probe(story.path);
    expect((probe.width, probe.height), (1080, 1920));
    final p = await frameAt(story.path, const Duration(milliseconds: 500));
    expectColor(p, 270, 480, _red);
    expectColor(p, 810, 480, _green);
    expectColor(p, 270, 1440, _blue);
    expectColor(p, 810, 1440, _white);
  });

  testWidgets('HEVC source with mono audio + stereo music', (tester) async {
    final media = await videoMedia('portrait_hevc_mono.mp4');
    final wav = await writeToneWav(
      root,
      name: 'stereo.wav',
      duration: const Duration(seconds: 6),
    );
    final story = await export(
      document(media).copyWith(
        music: music(
          wav,
          duration: const Duration(seconds: 4),
          start: Duration.zero,
        ),
      ),
    );
    final probe = await inspector.probe(story.path);
    expect(probe.videoCodec, anyOf('avc1', 'video/avc'));
    expect(probe.hasAudio, isTrue);
    expectDuration(probe.duration, 4000);
    final p = await frameAt(story.path, const Duration(milliseconds: 500));
    expectColor(p, 270, 480, _red);
    expectColor(p, 810, 1440, _white);
  });

  testWidgets('stereo 44.1 kHz video + mono 48 kHz music mix', (tester) async {
    final media = await videoMedia('landscape_h264_stereo.mp4');
    final wav = await writeToneWav(
      root,
      name: 'mono48.wav',
      duration: const Duration(seconds: 6),
      sampleRate: 48000,
      channels: 1,
    );
    final story = await export(
      document(media).copyWith(
        originalVolume: 0.5,
        music: music(wav, duration: const Duration(seconds: 4)),
      ),
    );
    final probe = await inspector.probe(story.path);
    expect(probe.hasAudio, isTrue);
    expectDuration(probe.duration, 4000);
  });

  testWidgets('cancel during a still-video export → cancelled, no output', (
    tester,
  ) async {
    final media = await photoMedia();
    final wav = await writeToneWav(
      root,
      name: 'long.wav',
      duration: const Duration(seconds: 40),
    );
    final job = exporter.start(
      document(media)
          .copyWith(music: music(wav, duration: const Duration(seconds: 30))),
      exportContext(),
    );
    final progress = <double>[];
    final sub = job.progress.listen(progress.add);
    await job.progress
        .firstWhere((p) => p > 0.06)
        .timeout(const Duration(seconds: 60));
    await job.cancel();
    await expectLater(job.result, throwsA(isA<ExportCancelledException>()));
    await sub.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(outDir.listSync().whereType<File>(), isEmpty);
    expect(session.directory.listSync(), isEmpty);
    expect(progress, isNotEmpty);
  });

  testWidgets('cancel during a video export → cancelled, no output', (
    tester,
  ) async {
    final media = await videoMedia('landscape_h264_stereo.mp4');
    final job = exporter.start(
      document(media, filterId: 'vivid').copyWith(strokes: [marker]),
      exportContext(),
    );
    await job.progress
        .firstWhere((p) => p >= 0.05)
        .timeout(const Duration(seconds: 60));
    await job.cancel();
    await expectLater(job.result, throwsA(isA<ExportCancelledException>()));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(outDir.listSync().whereType<File>(), isEmpty);
  });

  testWidgets('invalid input path → StoryException with a native code', (
    tester,
  ) async {
    final missing = '${root.path}/missing.mp4';
    final media = StoryMedia(
      path: missing,
      type: StoryMediaType.video,
      width: 640,
      height: 360,
      source: StorySourceKind.gallery,
      duration: const Duration(seconds: 2),
      hasAudio: true,
    );
    final job = exporter.start(document(media), exportContext());
    final error = await job.result.then<Object?>(
      (_) => null,
      onError: (Object e) => e,
    );
    expect(error, isA<StoryException>());
    expect((error! as StoryException).code, StoryErrorCode.exportFailed);
    expect(
      ((error as StoryException).cause! as PlatformException).code,
      anyOf('invalid_input', 'io'),
    );
    expect(outputs(), isEmpty);

    final probeError = await inspector
        .probe(missing)
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect(probeError, isA<StoryException>());
    expect(
      (probeError! as StoryException).code,
      StoryErrorCode.mediaUnavailable,
    );

    final raw = await StoryNativeApi()
        .probe(missing)
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect((raw! as PlatformException).code, 'invalid_input');

    final garbage = File('${root.path}/garbage.mp4')
      ..writeAsBytesSync(List.filled(4096, 7));
    final unsupported = await inspector
        .probe(garbage.path)
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect(
      (unsupported! as StoryException).code,
      StoryErrorCode.mediaUnsupported,
    );
  });

  testWidgets('waveform: bucket count and loud/quiet halves', (tester) async {
    final wav = await writeToneWav(root, name: 'wave.wav');
    final peaks = await inspector.waveform(wav, buckets: 40);
    expect(peaks, hasLength(40));
    expect(peaks.every((p) => p >= 0 && p <= 1), isTrue);
    final loud = peaks.sublist(1, 18);
    final quiet = peaks.sublist(22, 39);
    double mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;
    expect(mean(loud), greaterThan(0.6), reason: '$peaks');
    expect(mean(quiet), lessThan(0.15), reason: '$peaks');
    final silent = await inspector.waveform(
      await copyFixture('landscape_h264_silent.mp4', root),
      buckets: 10,
    );
    expect(silent, List.filled(10, 0.0));
  });

  testWidgets('thumbnails: one file per time, at most maxWidth wide', (
    tester,
  ) async {
    final video = await copyFixture('landscape_h264_stereo.mp4', root);
    const times = [0, 500, 1000, 2500, 3990];
    final paths = await inspector.thumbnails(
      video,
      [for (final t in times) Duration(milliseconds: t)],
      outputDirectory: '${root.path}/thumbs',
      maxWidth: 160,
    );
    expect(paths, hasLength(times.length));
    expect(paths.toSet(), hasLength(times.length));
    for (final path in paths) {
      final p = await Pixels.read(path);
      expect(p.width, lessThanOrEqualTo(160));
      expect(p.width, greaterThan(100));
    }
    final photo = await writeQuadrantPng(root, width: 400, height: 300);
    final photoThumbs = await inspector.thumbnails(
      photo,
      const [Duration.zero],
      outputDirectory: '${root.path}/thumbs',
      maxWidth: 100,
    );
    expect(photoThumbs, hasLength(1));
    expect(
      (await Pixels.read(photoThumbs.single)).width,
      lessThanOrEqualTo(100),
    );
  });

  testWidgets('probe: photo, videos and audio', (tester) async {
    final png = await writeQuadrantPng(root, width: 300, height: 200);
    final photo = await inspector.probe(png);
    expect(
      (photo.width, photo.height, photo.hasVideo, photo.duration),
      (300, 200, false, null),
    );
    final rotated = await inspector.probe(
      await copyFixture('portrait_rotated90_h264.mp4', root),
    );
    expect(
      (rotated.width, rotated.height, rotated.rotationDegrees),
      (360, 640, 90),
    );
    expect(rotated.hasAudio, isTrue);
    expectDuration(rotated.duration, 4000);
    final hevc = await inspector.probe(
      await copyFixture('portrait_hevc_mono.mp4', root),
    );
    expect(hevc.videoCodec, anyOf('hvc1', 'hev1', 'video/hevc'));
    final wav = await inspector.probe(
      await writeToneWav(
        root,
        name: 'p.wav',
        duration: const Duration(seconds: 3),
      ),
    );
    expect(wav.hasAudio, isTrue);
    expect(wav.hasVideo, isFalse);
    expectDuration(wav.duration, 3000);
  });
}
