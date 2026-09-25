import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/src/core/story_canvas.dart';
import 'package:story_creator_kit/src/editor/text/story_text_field.dart';
import 'package:story_creator_kit/src/model/overlay_transform.dart';
import 'package:story_creator_kit/src/model/story_overlay.dart';
import 'package:story_creator_kit/src/render/painters/story_edits_painter.dart';
import 'package:story_creator_kit/src/render/painters/story_paint_resources.dart';
import 'package:story_creator_kit/src/render/painters/story_text_layout.dart';
import 'package:story_creator_kit/src/render/painters/text_background_painter.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

/// Line start offsets of [text] as laid out by [painter].
List<int> _painterLineStarts(TextPainter painter, String text) {
  final starts = <int>{};
  for (var i = 0; i <= text.length; i++) {
    starts.add(painter.getLineBoundary(TextPosition(offset: i)).start);
  }
  return starts.toList()..sort();
}

/// Line start offsets of [text] in the editing field.
List<int> _fieldLineStarts(RenderEditable editable, String text) {
  final starts = <int>{};
  for (var i = 0; i <= text.length; i++) {
    starts.add(editable.getLineAtOffset(TextPosition(offset: i)).start);
  }
  return starts.toList()..sort();
}

const _samples = [
  'Hello',
  'The quick brown fox jumps over the lazy dog',
  'A much longer caption that certainly wraps onto several lines of text in the story',
  'Line one\nLine two is a little longer than the first\n\nafter a gap',
  'Supercalifragilisticexpialidocious',
  'Spaces    between   words   and trailing   ',
  'Emoji 🎉 in the 🔥 middle of a sentence ✨✨',
];

void main() {
  const font = StoryFont.system;
  const display = StoryFont(id: 'display', label: 'Display', uppercase: true);

  group('StoryTextLayout', () {
    tearDown(StoryTextLayout.clearCache);

    test('wraps at maxTextWidth and ignores text scaling', () {
      const style = TextOverlayStyle(fontId: 'system', color: Colors.white);
      final layout = StoryTextLayout.forText(_samples[2], style, font);
      expect(
        layout.painter.width,
        lessThanOrEqualTo(StoryTextLayout.maxTextWidth),
      );
      expect(layout.painter.computeLineMetrics().length, greaterThan(1));
      expect(layout.painter.textScaler, TextScaler.noScaling);
      expect(
        layout.size.width,
        layout.painter.width + 2 * layout.horizontalPadding,
      );
    });

    test('solid and highlight draw text in a contrasting colour', () {
      const white = TextOverlayStyle(
        fontId: 'system',
        color: Colors.white,
        background: TextBackgroundStyle.solid,
      );
      expect(StoryTextLayout.foregroundColor(white), const Color(0xFF000000));
      expect(
        StoryTextLayout.foregroundColor(
          white.copyWith(
            color: const Color(0xFF1677FF),
            background: TextBackgroundStyle.highlight,
          ),
        ),
        const Color(0xFFFFFFFF),
      );
      expect(
        StoryTextLayout.foregroundColor(
          white.copyWith(background: TextBackgroundStyle.none),
        ),
        Colors.white,
      );
    });

    test('display fonts upper-case the text without changing length', () {
      expect(StoryTextLayout.displayText('abc', display), 'ABC');
      // Never changes the length, so field offsets stay valid.
      expect(StoryTextLayout.displayText('straße', display), hasLength(6));
      expect(StoryTextLayout.displayText('abc', font), 'abc');
    });

    test('empty lines split the highlight', () {
      const style = TextOverlayStyle(fontId: 'system', color: Colors.white);
      final layout = StoryTextLayout.forText('a\n\nb', style, font);
      expect(layout.lineRects.length, 3);
      expect(layout.lineRects[1], isNull);
    });

    test('caches layouts and clears them', () {
      const style = TextOverlayStyle(fontId: 'system', color: Colors.white);
      final a = StoryTextLayout.forText('cache me', style, font);
      expect(
        identical(a, StoryTextLayout.forText('cache me', style, font)),
        isTrue,
      );
      StoryTextLayout.clearCache();
      expect(
        identical(a, StoryTextLayout.forText('cache me', style, font)),
        isFalse,
      );
    });
  });

  group('TextBackgroundPainter.snapEdges', () {
    test('equalises nearly aligned edges', () {
      final lines = TextBackgroundPainter.snapEdges([
        const Rect.fromLTRB(10, 0, 100, 10),
        const Rect.fromLTRB(14, 10, 96, 20),
        const Rect.fromLTRB(40, 20, 60, 30),
      ], 5);
      expect(lines[0].left, 10);
      expect(lines[1].left, 10);
      expect(lines[0].right, 100);
      expect(lines[1].right, 100);
      expect(lines[2].left, 40);
      expect(lines[2].right, 60);
    });

    test('the merged path covers every line and the fillet corners', () {
      final path = TextBackgroundPainter.highlightPath([
        const Rect.fromLTRB(40, 0, 60, 20),
        const Rect.fromLTRB(0, 20, 100, 40),
      ], 6);
      expect(path.contains(const Offset(50, 10)), isTrue);
      expect(path.contains(const Offset(5, 30)), isTrue);
      // Inside the concave fillet next to the narrow line's bottom corner.
      expect(path.contains(const Offset(61, 19.5)), isTrue);
      // Outside: above the wide line, away from the narrow one.
      expect(path.contains(const Offset(80, 10)), isFalse);
    });
  });

  group('overlay sizes', () {
    final resources = StoryPaintResources(
      fonts: const [font],
      stickerImages: {},
      filters: StoryFilter.defaults,
    );

    test('text size equals the layout', () {
      const overlay = TextOverlay(
        id: 't',
        transform: OverlayTransform(position: StoryCanvas.center),
        text: 'Sized',
        style: TextOverlayStyle(fontId: 'system', color: Colors.white),
      );
      expect(
        StoryEditsPainter.overlaySize(overlay, resources),
        StoryTextLayout.of(overlay, font).size,
      );
    });

    test('undecoded sticker is a square of the base size', () {
      const overlay = StickerOverlay(
        id: 's',
        transform: OverlayTransform(position: StoryCanvas.center),
        stickerId: 'missing',
      );
      expect(
        StoryEditsPainter.overlaySize(overlay, resources),
        const Size(
          StickerOverlay.defaultBaseSize,
          StickerOverlay.defaultBaseSize,
        ),
      );
    });

    test('emoji has a positive size', () {
      const overlay = EmojiOverlay(
        id: 'e',
        transform: OverlayTransform(position: StoryCanvas.center),
        emoji: '🔥',
      );
      final size = StoryEditsPainter.overlaySize(overlay, resources);
      expect(size.width, greaterThan(0));
      expect(size.height, greaterThan(0));
    });
  });

  testWidgets('a line exactly as wide as the wrap width fits in both', (
    tester,
  ) async {
    // FlutterTest glyphs are 1 em wide: 10 × 90 = maxTextWidth.
    const style = TextOverlayStyle(
      fontId: 'system',
      color: Colors.white,
      fontSize: 90,
    );
    const text = 'abcdefghij';
    for (final screenWidth in [320.0, 360.0, 375.0, 390.0, 412.0, 430.0]) {
      final controller = StoryTextEditingController(font, text: text);
      final focus = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: StoryTextField(
                controller: controller,
                focusNode: focus,
                style: style,
                font: font,
                viewScale: screenWidth / StoryCanvas.width,
                hint: '',
                hintColor: Colors.grey,
                cursorColor: Colors.orange,
              ),
            ),
          ),
        ),
      );
      final editable = tester.allRenderObjects
          .whereType<RenderEditable>()
          .single;
      final layout = StoryTextLayout.forText(text, style, font);
      expect(layout.painter.computeLineMetrics(), hasLength(1));
      expect(_fieldLineStarts(editable, text), [0], reason: '$screenWidth');
      // One more glyph wraps in both.
      controller.text = '${text}k';
      await tester.pump();
      expect(
        _fieldLineStarts(editable, '${text}k'),
        _painterLineStarts(
          StoryTextLayout.forText('${text}k', style, font).painter,
          '${text}k',
        ),
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      focus.dispose();
    }
  });

  group('editing field line breaks equal the painter', () {
    for (final screenWidth in [320.0, 375.0, 390.0, 430.0]) {
      for (final fontSize in [60.0, 88.0, 140.0]) {
        for (final align in [
          TextAlign.left,
          TextAlign.center,
          TextAlign.right,
        ]) {
          testWidgets('screen $screenWidth, size $fontSize, ${align.name}', (
            tester,
          ) async {
            final viewScale = screenWidth / StoryCanvas.width;
            for (final storyFont in [font, display]) {
              final style = TextOverlayStyle(
                fontId: storyFont.id,
                color: Colors.white,
                align: align,
                fontSize: fontSize,
              );
              for (final sample in _samples) {
                final controller = StoryTextEditingController(
                  storyFont,
                  text: sample,
                );
                final focus = FocusNode();
                await tester.pumpWidget(
                  MaterialApp(
                    home: MediaQuery(
                      // Host text scaling must not change the layout.
                      data: const MediaQueryData(
                        textScaler: TextScaler.linear(1.8),
                      ),
                      child: Material(
                        child: Center(
                          child: SingleChildScrollView(
                            child: StoryTextField(
                              controller: controller,
                              focusNode: focus,
                              style: style,
                              font: storyFont,
                              viewScale: viewScale,
                              hint: '',
                              hintColor: Colors.grey,
                              cursorColor: Colors.orange,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                final editable = tester.allRenderObjects
                    .whereType<RenderEditable>()
                    .single;
                final layout = StoryTextLayout.forText(
                  sample,
                  style,
                  storyFont,
                );
                expect(
                  _fieldLineStarts(editable, sample),
                  _painterLineStarts(layout.painter, sample),
                  reason: '"$sample" (${storyFont.id})',
                );
                await tester.pumpWidget(const SizedBox());
                controller.dispose();
                focus.dispose();
              }
            }
          });
        }
      }
    }
  });
}
