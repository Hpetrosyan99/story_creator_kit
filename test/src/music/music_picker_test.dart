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
import 'package:story_creator_kit/src/music/segment_selector.dart';
import 'package:story_creator_kit/src/music/widgets/equalizer_bars.dart';
import 'package:story_creator_kit/src/render/painters/story_paint_resources_loader.dart';
import 'package:story_creator_kit/src/ui/story_icon.dart';
import 'package:story_creator_kit/src/ui/story_nav_button.dart';
import 'package:story_creator_kit/src/ui/story_stage.dart';

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

/// Background colour of a row, `null` when it has none.
Color? rowColor(WidgetTester tester, String id) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(of: row(id), matching: find.byType(DecoratedBox)).first,
  );
  return (box.decoration as BoxDecoration).color;
}

Finder get list => find.byKey(const ValueKey('music-track-list'));

Finder icon(StoryIcons value) =>
    find.byWidgetPredicate((w) => w is StoryIcon && w.icon == value);

Finder key(String value) => find.byKey(ValueKey(value));

Finder get selector => find.byType(MusicSegmentSelector);

Finder get picker => find.text('Search music');

/// A catalog whose second category is a ranking.
class _RankedProvider extends FakeMusicProvider {
  @override
  List<MusicCategory> get categories => const [
    MusicCategory(id: 'all', label: 'All'),
    MusicCategory(id: 'top', label: 'Leaderboard', showRanks: true),
  ];
}

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
    testWidgets('shows a skeleton while the first page loads', (tester) async {
      final gate = Completer<void>();
      provider.beforeFetch = (_) => gate.future;
      await harness.open(tester);
      expect(key('music-list-skeleton'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(picker, findsOneWidget);
      gate.complete();
      await settle(tester);
      expect(key('music-list-skeleton'), findsNothing);
      expect(find.text('Track 0'), findsOneWidget);
      expect(find.text('Artist 0 | 02:00'), findsOneWidget);
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
      await tester.tap(key('music-search-clear'));
      await settle(tester);
      expect(provider.queries.last.search, '');
      expect(find.text('Track 0'), findsOneWidget);
    });

    testWidgets('a selected chip clears back to the first category', (
      tester,
    ) async {
      await harness.open(tester);
      final all = key('music-category-all');
      expect(
        find.descendant(of: all, matching: icon(StoryIcons.chipClose)),
        findsOneWidget,
      );
      await tester.tap(find.text('Bookmarked'));
      await settle(tester);
      expect(provider.queries.last.categoryId, 'bookmarked');
      expect(find.text('Track 1'), findsNothing);
      final chip = key('music-category-bookmarked');
      expect(
        find.descendant(of: chip, matching: icon(StoryIcons.chipClose)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: all, matching: icon(StoryIcons.chipClose)),
        findsNothing,
      );
      await tester.tap(chip);
      await settle(tester);
      expect(provider.queries.last.categoryId, 'all');
      expect(find.text('Track 1'), findsOneWidget);
    });

    testWidgets('the chip ✕ also clears the search, with one request', (
      tester,
    ) async {
      await harness.open(tester);
      await tester.tap(find.text('Bookmarked'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'Track 2');
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(provider.queries.last.search, 'Track 2');
      final before = provider.queries.length;

      await tester.tap(key('music-category-bookmarked'));
      await settle(tester);
      expect(provider.queries, hasLength(before + 1));
      expect(provider.queries.last.categoryId, 'all');
      expect(provider.queries.last.search, '');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.text('Track 1'), findsOneWidget);

      // Nothing to clear: no request.
      await tester.tap(key('music-category-all'));
      await settle(tester);
      expect(provider.queries, hasLength(before + 1));
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
      expect(inRow('t1', icon(StoryIcons.bookmark)), findsOneWidget);
      await tester.tap(inRow('t1', key('music-bookmark')));
      await tester.pump();
      expect(inRow('t1', icon(StoryIcons.bookmark)), findsNothing);
      expect(provider.bookmarkCalls, [('t1', true)]);
      expect(
        tester
            .widget<StoryIcon>(inRow('t1', icon(StoryIcons.bookmarkFilled)))
            .color,
        const StoryCreatorConfig().theme.accent,
      );
      // Toggling the bookmark does not pick the track.
      expect(selector, findsNothing);
    });

    testWidgets('reverts when the provider fails and keeps going', (
      tester,
    ) async {
      provider.bookmarkError = Exception('nope');
      await harness.open(tester);
      await tester.tap(inRow('t1', key('music-bookmark')));
      await tester.pump();
      expect(provider.bookmarkCalls, [('t1', true)]);
      expect(inRow('t1', icon(StoryIcons.bookmark)), findsOneWidget);
      provider.bookmarkError = null;
      await tester.tap(inRow('t1', key('music-bookmark')));
      await tester.pump();
      expect(inRow('t1', icon(StoryIcons.bookmarkFilled)), findsOneWidget);
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
      expect(key('music-bookmark'), findsNothing);
      expect(icon(StoryIcons.bookmark), findsNothing);
      expect(icon(StoryIcons.bookmarkFilled), findsNothing);
    });
  });

  group('ranked categories', () {
    setUp(() {
      provider = _RankedProvider()
        ..resolver = (_) async => MusicFileSource(audio.path);
      harness = _Harness(provider: provider, tempDir: tempDir);
    });

    testWidgets('show the rank and a ⋮ menu instead of the bookmark', (
      tester,
    ) async {
      await harness.open(tester);
      expect(inRow('t0', find.text('1')), findsNothing);
      expect(inRow('t0', key('music-bookmark')), findsOneWidget);

      await tester.tap(find.text('Leaderboard'));
      await settle(tester);
      expect(provider.queries.last.categoryId, 'top');
      expect(inRow('t0', find.text('1')), findsOneWidget);
      expect(inRow('t1', find.text('2')), findsOneWidget);
      expect(inRow('t0', key('music-bookmark')), findsNothing);
      expect(inRow('t1', icon(StoryIcons.moreVertical)), findsOneWidget);
      final rank = tester.widget<Text>(inRow('t1', find.text('2')));
      expect(
        rank.style?.color,
        const StoryCreatorConfig().theme.onSurfaceSecondary,
      );

      await tester.tap(inRow('t1', key('music-more')));
      await settle(tester);
      expect(selector, findsNothing);
      await tester.tap(find.text('Bookmark'));
      await settle(tester);
      expect(provider.bookmarkCalls, [('t1', true)]);

      await tester.tap(inRow('t1', key('music-more')));
      await settle(tester);
      expect(find.text('Remove bookmark'), findsOneWidget);
    });
  });

  group('preview', () {
    testWidgets('a long press previews a row in the playing style', (
      tester,
    ) async {
      final theme = const StoryCreatorConfig().theme;
      await harness.open(tester);
      await tester.longPress(find.text('Track 0'));
      await tester.pump();
      await tester.pump();
      final session = harness.session;
      expect((session.loaded! as MusicFileSource).path, audio.path);
      expect(session.segment, (Duration.zero, const Duration(seconds: 30)));
      expect(session.playing.value, isTrue);
      expect(selector, findsNothing);
      final bars = tester.widget<EqualizerBars>(
        inRow('t0', find.byType(EqualizerBars)),
      );
      expect(bars.animating, isTrue);
      expect(bars.color, theme.accent);
      final title = tester.widget<Text>(find.text('Track 0'));
      expect(title.style?.color, theme.accent);
      expect(rowColor(tester, 't0'), theme.surface);
      expect(rowColor(tester, 't1'), isNull);

      await tester.longPress(find.text('Track 1'));
      await tester.pump();
      await tester.pump();
      expect(inRow('t0', find.byType(EqualizerBars)), findsNothing);
      expect(inRow('t1', find.byType(EqualizerBars)), findsOneWidget);
      expect(rowColor(tester, 't0'), isNull);

      await tester.longPress(find.text('Track 1'));
      await tester.pump();
      expect(session.playing.value, isFalse);
      expect(find.byType(EqualizerBars), findsNothing);
    });

    testWidgets('the current track is highlighted, not animated', (
      tester,
    ) async {
      await harness.open(tester, current: _selection(Duration.zero));
      final bars = tester.widget<EqualizerBars>(
        inRow('t0', find.byType(EqualizerBars)),
      );
      expect(bars.animating, isFalse);
      expect(rowColor(tester, 't0'), const StoryCreatorConfig().theme.surface);
      expect(find.byType(EqualizerBars), findsOneWidget);
    });

    testWidgets('stops the preview when leaving', (tester) async {
      await harness.open(tester);
      await tester.longPress(find.text('Track 0'));
      await tester.pump();
      await tester.pump();
      await tester.tap(key('music-back'));
      await settle(tester);
      expect(harness.completed, isTrue);
      expect(harness.session.disposed, isTrue);
    });
  });

  group('flow', () {
    testWidgets('tap a row, choose a segment and finish', (tester) async {
      await harness.open(tester);
      await tester.tap(find.text('Track 0'));
      await settle(tester);
      expect(selector, findsOneWidget);
      expect(picker, findsNothing);
      expect(find.text('Choose the part to use'), findsNothing);
      final session = harness.session;
      expect(session.segment, (Duration.zero, const Duration(seconds: 15)));
      expect(session.lastLoop, isTrue);

      // Dragging the waveform left moves the start later.
      await tester.drag(key('music-waveform-strip'), const Offset(-120, 0));
      await settle(tester);
      final start = session.segment!.$1;
      expect(start, greaterThan(Duration.zero));
      expect(start, lessThanOrEqualTo(const Duration(seconds: 15)));
      expect(session.segment!.$2, const Duration(seconds: 15));

      await tester.tap(key('music-segment-done'));
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
      await tester.tap(find.text('Track 0'));
      await settle(tester);
      expect(find.bySemanticsLabel('Track 0 by Artist 0'), findsOneWidget);
      final slider = find.semantics.byAction(SemanticsAction.increase);
      tester.semantics.increase(slider);
      await settle(tester);
      expect(harness.session.segment!.$1, const Duration(seconds: 1));
      expect(
        tester.getSemantics(find.byType(MusicWaveformStrip)),
        matchesSemantics(
          label: 'Choose the part to use',
          value: '0:01',
          increasedValue: '0:02',
          decreasedValue: '0:00',
          isSlider: true,
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );
      tester.semantics.decrease(slider);
      await settle(tester);
      expect(harness.session.segment!.$1, Duration.zero);
      handle.dispose();
    });

    testWidgets('the segment window fills up to the playback position', (
      tester,
    ) async {
      final theme = const StoryCreatorConfig().theme;
      await harness.open(tester);
      await tester.tap(find.text('Track 0'));
      await settle(tester);
      final window = key('music-segment-window');
      final fill = key('music-segment-fill');
      expect(tester.getSize(window), const Size(120, 41));
      expect(tester.getSize(fill).width, 0);
      expect(
        tester
            .widget<ColoredBox>(
              find.descendant(of: fill, matching: find.byType(ColoredBox)),
            )
            .color,
        theme.accent,
      );

      await harness.session.seek(const Duration(milliseconds: 7500));
      await tester.pump();
      expect(tester.getSize(fill).width, closeTo(60, 0.01));
      expect(
        tester.getTopLeft(fill).dx,
        closeTo(tester.getTopLeft(window).dx, 0.01),
      );

      await harness.session.seek(const Duration(seconds: 30));
      await tester.pump();
      expect(tester.getSize(fill).width, closeTo(120, 0.01));

      // After a drag the new segment replays from its start: empty again.
      await tester.drag(key('music-waveform-strip'), const Offset(-60, 0));
      await settle(tester);
      expect(harness.session.segment!.$1, greaterThan(Duration.zero));
      expect(tester.getSize(fill).width, 0);
    });

    testWidgets('the segment selector is a stage with dimmed canvas', (
      tester,
    ) async {
      await harness.open(tester);
      await tester.tap(find.text('Track 0'));
      await settle(tester);
      expect(
        find.descendant(of: selector, matching: find.byType(StoryStage)),
        findsOneWidget,
      );
      final done = tester.widget<StoryNavButton>(key('music-segment-done'));
      expect(done.style, StoryNavButtonStyle.subtle);
      expect(done.icon, StoryIcons.check);
      final close = tester.widget<StoryNavButton>(key('music-segment-close'));
      expect(close.style, StoryNavButtonStyle.translucent);
      expect(close.icon, StoryIcons.close);
      expect(
        find.descendant(
          of: selector,
          matching: find.byWidgetPredicate(
            (w) =>
                w is ColoredBox &&
                w.color == const StoryCreatorConfig().theme.scrim,
          ),
        ),
        findsOneWidget,
      );
      // No visible title or track text.
      expect(find.text('Track 0'), findsNothing);
    });

    testWidgets('re-opening the current track starts at its start', (
      tester,
    ) async {
      final current = _selection(const Duration(seconds: 20), volume: 0.5);
      await harness.open(tester, current: current);
      await tester.tap(find.text('Track 0'));
      await settle(tester);
      expect(harness.session.segment!.$1, const Duration(seconds: 20));
      await tester.tap(key('music-segment-done'));
      await settle(tester);
      expect(harness.result!.start, const Duration(seconds: 20));
      expect(harness.result!.volume, 0.5);
    });

    testWidgets('a track shorter than the segment is used whole', (
      tester,
    ) async {
      harness.session.trackDuration = const Duration(seconds: 10);
      await harness.open(tester);
      await tester.tap(find.text('Track 0'));
      await settle(tester);
      await tester.tap(key('music-segment-done'));
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
      await tester.tap(inRow('t5', find.text('Track 5')));
      await settle(tester);
      expect(selector, findsOneWidget);
      await tester.tap(key('music-segment-close'));
      await settle(tester);
      expect(harness.completed, isFalse);
      expect(picker, findsOneWidget);
      expect(row('t5'), findsOneWidget);
      expect(harness.session.playing.value, isFalse);
      expect(provider.queries, hasLength(1));
    });

    testWidgets('back returns the current selection', (tester) async {
      final current = _selection(const Duration(seconds: 3));
      await harness.open(tester, current: current);
      await tester.tap(key('music-back'));
      await settle(tester);
      expect(harness.completed, isTrue);
      expect(harness.result, same(current));
    });

    testWidgets('remove returns null', (tester) async {
      await harness.open(tester, current: _selection(Duration.zero));
      await tester.tap(key('music-remove'));
      await settle(tester);
      expect(harness.completed, isTrue);
      expect(harness.result, isNull);
    });

    testWidgets('remove is offered only with current music', (tester) async {
      await harness.open(tester);
      expect(key('music-remove'), findsNothing);
    });

    testWidgets('an unavailable track shows a message and reports it', (
      tester,
    ) async {
      provider.resolver = (_) async => throw Exception('licence expired');
      await harness.open(tester);
      await tester.tap(find.text('Track 0'));
      await settle(tester);
      expect(find.text('This track is unavailable.'), findsOneWidget);
      expect(selector, findsNothing);
      final error = harness.events.last.error!;
      expect(error.code, StoryErrorCode.musicUnavailable);
      expect(inRow('t0', key('music-preparing')), findsNothing);
      expect(inRow('t0', key('music-bookmark')), findsOneWidget);
    });

    testWidgets('shows progress while a track is prepared', (tester) async {
      final gate = Completer<MusicSource>();
      provider.resolver = (_) => gate.future;
      await harness.open(tester);
      await tester.tap(find.text('Track 0'));
      await tester.pump();
      expect(inRow('t0', key('music-preparing')), findsOneWidget);
      expect(inRow('t0', key('music-bookmark')), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(rowColor(tester, 't0'), const StoryCreatorConfig().theme.surface);
      // Other rows ignore taps while a track is prepared.
      await tester.tap(find.text('Track 1'));
      await tester.pump();
      expect(provider.resolved, ['t0']);
      gate.complete(MusicFileSource(audio.path));
      await settle(tester);
      expect(selector, findsOneWidget);
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
