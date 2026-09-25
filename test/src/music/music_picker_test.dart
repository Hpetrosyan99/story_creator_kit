import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/src/api/config/editor_options.dart';
import 'package:story_creator_kit/src/api/config/story_creator_config.dart';
import 'package:story_creator_kit/src/api/errors/story_exception.dart';
import 'package:story_creator_kit/src/api/events/story_event.dart';
import 'package:story_creator_kit/src/api/music/music_models.dart';
import 'package:story_creator_kit/src/core/session_files.dart';
import 'package:story_creator_kit/src/core/story_scope.dart';
import 'package:story_creator_kit/src/model/music_selection.dart';
import 'package:story_creator_kit/src/music/music_picker.dart';
import 'package:story_creator_kit/src/music/widgets/equalizer_bars.dart';
import 'package:story_creator_kit/src/render/painters/story_paint_resources_loader.dart';

import '../../fakes/fake_services.dart';

/// Hosts a button that opens the picker inside a [StoryScope].
class _Harness {
  _Harness({required this.provider, required this.tempDir})
    : session = FakeMusicSession();

  final FakeMusicProvider provider;
  final Directory tempDir;
  final FakeMusicSession session;
  final List<StoryEvent> events = [];
  MusicSelection? result;
  bool completed = false;

  Future<void> open(
    WidgetTester tester, {
    Duration segmentLength = const Duration(seconds: 15),
    MusicSelection? current,
    Duration debounce = const Duration(milliseconds: 350),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: StoryScope(
          config: StoryCreatorConfig(
            musicProvider: provider,
            onEvent: events.add,
          ),
          services: fakeServices(tempDir: tempDir, music: () => session),
          session: SessionFiles.at(tempDir),
          resources: createStoryPaintResources(const EditorOptions()),
          child: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => unawaited(
                  openMusicPicker(
                    context,
                    segmentLength: segmentLength,
                    current: current,
                    searchDebounce: debounce,
                  ).then((value) {
                    result = value;
                    completed = true;
                  }),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder row(String id) => find.byKey(ValueKey('music-track-$id'));

Finder inRow(String id, Finder finder) =>
    find.descendant(of: row(id), matching: finder);

Finder get list => find.byKey(const ValueKey('music-track-list'));

void main() {
  late Directory tempDir;
  late FakeMusicProvider provider;
  late _Harness harness;
  late File audio;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('music_picker_test');
    audio = File('${tempDir.path}/track.m4a')..writeAsBytesSync([1, 2, 3]);
    provider = FakeMusicProvider()
      ..resolver = (_) async => MusicFileSource(audio.path);
    harness = _Harness(provider: provider, tempDir: tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('list states', () {
    testWidgets('shows a spinner while the first page loads', (tester) async {
      final gate = Completer<void>();
      provider.beforeFetch = (_) => gate.future;
      await harness.open(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Search music'), findsOneWidget);
      gate.complete();
      await settle(tester);
      expect(find.text('Track 0'), findsOneWidget);
      expect(find.text('Artist 0 | 2:00'), findsOneWidget);
    });

    testWidgets('shows the empty state', (tester) async {
      harness = _Harness(
        provider: FakeMusicProvider(tracks: const []),
        tempDir: tempDir,
      );
      await harness.open(tester);
      expect(find.text('No tracks found.'), findsOneWidget);
    });

    testWidgets('shows the error state and retries', (tester) async {
      provider.error = Exception('boom');
      await harness.open(tester);
      expect(find.text('Music could not be loaded.'), findsOneWidget);
      expect(
        harness.events.where((e) => e.type == StoryEventType.error),
        isNotEmpty,
      );
      provider.error = null;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Track 0'), findsOneWidget);
    });

    testWidgets('shows the offline state for network errors', (tester) async {
      provider.error = const SocketException('offline');
      await harness.open(tester);
      expect(find.text('You appear to be offline.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('meets tap target and label guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      await harness.open(tester, current: _selection(Duration.zero));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  });

  group('search and categories', () {
    testWidgets('debounces typing into one request', (tester) async {
      await harness.open(tester);
      expect(provider.queries, hasLength(1));
      final field = find.byType(TextField);
      await tester.enterText(field, 'T');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(field, 'Tr');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(field, 'Track 2');
      await tester.pump(const Duration(milliseconds: 300));
      expect(provider.queries, hasLength(1));
      await tester.pump(const Duration(milliseconds: 100));
      await settle(tester);
      expect(provider.queries, hasLength(2));
      expect(provider.queries.last.search, 'Track 2');
      expect(row('t0'), findsNothing);
      expect(inRow('t2', find.text('Track 2')), findsOneWidget);
    });

    testWidgets('clear button resets the search at once', (tester) async {
      await harness.open(tester);
      await tester.enterText(find.byType(TextField), 'Track 2');
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      await tester.tap(find.byTooltip('Clear search'));
      await settle(tester);
      expect(provider.queries.last.search, '');
      expect(find.text('Track 0'), findsOneWidget);
    });

    testWidgets('a selected chip clears back to the first category', (
      tester,
    ) async {
      await harness.open(tester);
      await tester.tap(find.text('Bookmarked'));
      await settle(tester);
      expect(provider.queries.last.categoryId, 'bookmarked');
      expect(find.text('Track 1'), findsNothing);
      final chip = find.byKey(const ValueKey('music-category-bookmarked'));
      expect(
        find.descendant(of: chip, matching: find.byIcon(Icons.close)),
        findsOneWidget,
      );
      await tester.tap(chip);
      await settle(tester);
      expect(provider.queries.last.categoryId, 'all');
      expect(find.text('Track 1'), findsOneWidget);
    });
  });

  group('pagination', () {
    testWidgets('requests the next page near the end, once', (tester) async {
      final gate = Completer<void>();
      provider.beforeFetch = (q) =>
          q.cursor == null ? Future.value() : gate.future;
      await harness.open(tester);
      expect(provider.queries, hasLength(1));
      await tester.drag(list, const Offset(0, -1500));
      await tester.pump();
      await tester.pump();
      expect(provider.queries, hasLength(2));
      expect(provider.queries.last.cursor, '30');
      await tester.drag(list, const Offset(0, -800));
      await tester.pump();
      await tester.drag(list, const Offset(0, 300));
      await tester.pump();
      expect(provider.queries, hasLength(2));
      gate.complete();
      await settle(tester);
      await tester.drag(list, const Offset(0, -3000));
      await settle(tester);
      expect(find.text('Track 44'), findsOneWidget);
      expect(provider.queries, hasLength(2));
    });
  });

  group('bookmarks', () {
    testWidgets('toggle calls the provider and updates at once', (
      tester,
    ) async {
      await harness.open(tester);
      expect(inRow('t1', find.byTooltip('Bookmark')), findsOneWidget);
      await tester.tap(inRow('t1', find.byTooltip('Bookmark')));
      await tester.pump();
      expect(inRow('t1', find.byTooltip('Remove bookmark')), findsOneWidget);
      expect(provider.bookmarkCalls, [('t1', true)]);
      expect(
        tester.widget<Icon>(inRow('t1', find.byIcon(Icons.bookmark))).color,
        const StoryCreatorConfig().theme.accent,
      );
    });

    testWidgets('reverts when the provider fails and keeps going', (
      tester,
    ) async {
      provider.bookmarkError = Exception('nope');
      await harness.open(tester);
      await tester.tap(inRow('t1', find.byTooltip('Bookmark')));
      await tester.pump();
      expect(provider.bookmarkCalls, [('t1', true)]);
      expect(inRow('t1', find.byTooltip('Bookmark')), findsOneWidget);
      provider.bookmarkError = null;
      await tester.tap(inRow('t1', find.byTooltip('Bookmark')));
      await tester.pump();
      expect(inRow('t1', find.byTooltip('Remove bookmark')), findsOneWidget);
    });

    testWidgets('are hidden when the provider does not support them', (
      tester,
    ) async {
      harness = _Harness(
        provider: FakeMusicProvider(bookmarksSupported: false),
        tempDir: tempDir,
      );
      await harness.open(tester);
      expect(find.text('Track 0'), findsOneWidget);
      expect(find.byTooltip('Bookmark'), findsNothing);
      expect(find.byTooltip('Remove bookmark'), findsNothing);
    });
  });

  group('preview', () {
    testWidgets('tapping a row plays it and tapping again stops', (
      tester,
    ) async {
      await harness.open(tester);
      await tester.tap(find.text('Track 0'));
      await tester.pump();
      await tester.pump();
      final session = harness.session;
      expect((session.loaded! as MusicFileSource).path, audio.path);
      expect(session.segment, (Duration.zero, const Duration(seconds: 30)));
      expect(session.playing.value, isTrue);
      expect(inRow('t0', find.byType(EqualizerBars)), findsOneWidget);
      final title = tester.widget<Text>(find.text('Track 0'));
      expect(title.style?.color, const StoryCreatorConfig().theme.accent);

      await tester.tap(find.text('Track 1'));
      await tester.pump();
      await tester.pump();
      expect(inRow('t0', find.byType(EqualizerBars)), findsNothing);
      expect(inRow('t1', find.byType(EqualizerBars)), findsOneWidget);

      await tester.tap(find.text('Track 1'));
      await tester.pump();
      expect(session.playing.value, isFalse);
      expect(find.byType(EqualizerBars), findsNothing);
    });

    testWidgets('stops the preview when leaving', (tester) async {
      await harness.open(tester);
      await tester.tap(find.text('Track 0'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Back'));
      await settle(tester);
      expect(harness.completed, isTrue);
      expect(harness.session.disposed, isTrue);
    });
  });

  group('flow', () {
    testWidgets('select, choose a segment and finish', (tester) async {
      await harness.open(tester);
      await tester.tap(inRow('t0', find.byTooltip('Use this track')));
      await settle(tester);
      expect(find.text('Choose the part to use'), findsOneWidget);
      expect(find.text('Search music'), findsNothing);
      final session = harness.session;
      expect(session.segment, (Duration.zero, const Duration(seconds: 15)));
      expect(session.lastLoop, isTrue);

      await tester.drag(
        find.byKey(const ValueKey('music-waveform-strip')),
        const Offset(120, 0),
      );
      await settle(tester);
      final start = session.segment!.$1;
      expect(start, greaterThan(Duration.zero));
      expect(session.segment!.$2, const Duration(seconds: 15));

      await tester.tap(find.byTooltip('Done'));
      await settle(tester);
      expect(harness.completed, isTrue);
      final result = harness.result!;
      expect(result.track.id, 't0');
      expect(result.start, start);
      expect(result.duration, const Duration(seconds: 15));
      expect(result.localPath, audio.path);
      expect(result.volume, 1);
    });

    testWidgets('the segment window supports semantic steps', (tester) async {
      final handle = tester.ensureSemantics();
      await harness.open(tester);
      await tester.tap(inRow('t0', find.byTooltip('Use this track')));
      await settle(tester);
      final slider = find.semantics.byAction(SemanticsAction.increase);
      tester.semantics.increase(slider);
      await settle(tester);
      expect(harness.session.segment!.$1, const Duration(seconds: 1));
      expect(find.text('0:01'), findsOneWidget);
      tester.semantics.decrease(slider);
      await settle(tester);
      expect(harness.session.segment!.$1, Duration.zero);
      handle.dispose();
    });

    testWidgets('re-opening the current track starts at its start', (
      tester,
    ) async {
      final current = _selection(const Duration(seconds: 20), volume: 0.5);
      await harness.open(tester, current: current);
      await tester.tap(inRow('t0', find.byTooltip('Use this track')));
      await settle(tester);
      expect(harness.session.segment!.$1, const Duration(seconds: 20));
      expect(find.text('0:20'), findsOneWidget);
      await tester.tap(find.byTooltip('Done'));
      await settle(tester);
      expect(harness.result!.start, const Duration(seconds: 20));
      expect(harness.result!.volume, 0.5);
    });

    testWidgets('a track shorter than the segment is used whole', (
      tester,
    ) async {
      harness.session.trackDuration = const Duration(seconds: 10);
      await harness.open(tester);
      await tester.tap(inRow('t0', find.byTooltip('Use this track')));
      await settle(tester);
      await tester.tap(find.byTooltip('Done'));
      await settle(tester);
      expect(harness.result!.start, Duration.zero);
      expect(harness.result!.duration, const Duration(seconds: 10));
    });

    testWidgets('back from the segment selector returns to the list', (
      tester,
    ) async {
      await harness.open(tester);
      await tester.drag(list, const Offset(0, -200));
      await tester.pump();
      await tester.tap(inRow('t5', find.byTooltip('Use this track')));
      await settle(tester);
      expect(find.text('Choose the part to use'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await settle(tester);
      expect(harness.completed, isFalse);
      expect(find.text('Search music'), findsOneWidget);
      expect(row('t5'), findsOneWidget);
      expect(harness.session.playing.value, isFalse);
      expect(provider.queries, hasLength(1));
    });

    testWidgets('back returns the current selection', (tester) async {
      final current = _selection(const Duration(seconds: 3));
      await harness.open(tester, current: current);
      await tester.tap(find.byTooltip('Back'));
      await settle(tester);
      expect(harness.completed, isTrue);
      expect(harness.result, same(current));
    });

    testWidgets('remove returns null', (tester) async {
      await harness.open(tester, current: _selection(Duration.zero));
      await tester.tap(find.byTooltip('Remove music'));
      await settle(tester);
      expect(harness.completed, isTrue);
      expect(harness.result, isNull);
    });

    testWidgets('remove is offered only with current music', (tester) async {
      await harness.open(tester);
      expect(find.byTooltip('Remove music'), findsNothing);
    });

    testWidgets('an unavailable track shows a message and reports it', (
      tester,
    ) async {
      provider.resolver = (_) async => throw Exception('licence expired');
      await harness.open(tester);
      await tester.tap(inRow('t0', find.byTooltip('Use this track')));
      await settle(tester);
      expect(find.text('This track is unavailable.'), findsOneWidget);
      expect(find.text('Choose the part to use'), findsNothing);
      final error = harness.events.last.error!;
      expect(error.code, StoryErrorCode.musicUnavailable);
      expect(inRow('t0', find.byTooltip('Use this track')), findsOneWidget);
    });

    testWidgets('shows progress while a track is prepared', (tester) async {
      final gate = Completer<MusicSource>();
      provider.resolver = (_) => gate.future;
      await harness.open(tester);
      await tester.tap(inRow('t0', find.byTooltip('Use this track')));
      await tester.pump();
      expect(find.text('Preparing track…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(inRow('t0', find.byTooltip('Use this track')), findsNothing);
      gate.complete(MusicFileSource(audio.path));
      await settle(tester);
      expect(find.text('Choose the part to use'), findsOneWidget);
    });
  });

  testWidgets('without a provider the current selection comes back', (
    tester,
  ) async {
    final current = _selection(Duration.zero);
    MusicSelection? result;
    await tester.pumpWidget(
      MaterialApp(
        home: StoryScope(
          config: const StoryCreatorConfig(),
          services: fakeServices(tempDir: tempDir),
          session: SessionFiles.at(tempDir),
          resources: createStoryPaintResources(const EditorOptions()),
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showMusicPicker(
                context,
                segmentLength: const Duration(seconds: 15),
                current: current,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    expect(result, same(current));
  });
}

MusicSelection _selection(Duration start, {double volume = 1}) =>
    MusicSelection(
      track: FakeMusicProvider.sampleTracks.first,
      start: start,
      duration: const Duration(seconds: 15),
      localPath: '/tmp/current.m4a',
      volume: volume,
    );
