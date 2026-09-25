import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/src/core/story_canvas.dart';
import 'package:story_creator_kit/src/model/drawing_stroke.dart';
import 'package:story_creator_kit/src/model/media_placement.dart';
import 'package:story_creator_kit/src/model/overlay_transform.dart';
import 'package:story_creator_kit/src/model/story_overlay.dart';
import 'package:story_creator_kit/src/render/painters/story_edits_painter.dart';
import 'package:story_creator_kit/src/render/painters/story_paint_resources.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

/// Paints [paint] on a canvas scaled so one unit is one canvas unit.
class _CanvasPainter extends CustomPainter {
  _CanvasPainter(this.draw);

  final void Function(Canvas canvas) draw;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / StoryCanvas.width);
    StoryEditsPainter.paintBackground(
      canvas,
      const StoryBackground(top: Color(0xFF3A6EA5), bottom: Color(0xFF1B2F45)),
    );
    draw(canvas);
  }

  @override
  bool shouldRepaint(_CanvasPainter oldDelegate) => true;
}

Future<void> _pumpCanvas(
  WidgetTester tester,
  void Function(Canvas canvas) draw,
) async {
  await tester.pumpWidget(
    Center(
      child: RepaintBoundary(
        child: CustomPaint(
          size: const Size(432, 768),
          painter: _CanvasPainter(draw),
        ),
      ),
    ),
  );
}

final StoryPaintResources _resources = StoryPaintResources(
  fonts: const [StoryFont.system],
  stickerImages: {},
  filters: StoryFilter.defaults,
);

TextOverlay _text(
  String text,
  TextBackgroundStyle background, {
  TextAlign align = TextAlign.center,
  Offset position = StoryCanvas.center,
  Color color = const Color(0xFFFFC53D),
  double rotation = 0,
}) => TextOverlay(
  id: '${background.name}-$align-$position',
  transform: OverlayTransform(position: position, rotation: rotation),
  text: text,
  style: TextOverlayStyle(
    fontId: 'system',
    color: color,
    align: align,
    background: background,
  ),
);

void main() {
  for (final background in TextBackgroundStyle.values) {
    testWidgets('text background ${background.name}', (tester) async {
      await _pumpCanvas(tester, (canvas) {
        for (final (i, align) in [
          TextAlign.left,
          TextAlign.center,
          TextAlign.right,
        ].indexed) {
          StoryEditsPainter.paintOverlay(
            canvas,
            _text(
              'Hi\nstory world\nabc',
              background,
              align: align,
              position: Offset(StoryCanvas.width / 2, 380.0 + i * 520),
            ),
            _resources,
          );
        }
      });
      await expectLater(
        find.byType(RepaintBoundary),
        matchesGoldenFile('goldens/text_${background.name}.png'),
      );
    });
  }

  testWidgets('rotated and scaled highlight text', (tester) async {
    await _pumpCanvas(tester, (canvas) {
      StoryEditsPainter.paintOverlay(
        canvas,
        _text(
          'a\nwide line here\nmid',
          TextBackgroundStyle.highlight,
          color: const Color(0xFFEB2F96),
          rotation: -math.pi / 12,
        ).withTransform(
          const OverlayTransform(
            position: StoryCanvas.center,
            scale: 1.3,
            rotation: -math.pi / 12,
          ),
        ),
        _resources,
      );
    });
    await expectLater(
      find.byType(RepaintBoundary),
      matchesGoldenFile('goldens/text_highlight_transformed.png'),
    );
  });

  testWidgets('strokes: pen, marker, neon and an eraser pass', (tester) async {
    List<StrokePoint> wave(double y, {double amplitude = 60}) => [
      for (var x = 120.0; x <= 960; x += 12)
        StrokePoint(x, y + amplitude * math.sin(x / 90)),
    ];
    final strokes = [
      DrawingStroke(
        points: wave(420),
        color: const Color(0xFFFFFFFF),
        size: 28,
      ),
      DrawingStroke(
        points: wave(760),
        color: const Color(0xFFFFC53D),
        size: 36,
        tool: StrokeTool.marker,
      ),
      DrawingStroke(
        points: wave(1100),
        color: const Color(0xFF13C2C2),
        size: 30,
        tool: StrokeTool.neon,
      ),
      DrawingStroke(
        points: [for (var y = 300.0; y <= 1300; y += 12) StrokePoint(540, y)],
        color: const Color(0xFF000000),
        size: 60,
        tool: StrokeTool.eraser,
      ),
      // Drawn after the eraser: stays intact.
      DrawingStroke(
        points: wave(1450, amplitude: 30),
        color: const Color(0xFFE4572E),
        size: 24,
      ),
    ];
    await _pumpCanvas(
      tester,
      (canvas) => StoryEditsPainter.paintStrokes(canvas, strokes),
    );
    await expectLater(
      find.byType(RepaintBoundary),
      matchesGoldenFile('goldens/strokes_with_eraser.png'),
    );
  });

  testWidgets('emoji overlay', (tester) async {
    await _pumpCanvas(tester, (canvas) {
      StoryEditsPainter.paintOverlay(
        canvas,
        const EmojiOverlay(
          id: 'e',
          transform: OverlayTransform(
            position: StoryCanvas.center,
            rotation: 0.3,
          ),
          emoji: 'A',
        ),
        _resources,
      );
    });
    await expectLater(
      find.byType(RepaintBoundary),
      matchesGoldenFile('goldens/emoji.png'),
    );
  });
}
