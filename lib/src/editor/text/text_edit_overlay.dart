import 'package:flutter/material.dart';

import '../../api/assets/story_font.dart';
import '../../api/config/editor_options.dart';
import '../../core/story_scope.dart';
import '../../model/story_overlay.dart';
import '../../render/painters/story_paint_resources_loader.dart';
import '../widgets/editor_icon_button.dart';
import '../widgets/editor_panel.dart';
import 'story_text_field.dart';
import 'text_style_controls.dart';

/// Full-screen text editor: dimmed backdrop, the text in place (rendered by
/// the shared painter), font carousel and colour palette above the
/// keyboard, alignment and background toggles, and Done.
///
/// Tapping the backdrop also finishes editing.
class TextEditOverlay extends StatefulWidget {
  /// Creates the editor.
  const TextEditOverlay({
    required this.initialText,
    required this.initialStyle,
    required this.options,
    required this.viewScale,
    required this.onDone,
    required this.onFontError,
    super.key,
  });

  /// Text to start from (empty for a new overlay).
  final String initialText;

  /// Style to start from.
  final TextOverlayStyle initialStyle;

  /// Fonts and colours.
  final EditorOptions options;

  /// Screen pixels per canvas unit.
  final double viewScale;

  /// Editing finished with this text and style.
  final void Function(String text, TextOverlayStyle style) onDone;

  /// A font could not be loaded.
  final void Function(Object error, StackTrace stackTrace) onFontError;

  @override
  State<TextEditOverlay> createState() => TextEditOverlayState();
}

/// State of [TextEditOverlay]; [finish] commits the text (e.g. on back).
class TextEditOverlayState extends State<TextEditOverlay> {
  late TextOverlayStyle _style = widget.initialStyle;
  late final StoryTextEditingController _text = StoryTextEditingController(
    _font(_style.fontId),
    text: widget.initialText,
  );
  final FocusNode _focus = FocusNode(debugLabel: 'storyText');
  bool _done = false;

  StoryFont _font(String id) {
    for (final font in widget.options.fonts) {
      if (font.id == id) {
        return font;
      }
    }
    return widget.options.fonts.isEmpty
        ? StoryFont.system
        : widget.options.fonts.first;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Finishes editing with the current text and style.
  void finish() {
    if (_done) {
      return;
    }
    _done = true;
    widget.onDone(_text.text, _style);
  }

  Future<void> _selectFont(StoryFont font) async {
    try {
      await loadStoryFont(font);
    } on Object catch (e, s) {
      widget.onFontError(e, s);
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _style = _style.copyWith(fontId: font.id);
      _text.font = font;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final strings = scope.strings;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final font = _font(_style.fontId);
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: finish,
          child: ColoredBox(color: theme.scrim),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      AlignmentToggle(
                        align: _style.align,
                        onChanged: (align) => setState(
                          () => _style = _style.copyWith(align: align),
                        ),
                      ),
                      const SizedBox(width: 8),
                      BackgroundStyleToggle(
                        background: _style.background,
                        onChanged: (background) => setState(
                          () =>
                              _style = _style.copyWith(background: background),
                        ),
                      ),
                      const Spacer(),
                      EditorTextButton(
                        label: strings.common.done,
                        filled: true,
                        onPressed: finish,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: StoryTextField(
                        controller: _text,
                        focusNode: _focus,
                        style: _style,
                        font: font,
                        viewScale: widget.viewScale,
                        hint: strings.editor.typeSomething,
                        hintColor: theme.onSurfaceMuted,
                        cursorColor: theme.accent,
                      ),
                    ),
                  ),
                ),
                FontCarousel(
                  fonts: widget.options.fonts,
                  selectedId: font.id,
                  onSelected: _selectFont,
                  onLoadError: widget.onFontError,
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ColorPalette(
                    colors: widget.options.textColors,
                    selected: _style.color,
                    onSelected: (color) =>
                        setState(() => _style = _style.copyWith(color: color)),
                  ),
                ),
                SizedBox(height: keyboard > 0 ? 8 : 24),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
