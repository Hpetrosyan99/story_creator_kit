import 'package:flutter/material.dart';

import '../../api/assets/story_font.dart';
import '../../core/story_scope.dart';
import '../../model/story_overlay.dart';
import '../../render/painters/story_paint_resources_loader.dart';
import '../widgets/editor_icon_button.dart';

/// Horizontal list of fonts, each label rendered in its own face once the
/// font's loader has finished.
class FontCarousel extends StatefulWidget {
  /// Creates the carousel.
  const FontCarousel({
    required this.fonts,
    required this.selectedId,
    required this.onSelected,
    required this.onLoadError,
    super.key,
  });

  /// Fonts offered.
  final List<StoryFont> fonts;

  /// Current font id.
  final String selectedId;

  /// A font was chosen.
  final ValueChanged<StoryFont> onSelected;

  /// A font loader failed.
  final void Function(Object error, StackTrace stackTrace) onLoadError;

  @override
  State<FontCarousel> createState() => _FontCarouselState();
}

class _FontCarouselState extends State<FontCarousel> {
  @override
  void initState() {
    super.initState();
    for (final font in widget.fonts) {
      if (isStoryFontReady(font)) {
        continue;
      }
      loadStoryFont(font).then(
        (_) {
          if (mounted) {
            setState(() {});
          }
        },
        onError: (Object e, StackTrace s) {
          if (mounted) {
            widget.onLoadError(e, s);
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    return Semantics(
      container: true,
      label: scope.strings.editor.font,
      child: SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: widget.fonts.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final font = widget.fonts[index];
            final selected = font.id == widget.selectedId;
            final ready = isStoryFontReady(font);
            return Semantics(
              button: true,
              selected: selected,
              label: font.label,
              excludeSemantics: true,
              onTap: () => widget.onSelected(font),
              child: Material(
                color: selected ? theme.onSurface : theme.controlBackground,
                shape: StadiumBorder(side: BorderSide(color: theme.onSurface)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => widget.onSelected(font),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          font.uppercase
                              ? font.label.toUpperCase()
                              : font.label,
                          style: theme.bodyStyle.copyWith(
                            color: selected
                                ? theme.background
                                : theme.onSurface,
                            fontFamily: ready ? font.family : null,
                            package: ready ? font.package : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Cycles left → centre → right.
class AlignmentToggle extends StatelessWidget {
  /// Creates the toggle.
  const AlignmentToggle({
    required this.align,
    required this.onChanged,
    super.key,
  });

  /// Current alignment.
  final TextAlign align;

  /// New alignment.
  final ValueChanged<TextAlign> onChanged;

  /// Next alignment in the cycle.
  static TextAlign next(TextAlign align) => switch (align) {
    TextAlign.left || TextAlign.start => TextAlign.center,
    TextAlign.center || TextAlign.justify => TextAlign.right,
    TextAlign.right || TextAlign.end => TextAlign.left,
  };

  @override
  Widget build(BuildContext context) {
    final strings = StoryScope.of(context).strings.editor;
    final (icon, label) = switch (align) {
      TextAlign.left ||
      TextAlign.start => (Icons.format_align_left, strings.alignLeft),
      TextAlign.center ||
      TextAlign.justify => (Icons.format_align_center, strings.alignCenter),
      TextAlign.right ||
      TextAlign.end => (Icons.format_align_right, strings.alignRight),
    };
    return EditorIconButton(
      icon: icon,
      label: label,
      onPressed: () => onChanged(next(align)),
    );
  }
}

/// Cycles none → solid → translucent → highlight.
class BackgroundStyleToggle extends StatelessWidget {
  /// Creates the toggle.
  const BackgroundStyleToggle({
    required this.background,
    required this.onChanged,
    super.key,
  });

  /// Current style.
  final TextBackgroundStyle background;

  /// New style.
  final ValueChanged<TextBackgroundStyle> onChanged;

  /// Next style in the cycle.
  static TextBackgroundStyle next(TextBackgroundStyle style) =>
      TextBackgroundStyle.values[(style.index + 1) %
          TextBackgroundStyle.values.length];

  @override
  Widget build(BuildContext context) {
    final strings = StoryScope.of(context).strings.editor;
    final (icon, label) = switch (background) {
      TextBackgroundStyle.none => (
        Icons.format_color_text,
        strings.backgroundNone,
      ),
      TextBackgroundStyle.solid => (
        Icons.format_color_fill,
        strings.backgroundSolid,
      ),
      TextBackgroundStyle.translucent => (
        Icons.opacity,
        strings.backgroundTranslucent,
      ),
      TextBackgroundStyle.highlight => (
        Icons.highlight,
        strings.backgroundHighlight,
      ),
    };
    return EditorIconButton(
      icon: icon,
      label: label,
      selected: background != TextBackgroundStyle.none,
      onPressed: () => onChanged(next(background)),
    );
  }
}
