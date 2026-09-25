import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/src/api/errors/story_exception.dart';
import 'package:story_creator_kit/src/api/music/music_models.dart';
import 'package:story_creator_kit/src/core/session_files.dart';
import 'package:story_creator_kit/src/music/music_file_cache.dart';
import 'package:story_creator_kit/src/music/music_picker_controller.dart';
import 'package:story_creator_kit/src/music/music_preview_controller.dart';
import 'package:story_creator_kit/src/music/music_track_preparer.dart';

import '../../fakes/fake_services.dart';

class _FailingWaveformInspector extends FakeMediaInspector {
  int calls = 0;

  @override
  Future<List<double>> waveform(String path, {int buckets = 120}) async {
    calls++;
    throw const StoryException(StoryErrorCode.mediaUnsupported, 'no peaks');
  }
}

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  group('MusicPickerController', () {
    late FakeMusicProvider provider;
    late List<Object> errors;
    late MusicPickerController controller;

    MusicPickerController create({
      Duration debounce = const Duration(milliseconds: 40),
    }) => controller = MusicPickerController(
      provider: provider,
      searchDebounce: debounce,
      onError: (e, _) => errors.add(e),
    );

    setUp(() {
      provider = FakeMusicProvider();
      errors = [];
    });

    tearDown(() => controller.dispose());

    test('loads the first page of the first category', () async {
      create();
      expect(controller.status, MusicListStatus.loading);
      await controller.start();
      expect(controller.status, MusicListStatus.ready);
      expect(controller.tracks, hasLength(30));
      expect(controller.hasMore, isTrue);
      expect(provider.queries.single.categoryId, 'all');
      expect(provider.queries.single.cursor, isNull);
      await controller.start();
      expect(provider.queries, hasLength(1));
    });

    test('debounces rapid typing into one search request', () async {
      create();
      await controller.start();
      controller
        ..setSearch('T')
        ..setSearch('Tr')
        ..setSearch('Track 1 ');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(provider.queries, hasLength(1));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(provider.queries, hasLength(2));
      expect(provider.queries.last.search, 'Track 1');
      expect(controller.search, 'Track 1');
      expect(controller.tracks.map((t) => t.title), contains('Track 1'));
      expect(controller.tracks, hasLength(11));
    });

    test('typing back to the current text sends nothing', () async {
      create();
      await controller.start();
      controller
        ..setSearch('x')
        ..setSearch('');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(provider.queries, hasLength(1));
    });

    test('searchNow skips the debounce', () async {
      create(debounce: const Duration(seconds: 5));
      await controller.start();
      controller.searchNow('Track 4');
      await _flush();
      expect(provider.queries.last.search, 'Track 4');
      expect(controller.tracks.first.title, 'Track 4');
    });

    test('loads the next page with the cursor until the end', () async {
      create();
      await controller.start();
      await controller.loadMore();
      expect(provider.queries.last.cursor, '30');
      expect(controller.tracks, hasLength(45));
      expect(controller.hasMore, isFalse);
      await controller.loadMore();
      expect(provider.queries, hasLength(2));
    });

    test('does not request a page twice while one is loading', () async {
      final gate = Completer<void>();
      provider.beforeFetch = (q) =>
          q.cursor == null ? Future.value() : gate.future;
      create();
      await controller.start();
      final first = controller.loadMore();
      final second = controller.loadMore();
      expect(controller.loadingMore, isTrue);
      expect(provider.queries, hasLength(2));
      gate.complete();
      await Future.wait([first, second]);
      expect(provider.queries, hasLength(2));
      expect(controller.tracks, hasLength(45));
      expect(controller.loadingMore, isFalse);
    });

    test('drops a page that arrives after the category changed', () async {
      final gate = Completer<void>();
      provider.beforeFetch = (q) =>
          q.cursor == null ? Future.value() : gate.future;
      create();
      await controller.start();
      final stale = controller.loadMore();
      controller.selectCategory(provider.categories[1]);
      await _flush();
      gate.complete();
      await stale;
      expect(controller.category.id, 'bookmarked');
      expect(controller.tracks, hasLength(23));
      expect(controller.tracks.every((t) => t.bookmarked), isTrue);
      expect(controller.loadingMore, isFalse);
    });

    test('drops a first page that arrives after the search changed', () async {
      final gate = Completer<void>();
      provider.beforeFetch = (q) =>
          q.search == 'Track 1' ? gate.future : Future.value();
      create();
      await controller.start();
      controller.searchNow('Track 1');
      await _flush();
      controller.searchNow('Track 2');
      await _flush();
      gate.complete();
      await _flush();
      expect(controller.search, 'Track 2');
      expect(controller.tracks.first.title, 'Track 2');
    });

    test('clearCategory goes back to the first category', () async {
      create();
      await controller.start();
      controller.selectCategory(provider.categories[1]);
      expect(controller.isFirstCategory, isFalse);
      controller.clearCategory();
      await _flush();
      expect(controller.category.id, 'all');
      expect(provider.queries.map((q) => q.categoryId), [
        'all',
        'bookmarked',
        'all',
      ]);
    });

    test('an empty result shows the empty state', () async {
      provider = FakeMusicProvider(tracks: const []);
      create();
      await controller.start();
      expect(controller.status, MusicListStatus.empty);
    });

    test('a failure shows the error state and retry recovers', () async {
      provider.error = Exception('boom');
      create();
      await controller.start();
      expect(controller.status, MusicListStatus.error);
      expect(errors, hasLength(1));
      provider.error = null;
      await controller.retry();
      expect(controller.status, MusicListStatus.ready);
    });

    test('network failures show the offline state', () async {
      provider.error = const SocketException('no route');
      create();
      await controller.start();
      expect(controller.status, MusicListStatus.offline);
      provider.error = TimeoutException('slow');
      await controller.retry();
      expect(controller.status, MusicListStatus.offline);
    });

    test('a failed next page waits for retryLoadMore', () async {
      create();
      await controller.start();
      provider.error = Exception('page 2');
      await controller.loadMore();
      expect(controller.loadMoreFailed, isTrue);
      expect(controller.tracks, hasLength(30));
      await controller.loadMore();
      expect(provider.queries, hasLength(2));
      provider.error = null;
      await controller.retryLoadMore();
      expect(controller.loadMoreFailed, isFalse);
      expect(controller.tracks, hasLength(45));
    });

    test('bookmark toggles optimistically and calls the provider', () async {
      create();
      await controller.start();
      final track = controller.tracks[1];
      expect(controller.isBookmarked(track), isFalse);
      final pending = controller.toggleBookmark(track);
      expect(controller.isBookmarked(track), isTrue);
      await pending;
      expect(provider.bookmarkCalls, [('t1', true)]);
      expect(controller.isBookmarked(track), isTrue);
    });

    test('a failed bookmark reverts and keeps going', () async {
      provider.bookmarkError = Exception('nope');
      create();
      await controller.start();
      final track = controller.tracks[1];
      final pending = controller.toggleBookmark(track);
      expect(controller.isBookmarked(track), isTrue);
      await pending;
      expect(controller.isBookmarked(track), isFalse);
      expect(errors, hasLength(1));
      provider.bookmarkError = null;
      await controller.toggleBookmark(track);
      expect(controller.isBookmarked(track), isTrue);
    });

    test('bookmarks do nothing when unsupported', () async {
      provider = FakeMusicProvider(bookmarksSupported: false);
      create();
      await controller.start();
      await controller.toggleBookmark(controller.tracks[1]);
      expect(provider.bookmarkCalls, isEmpty);
    });
  });

  test('isMusicNetworkError sees through StoryException causes', () {
    expect(
      isMusicNetworkError(
        const StoryException(
          StoryErrorCode.musicUnavailable,
          null,
          HttpException('reset'),
        ),
      ),
      isTrue,
    );
    expect(isMusicNetworkError(Exception('x')), isFalse);
  });

  group('MusicPreviewController', () {
    late FakeMusicProvider provider;
    late FakeMusicSession session;
    late MusicPreviewController preview;

    setUp(() {
      provider = FakeMusicProvider();
      session = FakeMusicSession();
      preview = MusicPreviewController(provider: provider, session: session);
    });

    tearDown(() async {
      preview.dispose();
      await session.dispose();
    });

    final a = FakeMusicProvider.sampleTracks[0];
    final b = FakeMusicProvider.sampleTracks[1];

    test('plays the first 30 s once and stops on a second tap', () async {
      await preview.toggle(a);
      expect(preview.playingId, a.id);
      expect((session.loaded! as MusicFileSource).path, '/tmp/t0.m4a');
      expect(session.segment, (Duration.zero, const Duration(seconds: 30)));
      expect(session.lastLoop, isFalse);
      expect(session.playing.value, isTrue);
      await preview.toggle(a);
      expect(preview.playingId, isNull);
      expect(session.playing.value, isFalse);
    });

    test('a short track plays whole', () async {
      session.trackDuration = const Duration(seconds: 12);
      await preview.toggle(a);
      expect(session.segment, (Duration.zero, const Duration(seconds: 12)));
    });

    test('only one track previews at a time', () async {
      await preview.toggle(a);
      await preview.toggle(b);
      expect(preview.playingId, b.id);
      expect(session.loads, hasLength(2));
    });

    test('a failed preview throws musicUnavailable and resets', () async {
      session.loadError = Exception('decode');
      await expectLater(
        preview.toggle(a),
        throwsA(
          isA<StoryException>().having(
            (e) => e.code,
            'code',
            StoryErrorCode.musicUnavailable,
          ),
        ),
      );
      expect(preview.playingId, isNull);
    });

    test('clears the row when playback ends', () async {
      await preview.toggle(a);
      await session.pause();
      expect(preview.playingId, isNull);
    });
  });

  group('MusicTrackPreparer', () {
    late Directory tempDir;
    late FakeMusicProvider provider;
    late FakeMusicSession session;
    late File audio;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('music_prepare_test');
      audio = File('${tempDir.path}/a.m4a')..writeAsBytesSync([1]);
      provider = FakeMusicProvider()
        ..resolver = (_) async => MusicFileSource(audio.path);
      session = FakeMusicSession();
    });

    tearDown(() async {
      await session.dispose();
      tempDir.deleteSync(recursive: true);
    });

    MusicTrackPreparer create({
      FakeMediaInspector? inspector,
      List<StoryException>? nonFatal,
    }) => MusicTrackPreparer(
      provider: provider,
      cache: MusicFileCache(SessionFiles.at(tempDir)),
      session: session,
      inspector: inspector ?? FakeMediaInspector(),
      onNonFatalError: nonFatal?.add,
    );

    final track = FakeMusicProvider.sampleTracks[3];

    test('resolves, loads and reads the waveform', () async {
      final prepared = await create().prepare(track);
      expect(prepared.localPath, audio.path);
      expect(prepared.duration, const Duration(minutes: 3));
      expect(prepared.peaks, hasLength(120));
      expect((session.loaded! as MusicFileSource).path, audio.path);
    });

    test('re-selecting uses the cache without resolving again', () async {
      final preparer = create();
      await preparer.prepare(track);
      await preparer.prepare(track);
      expect(provider.resolved, ['t3']);
    });

    test(
      'prefers the track waveform and falls back to the track length',
      () async {
        session.trackDuration = null;
        final inspector = _FailingWaveformInspector();
        final prepared = await create(inspector: inspector)
            .prepare(track.copyWith(waveform: const [0.5, 1]));
        expect(prepared.peaks, [0.5, 1]);
        expect(prepared.duration, track.duration);
        expect(inspector.calls, 0);
      },
    );

    test('a missing waveform is non-fatal', () async {
      final nonFatal = <StoryException>[];
      final prepared = await create(
        inspector: _FailingWaveformInspector(),
        nonFatal: nonFatal,
      ).prepare(track);
      expect(prepared.peaks, isEmpty);
      expect(nonFatal, hasLength(1));
    });

    test('resolve failures are musicUnavailable', () async {
      provider.resolver = (_) async => throw Exception('licence');
      await expectLater(
        create().prepare(track),
        throwsA(
          isA<StoryException>().having(
            (e) => e.code,
            'code',
            StoryErrorCode.musicUnavailable,
          ),
        ),
      );
    });

    test('a cancelled token stops the preparation', () async {
      final cancel = MusicCancelToken()..cancel();
      await expectLater(
        create().prepare(track, cancel: cancel),
        throwsA(isA<MusicCancelledException>()),
      );
      expect(session.loads, isEmpty);
    });
  });
}
