import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/story_scope.dart';

/// Container for a tool's controls at the bottom of the canvas: the
/// design's `surface` sheet with 20 px top corners.
class EditorPanel extends StatelessWidget {
  /// Creates a panel.
  const EditorPanel({required this.child, this.padding, super.key});

  /// Panel content.
  final Widget child;

  /// Inner padding.
  final EdgeInsetsGeometry? padding;

  /// Top corner radius (the design's radius xl).
  static const double radius = 20;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(radius)),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: child,
      ),
    );
  }
}

/// A row of colour swatches (48×48 targets).
class ColorPalette extends StatelessWidget {
  /// Creates a palette.
  const ColorPalette({
    required this.colors,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  /// Colours offered.
  final List<Color> colors;

  /// Current colour.
  final Color selected;

  /// A colour was picked.
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final strings = scope.strings.editor;
    return Semantics(
      label: strings.color,
      container: true,
      child: SizedBox(
        height: 48,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: colors.length,
          itemBuilder: (context, index) {
            final color = colors[index];
            final isSelected = color == selected;
            return Semantics(
              button: true,
              selected: isSelected,
              label: strings.colorSwatch(index + 1),
              excludeSemantics: true,
              onTap: () => onSelected(color),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(color),
                child: SizedBox.square(
                  dimension: 48,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? theme.accent : theme.onSurface,
                          width: isSelected ? 3 : 1.5,
                        ),
                      ),
                      child: const SizedBox.square(dimension: 28),
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

/// A short message over the canvas (e.g. overlay limit reached).
class EditorNotice extends StatelessWidget {
  /// Creates the notice.
  const EditorNotice({required this.message, super.key});

  /// Current message; nothing is shown when `null`.
  final ValueListenable<String?> message;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    return ValueListenableBuilder<String?>(
      valueListenable: message,
      builder: (context, text, _) {
        if (text == null) {
          return const SizedBox.shrink();
        }
        return Semantics(
          liveRegion: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(theme.chipRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                text,
                style: theme.bodyStyle,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
    );
  }
}
