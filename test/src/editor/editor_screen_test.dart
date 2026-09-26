import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/services.dart';
import 'package:story_creator_kit/src/core/story_canvas.dart';
import 'package:story_creator_kit/src/editor/canvas/media_layer.dart';
import 'package:story_creator_kit/src/editor/canvas/trash_zone.dart';
import 'package:story_creator_kit/src/editor/text/story_text_field.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

import '../../fakes/fake_services.dart';
import 'editor_test_harness.dart';

TextOverlay _textAt(Offset position, {String text = 'Hi', double scale = 1}) =>
    TextOverlay(
      id: 'text-$text',
      transform: OverlayTransform(position: position, scale: scale),
      text: text,
      style: const TextOverlayStyle(fontId: 'system', color: Color(0xFFFFFFFF)),
    );

StoryDocument Function(StoryMedia) _withOverlays(List<StoryOverlay> overlays) =>
    (media) => StoryDocument(media: media, overlays: overlays);

void main() {
  group('text (AC8)', () {
    testWidgets('tap on the empty canvas adds text; Done commits it', (
      tester,
    ) async {
      final h = await pumpEditor(tester);
      await addText(tester, 'Hello story');

      final doc = await h.export(tester);
      final text = doc.overlays.single as TextOverlay;
      expect(text.text, 'Hello story');
      expect(text.transform.position, StoryCanvas.center);
      expect(text.style.fontId, StoryFont.system.id);
    });

    testWidgets('empty text on Done adds nothing', (tester) async {
      final h = await pumpEditor(tester);
      await addText(tester, '   ');
      expect((await h.export(tester)).overlays, isEmpty);
    });

    testWidgets('tap on text edits it; style controls apply', (tester) async {
      final h = await pumpEditor(tester);
      await addText(tester, 'Hello');
      await tester.tapAt(canvasPoint(tester, StoryCanvas.center));
      await tester.pump();

      expect(find.byType(StoryTextField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Hello',
      );
      await tester.enterText(find.byType(TextField), 'Hello again');
      // Alignment centre → right, background none → solid → translucent.
      await tester.tap(find.bySemanticsLabel(strings.editor.alignCenter));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(strings.editor.backgroundNone));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(strings.editor.backgroundSolid));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(strings.editor.colorSwatch(3)));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(strings.common.done));
      await tester.pump();

      final text = (await h.export(tester)).overlays.single as TextOverlay;
      expect(text.text, 'Hello again');
      expect(text.style.align, TextAlign.right);
      expect(text.style.background, TextBackgroundStyle.translucent);
      expect(text.style.color, EditorOptions.defaultColors[2]);
    });

    testWidgets('clearing the text deletes the overlay', (tester) async {
      final h = await pumpEditor(
        tester,
        document: _withOverlays([_textAt(StoryCanvas.center)]),
      );
      await tester.tapAt(canvasPoint(tester, StoryCanvas.center));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.bySemanticsLabel(strings.common.done));
      await tester.pump();
      expect((await h.export(tester)).overlays, isEmpty);
    });

    testWidgets('font carousel awaits the font loader', (tester) async {
      var loaded = 0;
      final h = await pumpEditor(
        tester,
        editor: EditorOptions(
          fonts: [
            StoryFont.system,
            StoryFont(
              id: 'serif',
              label: 'Serif',
              loader: () async => loaded++,
            ),
          ],
        ),
      );
      await tester.tapAt(canvasPoint(tester, const Offset(540, 300)));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Fonts');
      await tester.tap(find.bySemanticsLabel('Serif'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(strings.common.done));
      await tester.pump();

      expect(loaded, 1);
      final text = (await h.export(tester)).overlays.single as TextOverlay;
      expect(text.style.fontId, 'serif');
    });

    testWidgets('back while typing finishes the text', (tester) async {
      final h = await pumpEditor(tester);
      await tester.tapAt(canvasPoint(tester, const Offset(540, 300)));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Typed');
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(StoryTextField), findsNothing);
      expect(h.backs, 0);
      expect((await h.export(tester)).overlays, hasLength(1));
    });
  });

  group('overlay gestures (AC8, AC10)', () {
    testWidgets('one finger moves the overlay; snapping to the centre', (
      tester,
    ) async {
      final h = await pumpEditor(
        tester,
        document: _withOverlays([_textAt(const Offset(300, 500))]),
      );
      final s = viewScaleOf(tester);
      final gesture = await tester.startGesture(
        canvasPoint(tester, const Offset(300, 500)),
      );
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final t = (await h.export(tester)).overlays.single.transform;
      expect(t.position.dx, closeTo(300 + 40 / s, 1));
      expect(t.position.dy, closeTo(500 + 60 / s, 1));

      // Drag near the vertical centre line: snaps and gives haptics.
      final snap = await tester.startGesture(canvasPoint(tester, t.position));
      await snap.moveBy(
        Offset((StoryCanvas.center.dx - t.position.dx) * s + 3, 0),
      );
      await tester.pump();
      await snap.moveBy(const Offset(1, 0));
      await tester.pump();
      await snap.up();
      await tester.pump();
      final snapped = (await h.export(tester)).overlays.single.transform;
      expect(snapped.position.dx, StoryCanvas.center.dx);
      expect(h.haptics, contains('HapticFeedbackType.selectionClick'));
    });

    testWidgets('two fingers pinch-scale and rotate, second finger anywhere', (
      tester,
    ) async {
      final h = await pumpEditor(
        tester,
        document: _withOverlays([_textAt(const Offset(540, 600))]),
      );
      final a = canvasPoint(tester, const Offset(540, 600));
      final b = canvasPoint(tester, const Offset(540, 1200));
      final first = await tester.startGesture(a, pointer: 1);
      await tester.pump();
      final second = await tester.startGesture(b, pointer: 2);
      await tester.pump();
      // Spread to twice the distance and rotate by ~25°.
      const angle = 25 * math.pi / 180;
      final mid = (a + b) / 2;
      final half = (b - a) / 2;
      Offset rotated(Offset v, double r) => Offset(
        v.dx * math.cos(r) - v.dy * math.sin(r),
        v.dx * math.sin(r) + v.dy * math.cos(r),
      );
      for (var i = 1; i <= 10; i++) {
        final f = i / 10;
        final v = rotated(half * (1 + f), angle * f);
        await first.moveTo(mid - v);
        await second.moveTo(mid + v);
        await tester.pump();
      }
      await first.up();
      await second.up();
      await tester.pump();

      // The recognizer measures from the moment it accepts (after the slop),
      // so the result is a little below the full spread and turn.
      final t = (await h.export(tester)).overlays.single.transform;
      expect(t.scale, inInclusiveRange(1.6, 2.05));
      expect(t.rotation, inInclusiveRange(angle * 0.7, angle * 1.05));
      expect(t.position.dy, closeTo(600, 40));
    });

    testWidgets(
      'two fingers around a text rotate it even when neither starts on it',
      (tester) async {
        final h = await pumpEditor(
          tester,
          document: _withOverlays([_textAt(const Offset(540, 900))]),
        );
        // Both fingers well outside the text, the text between them.
        final a = canvasPoint(tester, const Offset(140, 900));
        final b = canvasPoint(tester, const Offset(940, 900));
        final first = await tester.startGesture(a, pointer: 1);
        await tester.pump();
        final second = await tester.startGesture(b, pointer: 2);
        await tester.pump();
        const angle = 30 * math.pi / 180;
        final mid = (a + b) / 2;
        final half = (b - a) / 2;
        for (var i = 1; i <= 10; i++) {
          final r = angle * i / 10;
          final v = Offset(
            half.dx * math.cos(r) - half.dy * math.sin(r),
            half.dx * math.sin(r) + half.dy * math.cos(r),
          );
          await first.moveTo(mid - v);
          await second.moveTo(mid + v);
          await tester.pump();
        }
        await first.up();
        await second.up();
        await tester.pump();

        final doc = await h.export(tester);
        // The text turned (the pinch used to go to the media, which
        // cannot rotate).
        expect(
          doc.overlays.single.transform.rotation,
          inInclusiveRange(angle * 0.6, angle * 1.05),
        );
      },
    );

    testWidgets('dragging onto the trash deletes (with haptics)', (
      tester,
    ) async {
      final h = await pumpEditor(
        tester,
        document: _withOverlays([_textAt(StoryCanvas.center)]),
      );
      final canvasSize = tester.getSize(find.byType(TrashZone));
      final trash =
          tester.getTopLeft(find.byType(TrashZone)) +
          TrashZone.centerIn(canvasSize);
      final gesture = await tester.startGesture(
        canvasPoint(tester, StoryCanvas.center),
      );
      // Past the scale recognizer's slop (kPanSlop); it starts on the next
      // move.
      await gesture.moveBy(const Offset(0, 50));
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.bySemanticsLabel(strings.editor.dragToDelete),
        findsOneWidget,
      );
      await gesture.moveTo(trash);
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));

      expect((await h.export(tester)).overlays, isEmpty);
      expect(h.haptics, contains('HapticFeedbackType.mediumImpact'));
      // Undo brings it back (once the chrome has faded back in).
      await tester.pump(const Duration(milliseconds: 200));
      await openMoreTools(tester);
      await tester.tap(find.bySemanticsLabel(strings.editor.undo));
      await tester.pump();
      expect((await h.export(tester)).overlays, hasLength(1));
    });

    testWidgets('grabbing an overlay brings it to the front', (tester) async {
      final h = await pumpEditor(
        tester,
        document: _withOverlays([
          _textAt(const Offset(300, 500), text: 'A'),
          _textAt(const Offset(800, 1400), text: 'B'),
        ]),
      );
      final gesture = await tester.startGesture(
        canvasPoint(tester, const Offset(300, 500)),
      );
      await gesture.moveBy(const Offset(30, 30));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      final doc = await h.export(tester);
      expect((doc.overlays.last as TextOverlay).text, 'A');
    });

    testWidgets('two fingers on the media move and scale it', (tester) async {
      final h = await pumpEditor(tester);
      final a = canvasPoint(tester, const Offset(400, 900));
      final b = canvasPoint(tester, const Offset(700, 900));
      final first = await tester.startGesture(a, pointer: 1);
      final second = await tester.startGesture(b, pointer: 2);
      await tester.pump();
      for (var i = 1; i <= 5; i++) {
        await first.moveTo(a - Offset(10.0 * i, 0));
        await second.moveTo(b + Offset(10.0 * i, 0));
        await tester.pump();
      }
      await first.up();
      await second.up();
      await tester.pump();
      final placement = (await h.export(tester)).placement;
      expect(placement.scale, greaterThan(1.1));
    });
  });

  group('drawing (AC9)', () {
    testWidgets('pen and eraser strokes, undo in the drawing bar', (
      tester,
    ) async {
      final h = await pumpEditor(tester);
      await openMoreTools(tester);
      await tester.tap(find.bySemanticsLabel(strings.editor.draw));
      await tester.pump();

      Future<void> drag(double y) async {
        final g = await tester.startGesture(
          canvasPoint(tester, Offset(200, y)),
        );
        for (var i = 1; i <= 10; i++) {
          await g.moveBy(const Offset(20, 3));
          await tester.pump();
        }
        await g.up();
        await tester.pump();
      }

      await drag(600);
      await tester.tap(find.bySemanticsLabel(strings.editor.marker));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(strings.editor.colorSwatch(4)));
      await tester.pump();
      await drag(800);
      await tester.tap(find.bySemanticsLabel(strings.editor.eraser));
      await tester.pump();
      // No colours for the eraser.
      expect(
        find.bySemanticsLabel(strings.editor.colorSwatch(4)),
        findsNothing,
      );
      await drag(700);

      await tester.tap(find.bySemanticsLabel(strings.editor.undo));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(strings.editor.redo));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(strings.common.done));
      await tester.pump();

      final strokes = (await h.export(tester)).strokes;
      expect(strokes.map((s) => s.tool), [
        StrokeTool.pen,
        StrokeTool.marker,
        StrokeTool.eraser,
      ]);
      expect(strokes[1].color, EditorOptions.defaultColors[3]);
      expect(strokes.first.points.length, greaterThan(5));
      // Stored in canvas units.
      expect(strokes.first.points.first.x, closeTo(200, 2));
      expect(strokes.first.size, const EditorOptions().brushSizes[1]);
    });

    testWidgets('brush size picker changes the width', (tester) async {
      final h = await pumpEditor(tester);
      await openMoreTools(tester);
      await tester.tap(find.bySemanticsLabel(strings.editor.draw));
      await tester.pump();
      final sizes = find.bySemanticsLabel(strings.editor.brushSize);
      // Container + one per size.
      await tester.tap(sizes.last);
      await tester.pump();
      final g = await tester.startGesture(
        canvasPoint(tester, const Offset(300, 900)),
      );
      await g.moveBy(const Offset(60, 0));
      await tester.pump();
      await g.up();
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(strings.common.done));
      await tester.pump();
      final stroke = (await h.export(tester)).strokes.single;
      expect(stroke.size, const EditorOptions().brushSizes.last);
    });
  });

  group('stickers and emoji (AC10)', () {
    testWidgets('emoji and stickers are added centred', (tester) async {
      final h = await pumpEditor(
        tester,
        editor: EditorOptions(
          stickers: [
            StorySticker(
              id: 'star',
              image: MemoryImage(kTransparentPng),
              label: 'Star',
            ),
          ],
        ),
      );
      await tester.tap(find.bySemanticsLabel(strings.editor.stickers).first);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Star'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(strings.editor.stickers).first);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(strings.editor.emoji));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('🔥'));
      await tester.pump();

      final overlays = (await h.export(tester)).overlays;
      expect(overlays.first, isA<StickerOverlay>());
      expect((overlays.first as StickerOverlay).stickerId, 'star');
      expect((overlays.last as EmojiOverlay).emoji, '🔥');
      expect(overlays.last.transform.position, StoryCanvas.center);
    });

    testWidgets('the stickers tab is hidden without host stickers', (
      tester,
    ) async {
      await pumpEditor(tester);
      await tester.tap(find.bySemanticsLabel(strings.editor.stickers));
      await tester.pump();
      // Only the rail button carries the label; the panel shows emoji.
      expect(find.bySemanticsLabel(strings.editor.stickers), findsOneWidget);
      expect(find.bySemanticsLabel('😀'), findsOneWidget);
    });

    testWidgets('maxOverlays shows a notice', (tester) async {
      final h = await pumpEditor(
        tester,
        editor: const EditorOptions(maxOverlays: 1),
      );
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.bySemanticsLabel(strings.editor.stickers));
        await tester.pump();
        await tester.tap(find.bySemanticsLabel('😀'));
        await tester.pump();
      }
      expect(find.text(strings.editor.maxOverlaysReached), findsOneWidget);
      // New text is refused too.
      // The panel's close button (the top bar has one too).
      await tester.tap(find.bySemanticsLabel(strings.common.close).last);
      await tester.pump();
      await tester.tapAt(canvasPoint(tester, const Offset(540, 300)));
      await tester.pump();
      expect(find.byType(StoryTextField), findsNothing);
      expect((await h.export(tester)).overlays, hasLength(1));
      await tester.pump(const Duration(seconds: 3));
      expect(find.text(strings.editor.maxOverlaysReached), findsNothing);
    });
  });

  group('filters (AC11)', () {
    testWidgets('the strip selects a filter', (tester) async {
      final h = await pumpEditor(tester);
      await openMoreTools(tester);
      await tester.tap(find.bySemanticsLabel(strings.editor.filters).first);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Warm'));
      await tester.pump();
      // The media is drawn through the filter's matrix.
      expect(
        find.descendant(
          of: find.byType(MediaLayer),
          matching: find.byType(ColorFiltered),
        ),
        findsOneWidget,
      );
      expect((await h.export(tester)).filterId, 'warm');
      // Export closes the tool; reopen it.
      await tester.tap(find.bySemanticsLabel(strings.editor.filters).first);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Original'));
      await tester.pump();
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(MediaLayer),
          matching: find.byType(ColorFiltered),
        ),
        findsNothing,
      );
      expect((await h.export(tester)).filterId, isNull);
    });

    testWidgets('a horizontal swipe switches filters and names them', (
      tester,
    ) async {
      final h = await pumpEditor(tester);
      await tester.flingFrom(
        canvasPoint(tester, const Offset(800, 1000)),
        const Offset(-200, 0),
        1000,
      );
      await tester.pump();
      expect((await h.export(tester)).filterId, StoryFilter.defaults[1].id);
      expect(find.text(StoryFilter.defaults[1].label), findsOneWidget);

      await tester.flingFrom(
        canvasPoint(tester, const Offset(300, 1000)),
        const Offset(200, 0),
        1000,
      );
      await tester.pump();
      expect((await h.export(tester)).filterId, isNull);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(StoryFilter.defaults[1].label), findsNothing);
    });
  });

  testWidgets('edits survive switching tools (AC14)', (tester) async {
    final h = await pumpEditor(tester);
    await addText(tester, 'Keep me');
    await openMoreTools(tester);
    await tester.tap(find.bySemanticsLabel(strings.editor.draw));
    await tester.pump();
    final g = await tester.startGesture(
      canvasPoint(tester, const Offset(200, 900)),
    );
    await g.moveBy(const Offset(100, 0));
    await tester.pump();
    await g.up();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel(strings.common.done));
    await tester.pump();
    await openMoreTools(tester);
    await tester.tap(find.bySemanticsLabel(strings.editor.filters).first);
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Mono'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel(strings.editor.stickers));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('🎉'));
    await tester.pump();

    final doc = await h.export(tester);
    expect(doc.overlays, hasLength(2));
    expect((doc.overlays.first as TextOverlay).text, 'Keep me');
    expect(doc.strokes, hasLength(1));
    expect(doc.filterId, 'mono');
  });

  group('back and discard', () {
    testWidgets('clean editor leaves without asking', (tester) async {
      final h = await pumpEditor(tester);
      await tester.tap(find.bySemanticsLabel(strings.common.close));
      await tester.pump();
      expect(h.backs, 1);
    });

    testWidgets('dirty editor asks; keep editing stays, discard leaves', (
      tester,
    ) async {
      final h = await pumpEditor(tester);
      await addText(tester, 'Dirty');
      await tester.tap(find.bySemanticsLabel(strings.common.close));
      await tester.pumpAndSettle();
      expect(find.text(strings.common.discardTitle), findsOneWidget);
      await tester.tap(find.text(strings.common.keepEditing));
      await tester.pumpAndSettle();
      expect(h.backs, 0);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(strings.common.discardTitle), findsOneWidget);
      await tester.tap(find.text(strings.common.discard));
      await tester.pumpAndSettle();
      expect(h.backs, 1);
    });

    testWidgets('back closes an open tool first', (tester) async {
      final h = await pumpEditor(tester);
      await openMoreTools(tester);
      await tester.tap(find.bySemanticsLabel(strings.editor.filters).first);
      await tester.pump();
      expect(find.bySemanticsLabel('Warm'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.bySemanticsLabel('Warm'), findsNothing);
      expect(h.backs, 0);
    });

    testWidgets('no confirmation when confirmDiscard is off', (tester) async {
      final h = await pumpEditor(
        tester,
        editor: const EditorOptions(confirmDiscard: false),
      );
      await addText(tester, 'Dirty');
      await tester.tap(find.bySemanticsLabel(strings.common.close));
      await tester.pump();
      expect(h.backs, 1);
    });
  });

  testWidgets('inactive editor ignores input', (tester) async {
    final h = await pumpEditor(tester);
    h.active.value = false;
    await tester.pump();
    await tester.tapAt(canvasPoint(tester, const Offset(540, 300)));
    await tester.pump();
    expect(find.byType(StoryTextField), findsNothing);
    h.active.value = true;
    await tester.pump();
    await tester.tapAt(canvasPoint(tester, const Offset(540, 300)));
    await tester.pump();
    expect(find.byType(StoryTextField), findsOneWidget);
  });

  group('accessibility (AC22)', () {
    testWidgets('controls meet tap target and label guidelines', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpEditor(
        tester,
        document: _withOverlays([_textAt(const Offset(540, 1200))]),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await openMoreTools(tester);
      await tester.tap(find.bySemanticsLabel(strings.editor.draw));
      await tester.pump();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('overlay custom semantics actions move, resize, delete', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final h = await pumpEditor(
        tester,
        document: _withOverlays([_textAt(StoryCanvas.center)]),
      );
      final node = find.semantics.byValue('Hi');
      expect(node, findsOne);
      final data = node.evaluate().single.getSemanticsData();
      final labels = [
        for (final id in data.customSemanticsActionIds ?? <int>[])
          CustomSemanticsAction.getAction(id)!.label,
      ];
      expect(
        labels,
        containsAll([
          strings.editor.moveUp,
          strings.editor.moveDown,
          strings.editor.moveLeft,
          strings.editor.moveRight,
          strings.editor.enlarge,
          strings.editor.shrink,
          strings.editor.rotateLeft,
          strings.editor.rotateRight,
          strings.editor.bringToFront,
          strings.editor.edit,
          strings.editor.delete,
        ]),
      );

      tester.semantics.customAction(
        node,
        CustomSemanticsAction(label: strings.editor.moveRight),
      );
      await tester.pump();
      tester.semantics.customAction(
        find.semantics.byValue('Hi'),
        CustomSemanticsAction(label: strings.editor.enlarge),
      );
      await tester.pump();
      tester.semantics.customAction(
        find.semantics.byValue('Hi'),
        CustomSemanticsAction(label: strings.editor.rotateRight),
      );
      await tester.pump();
      var t = (await h.export(tester)).overlays.single.transform;
      expect(t.position.dx, greaterThan(StoryCanvas.center.dx));
      expect(t.scale, greaterThan(1));
      expect(t.rotation, greaterThan(0));

      tester.semantics.customAction(
        find.semantics.byValue('Hi'),
        CustomSemanticsAction(label: strings.editor.edit),
      );
      await tester.pump();
      expect(find.byType(StoryTextField), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(strings.common.done));
      await tester.pump();

      tester.semantics.customAction(
        find.semantics.byValue('Hi'),
        CustomSemanticsAction(label: strings.editor.delete),
      );
      await tester.pump();
      t = const OverlayTransform(position: Offset.zero);
      expect((await h.export(tester)).overlays, isEmpty);
      handle.dispose();
    });

    testWidgets('the Adjust panel does the same with buttons', (tester) async {
      final h = await pumpEditor(
        tester,
        document: _withOverlays([
          _textAt(const Offset(300, 400), text: 'A'),
          _textAt(StoryCanvas.center, text: 'B'),
        ]),
      );
      await openMoreTools(tester);
      await tester.tap(find.bySemanticsLabel(strings.editor.adjust).first);
      await tester.pump();
      // Topmost overlay is selected first.
      expect(find.text('B'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(strings.editor.moveDown));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(strings.editor.shrink));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(strings.editor.nextItem));
      await tester.pump();
      expect(find.text('A'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(strings.editor.delete));
      await tester.pump();

      final doc = await h.export(tester);
      final b = doc.overlays.single;
      expect((b as TextOverlay).text, 'B');
      expect(b.transform.position.dy, greaterThan(StoryCanvas.center.dy));
      expect(b.transform.scale, lessThan(1));
    });

    testWidgets('reduced motion: chrome and trash appear without animation', (
      tester,
    ) async {
      await pumpEditor(
        tester,
        disableAnimations: true,
        document: _withOverlays([_textAt(StoryCanvas.center)]),
      );
      final gesture = await tester.startGesture(
        canvasPoint(tester, StoryCanvas.center),
      );
      await gesture.moveBy(const Offset(0, 50));
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();
      final opacity = tester.widget<AnimatedOpacity>(
        find
            .ancestor(
              of: find.byIcon(Icons.delete_outline),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      );
      expect(opacity.duration, Duration.zero);
      expect(opacity.opacity, 1);
      await gesture.up();
      await tester.pump();
    });
  });
}
