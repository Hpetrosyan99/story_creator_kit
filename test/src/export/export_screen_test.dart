import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/src/api/config/editor_options.dart';
import 'package:story_creator_kit/src/api/config/output_options.dart';
import 'package:story_creator_kit/src/api/config/story_creator_config.dart';
import 'package:story_creator_kit/src/api/errors/story_exception.dart';
import 'package:story_creator_kit/src/api/events/story_event.dart';
import 'package:story_creator_kit/src/api/result/story_result.dart';
import 'package:story_creator_kit/src/api/strings/story_creator_strings.dart';
import 'package:story_creator_kit/src/core/session_files.dart';
import 'package:story_creator_kit/src/core/story_scope.dart';
import 'package:story_creator_kit/src/export/export_screen.dart';
import 'package:story_creator_kit/src/model/story_document.dart';
import 'package:story_creator_kit/src/model/story_media.dart';
import 'package:story_creator_kit/src/render/painters/story_paint_resources_loader.dart';
import 'package:story_creator_kit/src/services/export/story_exporter.dart';

import '../../fakes/fake_services.dart';

const _strings = ExportStrings();

/// Lets real file IO (export directory creation) and the widget's async
/// start-up interleave until they are done.
Future<void> settleIo(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pump();
}

const _common = CommonStrings();

void main() {
  late Directory dir;
  late FakeStoryExporter exporter;
  late List<ExportedStory> exported;
  late int aborts;
  late List<StoryEvent> events;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('export_screen');
    exporter = FakeStoryExporter(autoComplete: false);
    exported = [];
    aborts = 0;
    events = [];
  });

  tearDown(() async => dir.delete(recursive: true));

  StoryDocument doc() => StoryDocument(
    media: StoryMedia(
      path: '${dir.path}/p.jpg',
      type: StoryMediaType.photo,
      width: 1080,
      height: 1920,
      source: StorySourceKind.camera,
    ),
  );

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoryScope(
            config: StoryCreatorConfig(
              output: OutputOptions(outputDirectory: '${dir.path}/out'),
              onEvent: events.add,
            ),
            services: fakeServices(tempDir: dir, exporter: exporter),
            session: SessionFiles.at(dir),
            resources: createStoryPaintResources(const EditorOptions()),
            child: ExportScreen(
              document: doc(),
              onExported: exported.add,
              onAbort: () => aborts++,
            ),
          ),
        ),
      ),
    );
    await settleIo(tester);
  }

  testWidgets('shows progress as a percentage', (tester) async {
    await pump(tester);
    expect(exporter.lastJob, isNotNull);
    expect(exporter.lastJob!.context.outputDirectory, '${dir.path}/out');
    expect(find.text(_strings.exporting), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    exporter.lastJob!.emitProgress(0.42);
    await settleIo(tester);
    expect(find.text('42%'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel(_strings.exportProgress)).value,
      '42%',
    );
  });

  testWidgets('completes with the exported story', (tester) async {
    await pump(tester);
    await tester.runAsync(() => exporter.lastJob!.finish());
    await settleIo(tester);
    expect(exported, hasLength(1));
    expect(exported.single.type, StoryMediaType.photo);
    expect(aborts, 0);
  });

  testWidgets('cancel asks first; keep going does nothing', (tester) async {
    await pump(tester);
    await tester.tap(find.text(_strings.cancelExport));
    await tester.pumpAndSettle();
    expect(find.text(_strings.cancelExportTitle), findsOneWidget);
    await tester.tap(find.text(_strings.keepExporting));
    await tester.pumpAndSettle();
    expect(exporter.lastJob!.cancelled, isFalse);
    expect(aborts, 0);
  });

  testWidgets('confirmed cancel stops the job and returns to the editor', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text(_strings.cancelExport));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_strings.stopExport));
    await tester.pumpAndSettle();
    expect(exporter.lastJob!.cancelled, isTrue);
    expect(aborts, 1);
    expect(exported, isEmpty);
  });

  testWidgets('system back while exporting asks to cancel', (tester) async {
    await pump(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(_strings.cancelExportTitle), findsOneWidget);
  });

  testWidgets('failure shows the message, reports it and retries', (
    tester,
  ) async {
    exporter.failWith = const StoryException(StoryErrorCode.exportFailed);
    await pump(tester);
    await tester.runAsync(() => exporter.lastJob!.finish());
    await settleIo(tester);
    expect(find.text(_strings.exportFailed), findsOneWidget);
    expect(events.where((e) => e.type == StoryEventType.error), hasLength(1));
    final firstJob = exporter.lastJob;

    exporter.failWith = null;
    await tester.tap(find.text(_common.retry));
    await settleIo(tester);
    expect(exporter.lastJob, isNot(same(firstJob)));
    expect(find.text(_strings.exporting), findsOneWidget);
    await tester.runAsync(() => exporter.lastJob!.finish());
    await settleIo(tester);
    expect(exported, hasLength(1));
  });

  testWidgets('insufficient storage has its own message; back aborts', (
    tester,
  ) async {
    exporter.failWith = const StoryException(
      StoryErrorCode.insufficientStorage,
    );
    await pump(tester);
    await tester.runAsync(() => exporter.lastJob!.finish());
    await settleIo(tester);
    expect(find.text(_strings.notEnoughSpace), findsOneWidget);
    await tester.tap(find.text(_common.back));
    await tester.pump();
    expect(aborts, 1);
  });

  testWidgets('system back after a failure returns to the editor', (
    tester,
  ) async {
    exporter.failWith = const StoryException(StoryErrorCode.exportFailed);
    await pump(tester);
    await tester.runAsync(() => exporter.lastJob!.finish());
    await settleIo(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(aborts, 1);
  });

  testWidgets('controls meet tap-target guidelines', (tester) async {
    await pump(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });
}
