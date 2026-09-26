// Export screen → preview screen with the real exporter, inspector and
// video player on a device.
// ignore_for_file: implementation_imports

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:story_creator_kit/src/api/config/output_options.dart';
import 'package:story_creator_kit/src/api/config/story_creator_config.dart';
import 'package:story_creator_kit/src/api/result/story_result.dart';
import 'package:story_creator_kit/src/api/strings/story_creator_strings.dart';
import 'package:story_creator_kit/src/core/session_files.dart';
import 'package:story_creator_kit/src/core/story_canvas.dart';
import 'package:story_creator_kit/src/core/story_scope.dart';
import 'package:story_creator_kit/src/export/export_screen.dart';
import 'package:story_creator_kit/src/model/story_document.dart';
import 'package:story_creator_kit/src/model/story_media.dart';
import 'package:story_creator_kit/src/preview/preview_screen.dart';
import 'package:story_creator_kit/src/render/painters/story_paint_resources_loader.dart';
import 'package:story_creator_kit/src/services/export/story_exporter.dart';
import 'package:story_creator_kit/src/services/media/native_media_inspector.dart';
import 'package:story_creator_kit/src/services/story_services.dart';

import 'support/media_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('export screen exports a video and the preview plays it', (
    tester,
  ) async {
    final tmp = await getTemporaryDirectory();
    final root = Directory(
      '${tmp.path}/flow_it_${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    addTearDown(() => root.delete(recursive: true));
    final config = StoryCreatorConfig(
      output: OutputOptions(outputDirectory: '${root.path}/out'),
    );
    final services = StoryServices.platform(config);
    final path = await copyFixture('landscape_h264_stereo.mp4', root);
    final probe = await NativeMediaInspector().probe(path);
    final media = StoryMedia(
      path: path,
      type: StoryMediaType.video,
      width: probe.width,
      height: probe.height,
      source: StorySourceKind.gallery,
      duration: probe.duration,
      hasAudio: probe.hasAudio,
    );
    final document = StoryDocument(
      media: media,
      placement: StoryCanvas.defaultPlacement(media),
    );
    ExportedStory? exported;
    var aborted = false;
    var confirmed = false;

    Widget scoped(Widget child) => MaterialApp(
      home: Material(
        child: StoryScope(
          config: config,
          services: services,
          session: SessionFiles.at(root),
          resources: createStoryPaintResources(config.editor),
          child: child,
        ),
      ),
    );

    await tester.pumpWidget(
      scoped(
        ExportScreen(
          document: document,
          onExported: (s) => exported = s,
          onAbort: () => aborted = true,
        ),
      ),
    );
    expect(find.text(const ExportStrings().exporting), findsOneWidget);
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (exported == null && !aborted && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(aborted, isFalse);
    expect(exported, isNotNull);
    final story = exported!;
    expect(story.type, StoryMediaType.video);
    expect((story.width, story.height), (1080, 1920));
    expect(
      (story.duration!.inMilliseconds - 4000).abs(),
      lessThanOrEqualTo(100),
    );
    expect(File(story.thumbnailPath!).existsSync(), isTrue);

    await tester.pumpWidget(
      scoped(
        PreviewScreen(
          story: story,
          onConfirm: ({required savedToGallery}) => confirmed = true,
          onBack: () {},
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(
      find.bySemanticsLabel(const ExportStrings().videoPreview),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel(const ExportStrings().useStory));
    await tester.pump();
    expect(confirmed, isTrue);
  });
}
