import 'package:flutter/material.dart';

import '../../api/assets/story_font.dart';
import '../../model/story_overlay.dart';
import '../../render/painters/story_text_layout.dart';

/// Text controller that shows the text as the painter renders it
/// (upper-cased for display fonts) without changing the stored text.
class StoryTextEditingController extends TextEditingController {
  /// Creates a controller.
  StoryTextEditingController(this._font, {super.text});

  StoryFont _font;

  /// The font whose casing is applied.
  StoryFont get font => _font;

  set font(StoryFont value) {
    if (value == _font) {
      return;
    }
    _font = value;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    required bool withComposing,
    TextStyle? style,
  }) {
    final display = StoryTextLayout.displayText(text, _font);
    if (display == text) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    return TextSpan(style: style, text: display);
  }
}

/// The in-place text editing field.
///
/// It is laid out in canvas units at exactly the painter's wrap width
/// (`StoryTextLayout.maxTextWidth`, plus the caret margin `RenderEditable`
/// reserves) and scaled to the screen, so its line breaks equal the
/// painter's. Its own glyphs are transparent: the text and background the
/// user sees are drawn by the shared painter, so editing looks exactly like
/// the result. The field only supplies the caret, selection and IME.
class StoryTextField extends StatelessWidget {
  /// Creates the field.
  const StoryTextField({
    required this.controller,
    required this.focusNode,
    required this.style,
    required this.font,
    required this.viewScale,
    required this.hint,
    required this.hintColor,
    required this.cursorColor,
    super.key,
  });

  /// Text controller.
  final StoryTextEditingController controller;

  /// Focus of the field.
  final FocusNode focusNode;

  /// Overlay style being edited.
  final TextOverlayStyle style;

  /// Font of [style].
  final StoryFont font;

  /// Screen pixels per canvas unit.
  final double viewScale;

  /// Placeholder when empty.
  final String hint;

  /// Placeholder colour.
  final Color hintColor;

  /// Caret colour.
  final Color cursorColor;

  /// `RenderEditable`'s caret gap (`_kCaretGap`).
  static const double caretGap = 1;

  /// Caret width in canvas units (about 2 screen pixels).
  static double cursorWidthFor(double viewScale) => 2 / viewScale;

  /// Width reserved by `RenderEditable` for the caret, canvas units.
  static double caretMarginFor(double viewScale) =>
      caretGap + cursorWidthFor(viewScale);

  /// Width of the field in canvas units: text wraps at exactly
  /// `StoryTextLayout.maxTextWidth`.
  static double fieldWidthFor(double viewScale) =>
      StoryTextLayout.maxTextWidth + caretMarginFor(viewScale);

  /// Horizontal alignment factor of [align] (0 left, 0.5 centre, 1 right).
  static double alignFactor(TextAlign align) => switch (align) {
    TextAlign.center => 0.5,
    TextAlign.right || TextAlign.end => 1,
    TextAlign.left || TextAlign.start || TextAlign.justify => 0,
  };

  @override
  Widget build(BuildContext context) {
    final width = fieldWidthFor(viewScale);
    final glyphs = StoryTextLayout.textStyle(style, font);
    return SizedBox(
      width: width * viewScale,
      child: FittedBox(
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          child: MediaQuery.withNoTextScaling(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, field) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _EditingTextPainter(
                          text: controller.text,
                          style: style,
                          font: font,
                        ),
                      ),
                    ),
                    if (controller.text.isEmpty)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                            child: Text(
                              hint,
                              textAlign: style.align,
                              strutStyle: StoryTextLayout.strutStyle(
                                style,
                                font,
                              ),
                              style: glyphs.copyWith(color: hintColor),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.visible,
                            ),
                          ),
                        ),
                      ),
                    field!,
                  ],
                ),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  decoration: null,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  textAlign: style.align,
                  style: glyphs.copyWith(color: const Color(0x00000000)),
                  strutStyle: StoryTextLayout.strutStyle(style, font),
                  cursorColor: cursorColor,
                  cursorWidth: cursorWidthFor(viewScale),
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                  scrollPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditingTextPainter extends CustomPainter {
  const _EditingTextPainter({
    required this.text,
    required this.style,
    required this.font,
  });

  final String text;
  final TextOverlayStyle style;
  final StoryFont font;

  @override
  void paint(Canvas canvas, Size size) {
    if (text.isEmpty) {
      return;
    }
    final layout = StoryTextLayout.forText(text, style, font);
    // The field aligns lines within the full wrap width; the painter within
    // the longest line. Shift so both coincide.
    final dx =
        (StoryTextLayout.maxTextWidth - layout.textWidth) *
        StoryTextField.alignFactor(style.align);
    layout.paint(canvas, Offset(dx, 0) - layout.textOffset);
  }

  @override
  bool shouldRepaint(_EditingTextPainter oldDelegate) =>
      oldDelegate.text != text ||
      oldDelegate.style != style ||
      oldDelegate.font != font;
}
