import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/services.dart';
import 'package:story_creator_kit/src/core/media_import.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

import '../../fakes/fake_services.dart';

void main() {
  late Directory root;
  late Directory outside;
  late SessionFiles session;
  late FakeMediaInspector inspector;

  setUp(() {
    root = Directory.systemTemp.createTempSync('media_import_test_');
    outside = Directory('${root.path}/outside')..createSync();
    session = SessionFiles.at(Directory('${root.path}/session')..createSync());
    inspector = FakeMediaInspector();
  });
  tearDown(() => root.deleteSync(recursive: true));

  MediaImporter importer([
    MediaConstraints constraints = const MediaConstraints(),
  ]) => MediaImporter(
    inspector: inspector,
    session: session,
    constraints: constraints,
  );

  String file(String name, {int bytes = 16}) {
    final f = File('${outside.path}/$name')
      ..writeAsBytesSync(List.filled(bytes, 7));
    return f.path;
  }

  MediaProbe video(Duration duration, {bool audio = true}) => MediaProbe(
    width: 1920,
    height: 1080,
    fileSizeBytes: 16,
    duration: duration,
    rotationDegrees: 90,
    hasVideo: true,
    hasAudio: audio,
  );

  group('captured', () {
    test('photo is moved into the session with probed size', () async {
      final path = file('shot.jpg');
      inspector.defaultProbe = const MediaProbe(
        width: 3024,
        height: 4032,
        fileSizeBytes: 16,
      );

      final media = await importer().importCaptured(
        CapturedFile(
          path: path,
          type: StoryMediaType.photo,
          lens: StoryCameraLens.front,
          mirrored: true,
        ),
      );

      expect(media.path, startsWith(session.directory.path));
      expect(File(media.path).existsSync(), isTrue);
      expect(File(path).existsSync(), isFalse);
      expect(media.width, 3024);
      expect(media.height, 4032);
      expect(media.source, StorySourceKind.camera);
      expect(media.mirrored, isTrue);
      expect(media.duration, isNull);
      expect(media.hasAudio, isFalse);
      expect(media.mimeType, 'image/jpeg');
    });

    test('video uses probed duration, rotation and audio', () async {
      inspector.defaultProbe = video(const Duration(milliseconds: 5230));

      final media = await importer().importCaptured(
        CapturedFile(
          path: file('clip.mp4'),
          type: StoryMediaType.video,
          lens: StoryCameraLens.back,
          duration: const Duration(seconds: 6),
        ),
      );

      expect(media.duration, const Duration(milliseconds: 5230));
      expect(media.rotationDegrees, 90);
      expect(media.width, 1920);
      expect(media.hasAudio, isTrue);
      expect(media.mimeType, 'video/mp4');
    });

    test(
      'falls back to the capture duration when the probe has none',
      () async {
        inspector.defaultProbe = const MediaProbe(
          width: 1080,
          height: 1920,
          fileSizeBytes: 16,
        );

        final media = await importer().importCaptured(
          CapturedFile(
            path: file('clip.mp4'),
            type: StoryMediaType.video,
            lens: StoryCameraLens.back,
            duration: const Duration(seconds: 4),
          ),
        );

        expect(media.duration, const Duration(seconds: 4));
      },
    );

    test(
      'too short → MediaTooShortException and the file is deleted',
      () async {
        inspector.defaultProbe = video(const Duration(milliseconds: 600));
        final path = file('clip.mp4');

        await expectLater(
          importer().importCaptured(
            CapturedFile(
              path: path,
              type: StoryMediaType.video,
              lens: StoryCameraLens.back,
            ),
          ),
          throwsA(
            isA<MediaTooShortException>()
                .having((e) => e.code, 'code', StoryErrorCode.mediaTooShort)
                .having(
                  (e) => e.duration,
                  'duration',
                  const Duration(milliseconds: 600),
                ),
          ),
        );
        expect(File(path).existsSync(), isFalse);
        expect(session.directory.listSync(), isEmpty);
      },
    );
  });

  group('picked', () {
    test('is copied; the original stays', () async {
      final path = file('IMG_0001.HEIC');

      final media = await importer().importPicked(
        PickedMedia(path: path, type: StoryMediaType.photo),
      );

      expect(File(path).existsSync(), isTrue);
      expect(media.path, startsWith(session.directory.path));
      expect(media.path, endsWith('.heic'));
      expect(media.source, StorySourceKind.gallery);
      expect(media.mimeType, 'image/heic');
      expect(media.mirrored, isFalse);
    });

    test('keeps the picker MIME type', () async {
      final media = await importer().importPicked(
        PickedMedia(
          path: file('noext'),
          type: StoryMediaType.photo,
          mimeType: 'image/webp',
        ),
      );
      expect(media.mimeType, 'image/webp');
      expect(media.path, endsWith('.jpg'));
    });

    test('a video longer than the maximum is accepted', () async {
      inspector.defaultProbe = video(const Duration(minutes: 5));

      final media = await importer().importPicked(
        PickedMedia(path: file('long.mov'), type: StoryMediaType.video),
      );

      expect(media.duration, const Duration(minutes: 5));
      expect(media.mimeType, 'video/quicktime');
    });

    test('a video without a readable duration is unsupported', () async {
      await expectLater(
        importer().importPicked(
          PickedMedia(path: file('clip.mp4'), type: StoryMediaType.video),
        ),
        throwsA(
          isA<StoryException>().having(
            (e) => e.code,
            'code',
            StoryErrorCode.mediaUnsupported,
          ),
        ),
      );
      expect(session.directory.listSync(), isEmpty);
    });

    test('larger than maxImportFileSizeBytes → mediaTooLarge', () async {
      final path = file('big.jpg', bytes: 2048);

      await expectLater(
        importer(const MediaConstraints(maxImportFileSizeBytes: 1024))
            .importPicked(PickedMedia(path: path, type: StoryMediaType.photo)),
        throwsA(
          isA<StoryException>().having(
            (e) => e.code,
            'code',
            StoryErrorCode.mediaTooLarge,
          ),
        ),
      );
      expect(File(path).existsSync(), isTrue);
      expect(session.directory.listSync(), isEmpty);
    });

    test('a disallowed type → mediaUnsupported', () async {
      await expectLater(
        importer(const MediaConstraints(allowVideos: false)).importPicked(
          PickedMedia(path: file('clip.mp4'), type: StoryMediaType.video),
        ),
        throwsA(
          isA<StoryException>().having(
            (e) => e.code,
            'code',
            StoryErrorCode.mediaUnsupported,
          ),
        ),
      );
    });

    test('a missing file → mediaUnavailable', () async {
      await expectLater(
        importer().importPicked(
          PickedMedia(
            path: '${outside.path}/gone.jpg',
            type: StoryMediaType.photo,
          ),
        ),
        throwsA(
          isA<StoryException>().having(
            (e) => e.code,
            'code',
            StoryErrorCode.mediaUnavailable,
          ),
        ),
      );
    });

    test(
      'a probe failure → mediaUnsupported; typed probe errors pass',
      () async {
        inspector.probeError = Exception('decoder');
        await expectLater(
          importer().importPicked(
            PickedMedia(path: file('a.jpg'), type: StoryMediaType.photo),
          ),
          throwsA(
            isA<StoryException>()
                .having((e) => e.code, 'code', StoryErrorCode.mediaUnsupported)
                .having((e) => e.cause, 'cause', isA<Exception>()),
          ),
        );

        inspector.probeError = const StoryException(
          StoryErrorCode.mediaUnavailable,
        );
        await expectLater(
          importer().importPicked(
            PickedMedia(path: file('b.jpg'), type: StoryMediaType.photo),
          ),
          throwsA(
            isA<StoryException>().having(
              (e) => e.code,
              'code',
              StoryErrorCode.mediaUnavailable,
            ),
          ),
        );
        expect(session.directory.listSync(), isEmpty);
      },
    );

    test('a zero-size probe → mediaUnsupported', () async {
      inspector.defaultProbe = const MediaProbe(
        width: 0,
        height: 0,
        fileSizeBytes: 16,
      );
      await expectLater(
        importer().importPicked(
          PickedMedia(path: file('a.png'), type: StoryMediaType.photo),
        ),
        throwsA(
          isA<StoryException>().having(
            (e) => e.code,
            'code',
            StoryErrorCode.mediaUnsupported,
          ),
        ),
      );
    });
  });
}
