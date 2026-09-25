import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/services.dart';
import 'package:story_creator_kit/src/flow/story_flow_controller.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

import '../../fakes/fake_services.dart';

const _photo = StoryMedia(
  path: '/in/photo.jpg',
  type: StoryMediaType.photo,
  width: 1080,
  height: 1920,
  source: StorySourceKind.camera,
);

const _landscapeVideo = StoryMedia(
  path: '/in/video.mp4',
  type: StoryMediaType.video,
  width: 1920,
  height: 1080,
  source: StorySourceKind.gallery,
  duration: Duration(seconds: 30),
  hasAudio: true,
);

const _track = MusicTrack(
  id: 'loop-1',
  title: 'Sunrise',
  artist: 'Example',
  duration: Duration(minutes: 1),
  extra: {'licence': 'cc0'},
);

final _createdAt = DateTime.utc(2026, 9, 25, 12);

void main() {
  late Directory tmp;
  late List<StoryEvent> events;
  late FakeGallerySaver saver;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('flow_test_');
    events = [];
    saver = FakeGallerySaver();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  StoryFlowController controller({
    StoryCreatorConfig config = const StoryCreatorConfig(),
  }) {
    final c = StoryFlowController(
      config: config,
      services: fakeServices(tempDir: tmp, saver: saver),
      session: SessionFiles.at(tmp),
      report: events.add,
      clock: () => _createdAt,
    );
    addTearDown(c.dispose);
    return c;
  }

  ExportedStory exported({
    StoryMediaType type = StoryMediaType.photo,
    bool withThumbnail = false,
  }) {
    final ext = type == StoryMediaType.photo ? 'jpg' : 'mp4';
    final file = File('${tmp.path}/out_${events.length}.$ext')
      ..writeAsBytesSync(const [1, 2, 3, 4]);
    String? thumb;
    if (withThumbnail) {
      thumb = (File(
        '${tmp.path}/out_thumb.jpg',
      )..writeAsBytesSync(const [5])).path;
    }
    return ExportedStory(
      path: file.path,
      type: type,
      width: 1080,
      height: 1920,
      fileSizeBytes: 4,
      duration: type == StoryMediaType.video
          ? const Duration(seconds: 12)
          : null,
      thumbnailPath: thumb,
    );
  }

  Iterable<StoryEventType> types() => events.map((e) => e.type);

  group('mediaReady', () {
    test('opens the editor with a default document', () {
      final c = controller();
      var notified = 0;
      c.addListener(() => notified++);

      expect(c.step, StoryFlowStep.camera);
      expect(c.initialDocument, isNull);

      c.mediaReady(_photo);

      expect(c.step, StoryFlowStep.editor);
      expect(notified, 1);
      final doc = c.initialDocument!;
      expect(doc.media, _photo);
      expect(doc.placement.scale, closeTo(1, 1e-9));
      expect(doc.trim, isNull);
      expect(doc.filterId, isNull, reason: 'first default filter is identity');
      expect(doc.overlays, isEmpty);
    });

    test('reports captured for camera media and mediaPicked for gallery', () {
      controller()
        ..mediaReady(_photo)
        ..mediaReady(_landscapeVideo);

      expect(events[0].type, StoryEventType.captured);
      expect(events[0].properties, {'type': 'photo'});
      expect(events[1].type, StoryEventType.mediaPicked);
      expect(events[1].properties, {'type': 'video'});
    });

    test('bumps editorGeneration for every new media', () {
      final c = controller()..mediaReady(_photo);
      final first = c.editorGeneration;

      c.mediaReady(_photo);

      expect(c.editorGeneration, first + 1);
    });

    test('trims videos longer than the maximum to [0, max]', () {
      final c = controller(
        config: const StoryCreatorConfig(
          constraints: MediaConstraints(
            maxVideoDuration: Duration(seconds: 15),
          ),
        ),
      )..mediaReady(_landscapeVideo);

      final trim = c.initialDocument!.trim!;
      expect(trim.start, Duration.zero);
      expect(trim.end, const Duration(seconds: 15));
    });

    test('keeps videos that fit (including exactly max) untrimmed', () {
      final c = controller(
        config: const StoryCreatorConfig(
          constraints: MediaConstraints(
            maxVideoDuration: Duration(seconds: 30),
          ),
        ),
      )..mediaReady(_landscapeVideo);

      expect(c.initialDocument!.trim, isNull);
    });

    test('contains landscape media instead of filling', () {
      final c = controller()..mediaReady(_landscapeVideo);

      expect(c.initialDocument!.placement.scale, 1);
    });

    test('selects a non-identity first filter by default', () {
      const sepiaFirst = [
        StoryFilter(
          id: 'house',
          label: 'House',
          matrix: [
            0.9, 0, 0, 0, 5, //
            0, 0.9, 0, 0, 5,
            0, 0, 0.9, 0, 5,
            0, 0, 0, 1, 0,
          ],
        ),
        StoryFilter.original,
      ];
      final c = controller(
        config: const StoryCreatorConfig(
          editor: EditorOptions(filters: sepiaFirst),
        ),
      )..mediaReady(_photo);

      expect(c.initialDocument!.filterId, 'house');
    });
  });

  test('leaveEditor goes back to the camera and drops the document', () {
    final c = controller()
      ..mediaReady(_photo)
      ..leaveEditor();

    expect(c.step, StoryFlowStep.camera);
    expect(c.initialDocument, isNull);
  });

  group('export', () {
    test('requestExport moves to exporting and reports the output type', () {
      final c = controller()..mediaReady(_photo);
      final doc = c.initialDocument!.copyWith(filterId: 'mono');

      c.requestExport(doc);

      expect(c.step, StoryFlowStep.exporting);
      expect(c.exportDocument, doc);
      expect(events.last.type, StoryEventType.exportStarted);
      expect(events.last.properties, {'type': 'photo'});
    });

    test('a photo with music exports as video', () {
      final c = controller()..mediaReady(_photo);

      c.requestExport(
        c.initialDocument!.copyWith(
          music: const MusicSelection(
            track: _track,
            start: Duration.zero,
            duration: Duration(seconds: 15),
          ),
        ),
      );

      expect(events.last.properties, {'type': 'video'});
    });

    test('exportAborted returns to the editor', () {
      final c = controller()
        ..mediaReady(_photo)
        ..requestExport(const StoryDocument(media: _photo))
        ..exportAborted();

      expect(c.step, StoryFlowStep.editor);
      expect(c.initialDocument, isNotNull, reason: 'edits survive');
      expect(events.last.type, StoryEventType.exportCancelled);
    });

    test('exportFinished with preview shows the preview', () async {
      final c = controller()
        ..mediaReady(_photo)
        ..requestExport(const StoryDocument(media: _photo));
      final story = exported(type: StoryMediaType.video);

      final outcome = await c.exportFinished(story);

      expect(outcome, isNull);
      expect(c.step, StoryFlowStep.preview);
      expect(c.exported, same(story));
      final event = events.last;
      expect(event.type, StoryEventType.exportCompleted);
      expect(event.properties, {
        'type': 'video',
        'bytes': 4,
        'durationMs': 12000,
      });
      expect(c.finished, isFalse);
    });

    test('exportFinished without preview completes immediately', () async {
      final c = controller(
        config: const StoryCreatorConfig(
          output: OutputOptions(showPreview: false),
        ),
      )..mediaReady(_photo);
      c.requestExport(c.initialDocument!);
      final story = exported();

      final outcome = await c.exportFinished(story);

      expect(outcome, isA<StoryCompleted>());
      expect(outcome!.resultOrNull!.path, story.path);
      expect(outcome.resultOrNull!.savedToGallery, isFalse);
      expect(c.finished, isTrue);
      expect(
        types(),
        containsAllInOrder([
          StoryEventType.exportCompleted,
          StoryEventType.completed,
        ]),
      );
      expect(events.last.properties.containsKey('durationMs'), isFalse);
      expect(File(story.path).existsSync(), isTrue);
    });

    test('backToEditor deletes the exported file and thumbnail', () async {
      final c = controller()
        ..mediaReady(_photo)
        ..requestExport(const StoryDocument(media: _photo));
      final story = exported(type: StoryMediaType.video, withThumbnail: true);
      await c.exportFinished(story);

      await c.backToEditor();

      expect(c.step, StoryFlowStep.editor);
      expect(c.exported, isNull);
      expect(File(story.path).existsSync(), isFalse);
      expect(File(story.thumbnailPath!).existsSync(), isFalse);
    });

    test('backToEditor tolerates an already deleted file', () async {
      final c = controller()
        ..mediaReady(_photo)
        ..requestExport(const StoryDocument(media: _photo));
      final story = exported();
      await c.exportFinished(story);
      File(story.path).deleteSync();

      await c.backToEditor();

      expect(c.step, StoryFlowStep.editor);
      expect(types(), isNot(contains(StoryEventType.error)));
    });
  });

  group('complete', () {
    Future<StoryFlowController> atPreview({
      OutputOptions output = const OutputOptions(),
      StoryDocument document = const StoryDocument(media: _photo),
      ExportedStory? story,
    }) async {
      final c = controller(config: StoryCreatorConfig(output: output))
        ..mediaReady(document.media)
        ..requestExport(document);
      await c.exportFinished(story ?? exported());
      return c;
    }

    test('fails when called before an export', () async {
      final outcome = await controller().complete(savedToGallery: false);

      expect(outcome, isA<StoryFailed>());
      expect((outcome as StoryFailed).error.code, StoryErrorCode.unknown);
    });

    test('returns the exported file and keeps it on disk', () async {
      final story = exported();
      final c = await atPreview(story: story);

      final outcome = await c.complete(savedToGallery: false);

      final result = outcome.resultOrNull!;
      expect(result.path, story.path);
      expect(result.mimeType, 'image/jpeg');
      expect(result.type, StoryMediaType.photo);
      expect(result.width, 1080);
      expect(result.height, 1920);
      expect(result.fileSizeBytes, 4);
      expect(result.savedToGallery, isFalse);
      expect(File(story.path).existsSync(), isTrue);
      expect(c.finished, isTrue);
      expect(c.exported, isNull);
      expect(events.last.type, StoryEventType.completed);
      expect(saver.saved, isEmpty, reason: 'mode is button by default');
    });

    test(
      'passes savedToGallery through when the preview already saved',
      () async {
        final c = await atPreview(
          output: const OutputOptions(saveToGallery: SaveToGalleryMode.always),
        );

        final outcome = await c.complete(savedToGallery: true);

        expect(outcome.resultOrNull!.savedToGallery, isTrue);
        expect(saver.saved, isEmpty, reason: 'not saved twice');
      },
    );

    test('saveToGallery always saves before completing', () async {
      final story = exported();
      final c = await atPreview(
        output: const OutputOptions(
          saveToGallery: SaveToGalleryMode.always,
          galleryAlbum: 'Stories',
        ),
        story: story,
      );

      final outcome = await c.complete(savedToGallery: false);

      expect(saver.saved, [story.path]);
      expect(outcome.resultOrNull!.savedToGallery, isTrue);
      expect(
        types(),
        containsAllInOrder([
          StoryEventType.savedToGallery,
          StoryEventType.completed,
        ]),
      );
    });

    test(
      'a failed always-save still completes and reports the error',
      () async {
        saver.error = const StoryException(StoryErrorCode.saveToGalleryFailed);
        final c = await atPreview(
          output: const OutputOptions(saveToGallery: SaveToGalleryMode.always),
        );

        final outcome = await c.complete(savedToGallery: false);

        expect(outcome, isA<StoryCompleted>());
        expect(outcome.resultOrNull!.savedToGallery, isFalse);
        final error = events.firstWhere((e) => e.type == StoryEventType.error);
        expect(error.error!.code, StoryErrorCode.saveToGalleryFailed);
        expect(error.properties, {'code': 'saveToGalleryFailed'});
        expect(events.last.type, StoryEventType.completed);
      },
    );

    test(
      'a non-StoryException from the gallery saver still completes',
      () async {
        final c = StoryFlowController(
          config: const StoryCreatorConfig(
            output: OutputOptions(saveToGallery: SaveToGalleryMode.always),
          ),
          services: fakeServices(tempDir: tmp)
              .copyWith(gallerySaver: _ThrowingSaver()),
          session: SessionFiles.at(tmp),
          report: events.add,
        )..mediaReady(_photo);
        addTearDown(c.dispose);
        c.requestExport(c.initialDocument!);
        await c.exportFinished(exported());

        final outcome = await c.complete(savedToGallery: false);

        expect(outcome, isA<StoryCompleted>());
      },
    );
  });

  group('cancel', () {
    test('returns StoryCancelled with the reason and reports it', () async {
      final c = controller();

      final outcome = await c.cancel(StoryCancelReason.userCancelled);

      expect(outcome, isA<StoryCancelled>());
      expect(
        (outcome as StoryCancelled).reason,
        StoryCancelReason.userCancelled,
      );
      expect(outcome.resultOrNull, isNull);
      expect(c.finished, isTrue);
      expect(events.last.type, StoryEventType.cancelled);
      expect(events.last.properties, {'reason': 'userCancelled'});
    });

    test('deletes an exported file that was not confirmed', () async {
      final c = controller()
        ..mediaReady(_photo)
        ..requestExport(const StoryDocument(media: _photo));
      final story = exported();
      await c.exportFinished(story);

      await c.cancel(StoryCancelReason.dismissed);

      expect(File(story.path).existsSync(), isFalse);
    });
  });

  group('buildResult metadata', () {
    test('maps overlays, drawing, music, trim and volume for a video', () {
      final c = controller();
      final doc = StoryDocument(
        media: _landscapeVideo,
        filterId: 'warm',
        trim: TrimRange(
          const Duration(seconds: 2),
          const Duration(seconds: 14),
        ),
        originalVolume: 0.25,
        music: const MusicSelection(
          track: _track,
          start: Duration(seconds: 8),
          duration: Duration(seconds: 12),
          volume: 0.7,
        ),
        overlays: const [
          TextOverlay(
            id: 'a',
            transform: OverlayTransform(position: Offset(1, 1)),
            text: 'Hello',
            style: TextOverlayStyle(fontId: 'inter', color: Color(0xFFE4572E)),
          ),
          StickerOverlay(
            id: 'b',
            transform: OverlayTransform(position: Offset(2, 2)),
            stickerId: 'star',
          ),
          EmojiOverlay(
            id: 'c',
            transform: OverlayTransform(position: Offset(3, 3)),
            emoji: '🔥',
          ),
          TextOverlay(
            id: 'd',
            transform: OverlayTransform(position: Offset(4, 4)),
            text: 'World',
            style: TextOverlayStyle(fontId: 'mono', color: Color(0xFFFFFFFF)),
          ),
          StickerOverlay(
            id: 'e',
            transform: OverlayTransform(position: Offset(5, 5)),
            stickerId: 'heart',
          ),
        ],
        strokes: const [
          DrawingStroke(
            points: [StrokePoint(0, 0)],
            color: Color(0xFF000000),
            size: 8,
          ),
        ],
      );

      final result = c.buildResult(
        exported(type: StoryMediaType.video, withThumbnail: true),
        doc,
        savedToGallery: true,
      );
      final m = result.metadata;

      expect(result.type, StoryMediaType.video);
      expect(result.mimeType, 'video/mp4');
      expect(result.duration, const Duration(seconds: 12));
      expect(result.thumbnailPath, endsWith('out_thumb.jpg'));
      expect(result.savedToGallery, isTrue);
      expect(m.source, StorySourceKind.gallery);
      expect(m.sourceType, StoryMediaType.video);
      expect(m.createdAt, _createdAt);
      expect(m.trimStart, const Duration(seconds: 2));
      expect(m.trimEnd, const Duration(seconds: 14));
      expect(m.originalAudioVolume, 0.25);
      expect(m.filterId, 'warm');
      expect(m.hasDrawing, isTrue);
      expect(m.texts.map((t) => t.text), ['Hello', 'World']);
      expect(m.texts.map((t) => t.fontId), ['inter', 'mono']);
      expect(m.texts.first.colorValue, 0xFFE4572E);
      expect(m.stickerIds, ['star', 'heart']);
      expect(m.emojis, ['🔥']);
      final music = m.music!;
      expect(music.trackId, 'loop-1');
      expect(music.title, 'Sunrise');
      expect(music.artist, 'Example');
      expect(music.start, const Duration(seconds: 8));
      expect(music.duration, const Duration(seconds: 12));
      expect(music.volume, 0.7);
      expect(music.extra, {'licence': 'cc0'});
    });

    test('an untrimmed video reports the full source range', () {
      final result = controller().buildResult(
        exported(type: StoryMediaType.video),
        const StoryDocument(media: _landscapeVideo),
        savedToGallery: false,
      );

      expect(result.metadata.trimStart, Duration.zero);
      expect(result.metadata.trimEnd, const Duration(seconds: 30));
      expect(result.metadata.originalAudioVolume, 1);
    });

    test('a photo has no trim, no original audio and no extras', () {
      final result = controller().buildResult(
        exported(),
        const StoryDocument(media: _photo),
        savedToGallery: false,
      );
      final m = result.metadata;

      expect(m.source, StorySourceKind.camera);
      expect(m.sourceType, StoryMediaType.photo);
      expect(m.trimStart, isNull);
      expect(m.trimEnd, isNull);
      expect(m.originalAudioVolume, 0);
      expect(m.music, isNull);
      expect(m.filterId, isNull);
      expect(m.texts, isEmpty);
      expect(m.stickerIds, isEmpty);
      expect(m.emojis, isEmpty);
      expect(m.hasDrawing, isFalse);
      expect(result.duration, isNull);
    });
  });
}

class _ThrowingSaver implements GallerySaver {
  @override
  Future<void> save(String path, StoryMediaType type, {String? album}) =>
      Future.error(PlatformException(code: 'gal_error'));
}
