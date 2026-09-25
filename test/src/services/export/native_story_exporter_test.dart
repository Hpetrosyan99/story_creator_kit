import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/src/api/assets/story_filter.dart';
import 'package:story_creator_kit/src/api/assets/story_font.dart';
import 'package:story_creator_kit/src/api/config/output_options.dart';
import 'package:story_creator_kit/src/api/errors/story_exception.dart';
import 'package:story_creator_kit/src/api/music/music_models.dart';
import 'package:story_creator_kit/src/api/result/story_result.dart';
import 'package:story_creator_kit/src/core/session_files.dart';
import 'package:story_creator_kit/src/model/media_placement.dart';
import 'package:story_creator_kit/src/model/music_selection.dart';
import 'package:story_creator_kit/src/model/story_document.dart';
import 'package:story_creator_kit/src/model/story_media.dart';
import 'package:story_creator_kit/src/model/trim_range.dart';
import 'package:story_creator_kit/src/native/story_native_api.g.dart';
import 'package:story_creator_kit/src/render/painters/story_paint_resources.dart';
import 'package:story_creator_kit/src/services/export/native_story_exporter.dart';
import 'package:story_creator_kit/src/services/export/story_exporter.dart';
import 'package:story_creator_kit/src/services/media/native_media_inspector.dart';

import 'fake_native_api.dart';

final _resources = StoryPaintResources(
  fonts: const [StoryFont.system],
  stickerImages: {},
  filters: StoryFilter.defaults,
);

const _landscape = StoryMedia(
  path: '/videos/clip.mp4',
  type: StoryMediaType.video,
  width: 1920,
  height: 1080,
  source: StorySourceKind.gallery,
  duration: Duration(seconds: 10),
  hasAudio: true,
);

MusicSelection _music({String? localPath = '/music/a.m4a'}) => MusicSelection(
  track: const MusicTrack(
    id: 'm1',
    title: 'Song',
    artist: 'Artist',
    duration: Duration(minutes: 2),
  ),
  start: const Duration(milliseconds: 12500),
  duration: const Duration(seconds: 8),
  localPath: localPath,
  volume: 0.4,
);

Future<String> _writePng(Directory dir, int w, int h) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFF0000),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${dir.path}/photo_${w}x$h.png');
  await file.writeAsBytes(data!.buffer.asUint8List());
  return file.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildVideoRequest', () {
    VideoExportRequest build(StoryDocument doc) =>
        NativeStoryExporter.buildVideoRequest(
          jobId: 'j',
          document: doc,
          resources: _resources,
          output: const OutputOptions(videoBitrate: 5000000, frameRate: 24),
          outputPath: '/out/s.mp4',
          overlayPath: '/tmp/o.png',
        );

    test('videoRect is the media rect in output pixels', () {
      // 16:9 contained in 1080×1920 is 1080×607.5, then scaled ×2 around
      // the centre and moved by (40, -100).
      final r = build(
        const StoryDocument(
          media: _landscape,
          placement: MediaPlacement(scale: 2, offset: ui.Offset(40, -100)),
        ),
      );
      expect(r.videoRect.width, closeTo(2160, 0.01));
      expect(r.videoRect.height, closeTo(1215, 0.01));
      expect(r.videoRect.left, closeTo(540 + 40 - 1080, 0.01));
      expect(r.videoRect.top, closeTo(960 - 100 - 607.5, 0.01));
      expect(r.overlayPngPath, '/tmp/o.png');
      expect(r.sourcePath, '/videos/clip.mp4');
    });

    test('trim, output settings and mirror', () {
      final r = build(
        StoryDocument(
          media: _landscape.copyWith(mirrored: true),
          trim: TrimRange(
            const Duration(milliseconds: 1500),
            const Duration(milliseconds: 6250),
          ),
        ),
      );
      expect((r.trimStartMs, r.trimEndMs), (1500, 6250));
      expect(r.mirror, isTrue);
      expect(r.output.path, '/out/s.mp4');
      expect((r.output.width, r.output.height), (1080, 1920));
      expect((r.output.frameRate, r.output.videoBitrate), (24, 5000000));
    });

    test('no trim exports the whole video', () {
      final r = build(const StoryDocument(media: _landscape));
      expect((r.trimStartMs, r.trimEndMs), (0, 10000));
    });

    test('colour matrix only for a non-identity filter', () {
      expect(build(const StoryDocument(media: _landscape)).colorMatrix, isNull);
      expect(
        build(const StoryDocument(media: _landscape, filterId: 'original'))
            .colorMatrix,
        isNull,
      );
      final mono = build(
        const StoryDocument(media: _landscape, filterId: 'mono'),
      ).colorMatrix;
      expect(mono, hasLength(20));
      expect(
        mono,
        StoryFilter.defaults.firstWhere((f) => f.id == 'mono').matrix,
      );
    });

    test('original volume is clamped and 0 without an audio track', () {
      expect(
        build(const StoryDocument(media: _landscape, originalVolume: 0.3))
            .originalVolume,
        0.3,
      );
      expect(
        build(StoryDocument(media: _landscape.copyWith(hasAudio: false)))
            .originalVolume,
        0,
      );
    });

    test('music segment start and volume', () {
      final r = build(StoryDocument(media: _landscape, music: _music()));
      expect(r.music!.path, '/music/a.m4a');
      expect(r.music!.startMs, 12500);
      expect(r.music!.volume, 0.4);
    });

    test('music without a local file is musicUnavailable', () {
      expect(
        () => build(
          StoryDocument(media: _landscape, music: _music(localPath: null)),
        ),
        throwsA(
          isA<StoryException>().having(
            (e) => e.code,
            'code',
            StoryErrorCode.musicUnavailable,
          ),
        ),
      );
    });

    test('a video without duration or trim cannot be exported', () {
      const media = StoryMedia(
        path: '/v.mp4',
        type: StoryMediaType.video,
        width: 10,
        height: 10,
        source: StorySourceKind.camera,
      );
      expect(
        () => build(const StoryDocument(media: media)),
        throwsA(isA<StoryException>()),
      );
    });
  });

  group('jobs', () {
    late Directory dir;
    late FakeNativeApi api;
    late NativeStoryExporter exporter;
    late String photo;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('exporter_test');
      api = FakeNativeApi();
      exporter = NativeStoryExporter(
        inspector: NativeMediaInspector(api: api),
        api: api,
      );
      photo = await _writePng(dir, 300, 400);
    });

    tearDown(() async {
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    });

    ExportContext context() => ExportContext(
      session: SessionFiles.at(Directory('${dir.path}/session')..createSync()),
      outputDirectory: '${dir.path}/out',
      output: const OutputOptions(jpegQuality: 77),
      resources: _resources,
    );

    StoryMedia photoMedia() => StoryMedia(
      path: photo,
      type: StoryMediaType.photo,
      width: 300,
      height: 400,
      source: StorySourceKind.gallery,
    );

    test('photo is composed in Dart and encoded natively', () async {
      final ctx = context();
      final story = await exporter
          .start(StoryDocument(media: photoMedia()), ctx)
          .result;
      final request = api.requests.single as JpegEncodeRequest;
      expect((request.width, request.height), (1080, 1920));
      expect(request.rgba.length, 1080 * 1920 * 4);
      expect(request.quality, 77);
      expect(request.outputPath, startsWith('${dir.path}/out/story_'));
      expect(story.type, StoryMediaType.photo);
      expect(story.path, request.outputPath);
      expect(story.mimeType, 'image/jpeg');
      expect(ctx.session.directory.listSync(), isEmpty);
    });

    test('photo with music becomes a still video of the segment', () async {
      final ctx = context();
      final story = await exporter
          .start(StoryDocument(media: photoMedia(), music: _music()), ctx)
          .result;
      final request = api.requests.single as StillVideoExportRequest;
      expect(request.durationMs, 8000);
      expect(request.music!.startMs, 12500);
      expect(request.output.path, endsWith('.mp4'));
      expect(story.type, StoryMediaType.video);
      expect(story.duration, const Duration(seconds: 5));
      expect(story.thumbnailPath, endsWith('_poster.jpg'));
      expect(File(story.thumbnailPath!).existsSync(), isTrue);
      // The frame PNG was an intermediate.
      expect(ctx.session.directory.listSync(), isEmpty);
    });

    test('video sends the overlay PNG and probes the result', () async {
      String? overlay;
      var overlayExisted = false;
      api.probeResult = NativeMediaProbe(
        width: 1080,
        height: 1920,
        fileSizeBytes: 99,
        rotationDegrees: 0,
        hasVideo: true,
        hasAudio: false,
        durationMs: 2000,
      );
      final story = await exporter
          .start(
            StoryDocument(
              media: _landscape.copyWith(path: '${dir.path}/in.mp4'),
              trim: TrimRange(Duration.zero, const Duration(seconds: 2)),
            ),
            context(),
          )
          .result;
      final request = api.requests.single as VideoExportRequest;
      overlay = request.overlayPngPath;
      overlayExisted = overlay != null;
      expect(overlayExisted, isTrue);
      expect(File(overlay!).existsSync(), isFalse, reason: 'cleaned up');
      expect(story.fileSizeBytes, 99);
      expect(story.duration, const Duration(seconds: 2));
    });

    test('progress from native events is scaled into the job', () async {
      api.autoComplete = false;
      final job = exporter.start(
        StoryDocument(media: _landscape.copyWith(path: '${dir.path}/in.mp4')),
        context(),
      );
      final values = <double>[];
      job.progress.listen(values.add);
      while (api.requests.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final id = (api.requests.single as VideoExportRequest).jobId;
      ExportProgressHub.instance().onExportProgress(id, 0.5);
      api.release();
      await job.result;
      expect(values.first, lessThanOrEqualTo(0.05));
      expect(values, contains(closeTo(0.5, 0.001)));
      expect(values.last, 1);
      for (var i = 1; i < values.length; i++) {
        expect(values[i], greaterThanOrEqualTo(values[i - 1]));
      }
    });

    test('cancel stops the native job and removes the output', () async {
      api.autoComplete = false;
      final ctx = context();
      final job = exporter.start(
        StoryDocument(media: _landscape.copyWith(path: '${dir.path}/in.mp4')),
        ctx,
      );
      while (api.requests.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await job.cancel();
      await expectLater(job.result, throwsA(isA<ExportCancelledException>()));
      expect(api.cancelled, hasLength(1));
      final out = Directory('${dir.path}/out');
      expect(out.listSync(), isEmpty);
      expect(ctx.session.directory.listSync(), isEmpty);
    });

    test('native no_space maps to insufficientStorage', () async {
      api.error = PlatformException(code: 'no_space', message: 'full');
      final job = exporter.start(
        StoryDocument(media: _landscape.copyWith(path: '${dir.path}/in.mp4')),
        context(),
      );
      await expectLater(
        job.result,
        throwsA(
          isA<StoryException>().having(
            (e) => e.code,
            'code',
            StoryErrorCode.insufficientStorage,
          ),
        ),
      );
    });

    test('other native failures map to exportFailed', () async {
      api.error = PlatformException(code: 'encoder', message: 'boom');
      final job = exporter.start(StoryDocument(media: photoMedia()), context());
      await expectLater(
        job.result,
        throwsA(
          isA<StoryException>()
              .having((e) => e.code, 'code', StoryErrorCode.exportFailed)
              .having((e) => e.cause, 'cause', isA<PlatformException>()),
        ),
      );
      expect(Directory('${dir.path}/out').listSync(), isEmpty);
    });
  });
}
