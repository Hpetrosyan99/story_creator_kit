import 'package:flutter/material.dart';

import '../../core/story_scope.dart';
import '../../model/drawing_stroke.dart';
import '../widgets/editor_icon_button.dart';
import '../widgets/editor_panel.dart';
import 'drawing_brush.dart';

/// Top row of the drawing tool: undo, redo and Done.
class DrawingTopBar extends StatelessWidget {
  /// Creates the bar.
  const DrawingTopBar({
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    required this.onDone,
    super.key,
  });

  /// Whether undo is possible.
  final bool canUndo;

  /// Whether redo is possible.
  final bool canRedo;

  /// Undo tapped.
  final VoidCallback onUndo;

  /// Redo tapped.
  final VoidCallback onRedo;

  /// Done tapped.
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final strings = StoryScope.of(context).strings;
    return Row(
      children: [
        EditorIconButton(
          icon: Icons.undo,
          label: strings.editor.undo,
          onPressed: canUndo ? onUndo : null,
        ),
        const SizedBox(width: 8),
        EditorIconButton(
          icon: Icons.redo,
          label: strings.editor.redo,
          onPressed: canRedo ? onRedo : null,
        ),
        const Spacer(),
        EditorTextButton(
          label: strings.common.done,
          filled: true,
          onPressed: onDone,
        ),
      ],
    );
  }
}

/// Bottom panel of the drawing tool: brush kinds, sizes and colours.
class DrawingToolbar extends StatelessWidget {
  /// Creates the toolbar.
  const DrawingToolbar({
    required this.brush,
    required this.sizes,
    required this.colors,
    required this.onChanged,
    super.key,
  });

  /// Current brush.
  final DrawingBrush brush;

  /// Brush widths in canvas units.
  final List<double> sizes;

  /// Colour palette.
  final List<Color> colors;

  /// The brush changed.
  final ValueChanged<DrawingBrush> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = StoryScope.of(context).strings.editor;
    final tools = [
      (StrokeTool.pen, Icons.draw, strings.pen),
      (StrokeTool.marker, Icons.border_color, strings.marker),
      (StrokeTool.neon, Icons.auto_awesome, strings.neon),
      (StrokeTool.eraser, Icons.auto_fix_normal, strings.eraser),
    ];
    return EditorPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final (tool, icon, label) in tools)
                EditorIconButton(
                  icon: icon,
                  label: label,
                  selected: brush.tool == tool,
                  onPressed: () => onChanged(brush.copyWith(tool: tool)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          BrushSizePicker(
            sizes: sizes,
            selected: brush.size,
            onSelected: (size) => onChanged(brush.copyWith(size: size)),
          ),
          if (brush.tool != StrokeTool.eraser) ...[
            const SizedBox(height: 8),
            ColorPalette(
              colors: colors,
              selected: brush.color,
              onSelected: (color) => onChanged(brush.copyWith(color: color)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Row of brush widths, each drawn as a dot of relative size.
class BrushSizePicker extends StatelessWidget {
  /// Creates the picker.
  const BrushSizePicker({
    required this.sizes,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  /// Widths in canvas units.
  final List<double> sizes;

  /// Current width.
  final double selected;

  /// A width was chosen.
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final label = scope.strings.editor.brushSize;
    final largest = sizes.fold<double>(1, (a, b) => a > b ? a : b);
    return Semantics(
      container: true,
      label: label,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final size in sizes)
            Semantics(
              button: true,
              selected: size == selected,
              label: label,
              value: size.round().toString(),
              excludeSemantics: true,
              onTap: () => onSelected(size),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(size),
                child: SizedBox.square(
                  dimension: 48,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: size == selected
                            ? theme.accent
                            : theme.onSurface,
                      ),
                      child: SizedBox.square(
                        dimension: 6 + 22 * (size / largest),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
