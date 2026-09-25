import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/services.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

class _Music extends StoryMusicProvider {
  const _Music();

  @override
  List<MusicCategory> get categories => const [
    MusicCategory(id: 'all', label: 'All'),
  ];

  @override
  Future<MusicPage> fetchTracks(MusicQuery query) async =>
      const MusicPage(tracks: []);

  @override
  Future<MusicSource> resolve(MusicTrack track) async =>
      const MusicAssetSource('assets/a.m4a');
}

final _result = StoryResult(
  path: '/out/story.jpg',
  type: StoryMediaType.photo,
  mimeType: 'image/jpeg',
  width: 1080,
  height: 1920,
  fileSizeBytes: 100,
  metadata: StoryMetadata(
    source: StorySourceKind.camera,
    sourceType: StoryMediaType.photo,
    createdAt: DateTime.utc(2026, 9, 25),
  ),
);

void main() {
  group('StoryCreatorConfig', () {
    test('music is enabled only with a provider and the tool on', () {
      expect(const StoryCreatorConfig().musicEnabled, isFalse);
      expect(
        const StoryCreatorConfig(musicProvider: _Music()).musicEnabled,
        isTrue,
      );
      expect(
        const StoryCreatorConfig(
          musicProvider: _Music(),
          editor: EditorOptions(enableMusic: false),
        ).musicEnabled,
        isFalse,
      );
    });

    test('defaults', () {
      const config = StoryCreatorConfig();

      expect(config.capture.galleryMode, GalleryMode.inApp);
      expect(config.capture.initialLens, StoryCameraLens.back);
      expect(config.constraints.maxVideoDuration, const Duration(seconds: 60));
      expect(config.constraints.minVideoDuration, const Duration(seconds: 1));
      expect(
        config.constraints.photoWithMusicDuration,
        const Duration(seconds: 15),
      );
      expect(config.output.saveToGallery, SaveToGalleryMode.button);
      expect(config.output.showPreview, isTrue);
      expect(config.output.jpegQuality, 90);
      expect(config.output.frameRate, 30);
      expect(config.editor.fonts, [StoryFont.system]);
      expect(config.editor.filters, StoryFilter.defaults);
      expect(config.theme.accent, const Color(0xFFE4572E));
    });
  });

  group('config asserts', () {
    test('CaptureOptions needs at least one media source', () {
      CaptureOptions build({required bool photo, required bool video}) =>
          CaptureOptions(
            enablePhoto: photo,
            enableVideo: video,
            galleryMode: GalleryMode.disabled,
          );

      expect(() => build(photo: false, video: false), throwsAssertionError);
      expect(build(photo: true, video: false).enablePhoto, isTrue);
    });

    test('MediaConstraints needs photos or videos', () {
      MediaConstraints build({required bool photos}) =>
          MediaConstraints(allowPhotos: photos, allowVideos: false);

      expect(() => build(photos: false), throwsAssertionError);
      expect(build(photos: true).allowPhotos, isTrue);
    });

    test('OutputOptions checks the JPEG quality range', () {
      OutputOptions build(int quality) => OutputOptions(jpegQuality: quality);

      expect(() => build(0), throwsAssertionError);
      expect(() => build(101), throwsAssertionError);
      expect(build(1).jpegQuality, 1);
      expect(build(100).jpegQuality, 100);
    });
  });

  group('StoryOutcome.resultOrNull', () {
    test('returns the result for StoryCompleted', () {
      expect(StoryCompleted(_result).resultOrNull, same(_result));
    });

    test('returns null for cancelled and failed', () {
      expect(
        const StoryCancelled(StoryCancelReason.userCancelled).resultOrNull,
        isNull,
      );
      expect(
        const StoryFailed(StoryException(StoryErrorCode.cameraUnavailable))
            .resultOrNull,
        isNull,
      );
    });

    test('StoryOutcome is exhaustively switchable', () {
      String describe(StoryOutcome outcome) => switch (outcome) {
        StoryCompleted(:final result) => 'done ${result.path}',
        StoryCancelled(:final reason) => 'cancelled ${reason.name}',
        StoryFailed(:final error) => 'failed ${error.code.name}',
      };

      expect(describe(StoryCompleted(_result)), 'done /out/story.jpg');
      expect(
        describe(const StoryCancelled(StoryCancelReason.dismissed)),
        'cancelled dismissed',
      );
    });
  });

  group('StoryFilter', () {
    test('defaults have 20-entry matrices and unique ids', () {
      final ids = <String>{};
      for (final filter in StoryFilter.defaults) {
        expect(filter.matrix, hasLength(20), reason: filter.id);
        expect(filter.label, isNotEmpty, reason: filter.id);
        expect(ids.add(filter.id), isTrue, reason: 'duplicate ${filter.id}');
      }
      expect(StoryFilter.defaults.length, greaterThanOrEqualTo(8));
    });

    test('original comes first and is the only identity filter', () {
      expect(StoryFilter.defaults.first, StoryFilter.original);
      expect(StoryFilter.original.isIdentity, isTrue);
      expect(StoryFilter.defaults.skip(1).where((f) => f.isIdentity), isEmpty);
    });

    test('alpha row of every default leaves alpha unchanged', () {
      for (final filter in StoryFilter.defaults) {
        expect(filter.matrix.sublist(15), [0, 0, 0, 1, 0], reason: filter.id);
      }
    });

    test('equality is by id', () {
      expect(
        const StoryFilter(id: 'original', label: 'x', matrix: []),
        StoryFilter.original,
      );
    });
  });

  group('StoryException.toString', () {
    test('code only', () {
      expect(
        const StoryException(StoryErrorCode.exportFailed).toString(),
        'StoryException(exportFailed)',
      );
    });

    test('code and message', () {
      expect(
        const StoryException(
          StoryErrorCode.captureFailed,
          'no frame',
        ).toString(),
        'StoryException(captureFailed: no frame)',
      );
    });

    test('code, message and cause', () {
      expect(
        StoryException(
          StoryErrorCode.mediaUnavailable,
          'gone',
          StateError('deleted'),
        ).toString(),
        'StoryException(mediaUnavailable: gone, cause: Bad state: deleted)',
      );
    });

    test('code and cause without message', () {
      expect(
        const StoryException(StoryErrorCode.unknown, null, 'x').toString(),
        'StoryException(unknown, cause: x)',
      );
    });
  });

  group('StoryEvent', () {
    test('toString includes the type, properties and error', () {
      expect(
        const StoryEvent(
          StoryEventType.toolOpened,
          properties: {'tool': 'text'},
        ).toString(),
        'StoryEvent(toolOpened, {tool: text})',
      );
      expect(
        const StoryEvent(
          StoryEventType.error,
          error: StoryException(StoryErrorCode.unknown),
        ).toString(),
        'StoryEvent(error, {}, StoryException(unknown))',
      );
    });
  });

  group('music models', () {
    test('StoryMusicProvider defaults: no bookmarks, setBookmarked fails', () {
      const provider = _Music();
      const track = MusicTrack(
        id: 'a',
        title: 'A',
        artist: 'B',
        duration: Duration(seconds: 30),
      );

      expect(provider.supportsBookmarks, isFalse);
      expect(
        provider.setBookmarked(track, bookmarked: true),
        throwsUnsupportedError,
      );
    });

    test('MusicTrack.copyWith keeps identity fields', () {
      const track = MusicTrack(
        id: 'a',
        title: 'A',
        artist: 'B',
        duration: Duration(seconds: 30),
        extra: {'k': 1},
      );

      final copy = track.copyWith(bookmarked: true, waveform: [0.1, 0.9]);

      expect(copy.id, 'a');
      expect(copy.title, 'A');
      expect(copy.extra, {'k': 1});
      expect(copy.bookmarked, isTrue);
      expect(copy.waveform, [0.1, 0.9]);
      expect(copy, isNot(track), reason: 'bookmark state is part of ==');
      expect(track.copyWith(), track);
    });

    test('MusicQuery defaults', () {
      const q = MusicQuery(categoryId: 'all');
      expect(q.search, '');
      expect(q.cursor, isNull);
      expect(q.pageSize, 30);
    });

    test('MusicUrlSource defaults to no headers', () {
      final source = MusicUrlSource(Uri.parse('https://example.com/a.m4a'));
      expect(source.headers, isEmpty);
    });
  });

  group('theme and strings', () {
    test('StoryCreatorTheme.copyWith replaces only the given values', () {
      const theme = StoryCreatorTheme();

      final copy = theme.copyWith(
        accent: const Color(0xFF0000FF),
        cornerRadius: 4,
      );

      expect(copy.accent, const Color(0xFF0000FF));
      expect(copy.cornerRadius, 4);
      expect(copy.background, theme.background);
      expect(copy.chipRadius, theme.chipRadius);
    });

    test('text styles follow the theme colours and font', () {
      const theme = StoryCreatorTheme(
        onSurface: Color(0xFF010203),
        onSurfaceMuted: Color(0xFF040506),
        fontFamily: 'Inter',
      );

      expect(theme.titleStyle.color, const Color(0xFF010203));
      expect(theme.bodyStyle.fontFamily, 'Inter');
      expect(theme.captionStyle.color, const Color(0xFF040506));
      expect(theme.labelStyle.fontSize, 12);
    });

    test('strings can be overridden per group', () {
      const strings = StoryCreatorStrings(
        camera: CameraStrings(takePhoto: 'Foto aufnehmen'),
        export: ExportStrings(useStory: 'Story verwenden'),
      );

      expect(strings.camera.takePhoto, 'Foto aufnehmen');
      expect(strings.camera.switchCamera, 'Switch camera');
      expect(strings.export.useStory, 'Story verwenden');
      expect(strings.common.close, 'Close');
    });
  });

  group('services barrel', () {
    test('ExportedStory.mimeType follows the type', () {
      const photo = ExportedStory(
        path: '/a.jpg',
        type: StoryMediaType.photo,
        width: 1080,
        height: 1920,
        fileSizeBytes: 1,
      );
      const video = ExportedStory(
        path: '/a.mp4',
        type: StoryMediaType.video,
        width: 1080,
        height: 1920,
        fileSizeBytes: 1,
      );

      expect(photo.mimeType, 'image/jpeg');
      expect(video.mimeType, 'video/mp4');
    });

    test('CaptureCapabilities.canSwitchLens needs two lenses', () {
      const one = CaptureCapabilities(
        lens: StoryCameraLens.back,
        availableLenses: {StoryCameraLens.back},
        hasFlash: true,
        minZoom: 1,
        maxZoom: 4,
        previewAspectRatio: 9 / 16,
      );
      const two = CaptureCapabilities(
        lens: StoryCameraLens.back,
        availableLenses: {StoryCameraLens.back, StoryCameraLens.front},
        hasFlash: true,
        minZoom: 1,
        maxZoom: 4,
        previewAspectRatio: 9 / 16,
      );

      expect(one.canSwitchLens, isFalse);
      expect(two.canSwitchLens, isTrue);
    });
  });
}
