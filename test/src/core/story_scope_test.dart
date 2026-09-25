import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/src/core/session_files.dart';
import 'package:story_creator_kit/src/core/story_scope.dart';
import 'package:story_creator_kit/src/render/painters/story_paint_resources_loader.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

import '../../fakes/fake_services.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('story_scope_test_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  StoryScope scope({
    StoryCreatorConfig config = const StoryCreatorConfig(),
    Widget child = const SizedBox(),
  }) => StoryScope(
    config: config,
    services: fakeServices(tempDir: tmp),
    session: SessionFiles.at(tmp),
    resources: createStoryPaintResources(config.editor),
    child: child,
  );

  group('report', () {
    test('forwards events to onEvent', () {
      final events = <StoryEvent>[];
      scope(config: StoryCreatorConfig(onEvent: events.add))
          .report(const StoryEvent(StoryEventType.opened));

      expect(events.single.type, StoryEventType.opened);
    });

    test('does nothing without onEvent', () {
      expect(
        () => scope().report(const StoryEvent(StoryEventType.opened)),
        returnsNormally,
      );
    });

    test('swallows callback exceptions and reports them to FlutterError', () {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);

      final s = scope(
        config: StoryCreatorConfig(
          onEvent: (_) => throw StateError('analytics down'),
        ),
      );

      expect(
        () => s.report(const StoryEvent(StoryEventType.completed)),
        returnsNormally,
      );
      expect(reported, hasLength(1));
      expect(reported.single.exception, isA<StateError>());
      expect(reported.single.library, 'story_creator_kit');
    });

    test('reportError sends an error event with the code', () {
      final events = <StoryEvent>[];
      final trace = StackTrace.current;
      const error = StoryException(StoryErrorCode.exportFailed, 'boom');

      scope(config: StoryCreatorConfig(onEvent: events.add))
          .reportError(error, trace);

      final event = events.single;
      expect(event.type, StoryEventType.error);
      expect(event.properties, {'code': 'exportFailed'});
      expect(event.error, same(error));
      expect(event.stackTrace, same(trace));
    });

    test("reportError falls back to the exception's own stack trace", () {
      final events = <StoryEvent>[];
      final trace = StackTrace.current;
      final error = StoryException(StoryErrorCode.unknown, null, null, trace);

      scope(config: StoryCreatorConfig(onEvent: events.add)).reportError(error);

      expect(events.single.stackTrace, same(trace));
    });
  });

  test('theme and strings are shortcuts into the config', () {
    const theme = StoryCreatorTheme(accent: Color(0xFF00FF00));
    const strings = StoryCreatorStrings(
      common: CommonStrings(close: 'Schliessen'),
    );
    final s = scope(
      config: const StoryCreatorConfig(theme: theme, strings: strings),
    );

    expect(s.theme.accent, const Color(0xFF00FF00));
    expect(s.strings.common.close, 'Schliessen');
  });

  testWidgets('of and read find the nearest scope', (tester) async {
    StoryScope? viaOf;
    StoryScope? viaRead;
    final s = scope(
      child: Builder(
        builder: (context) {
          viaOf = StoryScope.of(context);
          viaRead = StoryScope.read(context);
          return const SizedBox();
        },
      ),
    );

    await tester.pumpWidget(s);

    expect(viaOf, same(s));
    expect(viaRead, same(s));
  });

  testWidgets('of asserts when there is no scope', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    );

    expect(() => StoryScope.of(captured), throwsAssertionError);
  });

  test('updateShouldNotify only when an input changes', () {
    final config = StoryCreatorConfig(onEvent: (_) {});
    final services = fakeServices(tempDir: tmp);
    final session = SessionFiles.at(tmp);
    final resources = createStoryPaintResources(config.editor);
    StoryScope build({StoryCreatorConfig? c, SessionFiles? s}) => StoryScope(
      config: c ?? config,
      services: services,
      session: s ?? session,
      resources: resources,
      child: const SizedBox(),
    );

    expect(build().updateShouldNotify(build()), isFalse);
    expect(
      build(c: const StoryCreatorConfig()).updateShouldNotify(build()),
      isTrue,
    );
    expect(build(s: SessionFiles.at(tmp)).updateShouldNotify(build()), isTrue);
  });
}
