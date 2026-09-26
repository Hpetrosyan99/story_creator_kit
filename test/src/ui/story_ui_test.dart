import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/src/core/session_files.dart';
import 'package:story_creator_kit/src/core/story_scope.dart';
import 'package:story_creator_kit/src/render/painters/story_paint_resources_loader.dart';
import 'package:story_creator_kit/src/ui/story_icon.dart';
import 'package:story_creator_kit/src/ui/story_nav_button.dart';
import 'package:story_creator_kit/src/ui/story_stage.dart';
import 'package:story_creator_kit/src/ui/story_surface.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

import '../../fakes/fake_services.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('story_ui_test');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Widget wrap(Widget child, {bool glass = false}) {
    final config = StoryCreatorConfig(
      theme: StoryCreatorTheme(isLiquidGlassEnabled: glass),
    );
    return MaterialApp(
      home: BackdropGroup(
        child: Material(
          child: StoryScope(
            config: config,
            services: fakeServices(tempDir: temp),
            session: SessionFiles.at(temp),
            resources: createStoryPaintResources(config.editor),
            child: child,
          ),
        ),
      ),
    );
  }

  group('StoryIcon', () {
    testWidgets('takes its design box and draws the SVG at its own size', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const Center(child: StoryIcon(StoryIcons.flash))),
      );
      expect(tester.getSize(find.byType(StoryIcon)), const Size(20, 20));
      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(svg.width, 24);
      expect(svg.height, closeTo(29, 0.01));
    });

    testWidgets(
      'the design shadow is a pre-rendered image, never a live blur',
      (tester) async {
        await tester.pumpWidget(
          wrap(const Center(child: StoryIcon(StoryIcons.flash))),
        );
        // Live blurs on every icon starved the GPU during video export.
        expect(find.byType(ImageFiltered), findsNothing);
        expect(find.byType(BackdropFilter), findsNothing);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();
        final shadow = tester.widget<RawImage>(find.byType(RawImage));
        expect(shadow.image, isNotNull);
        // 24 x 29 SVG plus a 7.5 px blur margin on each side.
        expect(tester.getSize(find.byType(RawImage)).width, 39);
      },
    );

    testWidgets('icons without a shadow draw only the SVG', (tester) async {
      await tester.pumpWidget(
        wrap(const Center(child: StoryIcon(StoryIcons.close))),
      );
      expect(find.byType(RawImage), findsNothing);
      expect(find.byType(SvgPicture), findsOneWidget);
    });

    test('every icon asset exists', () {
      for (final icon in StoryIcons.values) {
        expect(File(icon.assetKey).existsSync(), isTrue, reason: icon.assetKey);
      }
    });
  });

  group('StorySurface', () {
    testWidgets('flat when liquid glass is off', (tester) async {
      await tester.pumpWidget(
        wrap(
          const Center(
            child: StorySurface(
              fill: Color(0x80141414),
              radius: 22,
              child: SizedBox.square(dimension: 44),
            ),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('flat while its screen is covered (TickerMode off)', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const TickerMode(
            enabled: false,
            child: Center(
              child: StorySurface(
                fill: Color(0x80141414),
                radius: 22,
                child: SizedBox.square(dimension: 44),
              ),
            ),
          ),
          glass: true,
        ),
      );
      // Hidden blurs stalled exports; covered screens draw flat.
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('frosted backdrop when liquid glass is on', (tester) async {
      await tester.pumpWidget(
        wrap(
          const Center(
            child: StorySurface(
              fill: Color(0x80141414),
              radius: 22,
              child: SizedBox.square(dimension: 44),
            ),
          ),
          glass: true,
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });

  group('StoryNavButton', () {
    testWidgets('is a 44 px circle with a 48 px target and a label', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          Center(
            child: StoryNavButton(
              icon: StoryIcons.close,
              label: 'Close',
              onPressed: () => taps++,
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(StoryNavButton)), const Size(48, 48));
      await tester.tap(find.bySemanticsLabel('Close'));
      expect(taps, 1);
    });

    testWidgets('liquid glass applies to translucent buttons only', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Row(
            children: [
              StoryNavButton(
                icon: StoryIcons.close,
                label: 'Close',
                onPressed: () {},
              ),
              StoryNavButton(
                icon: StoryIcons.check,
                label: 'Done',
                style: StoryNavButtonStyle.accent,
                onPressed: () {},
              ),
            ],
          ),
          glass: true,
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });

  group('StoryStage', () {
    testWidgets('the card fills the space between the safe areas', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const StoryStage(card: ColoredBox(color: Colors.red))),
      );
      final card = tester.getRect(find.byType(ClipRRect).first);
      final screen = tester.getRect(find.byType(StoryStage));
      expect(card.width, screen.width);
      expect(screen.bottom - card.bottom, 16);
    });
  });
}
