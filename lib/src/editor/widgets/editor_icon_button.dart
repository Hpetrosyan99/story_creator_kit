import 'package:flutter/material.dart';

import '../../core/story_scope.dart';
import '../../ui/story_surface.dart';

/// A round 48×48 icon button on the canvas: translucent (a [StorySurface])
/// by default, filled with the accent when [filled], accent icon and ring
/// when [selected].
class EditorIconButton extends StatelessWidget {
  /// Creates the button.
  const EditorIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.filled = false,
    this.toggled,
    super.key,
  });

  /// Icon.
  final IconData icon;

  /// Semantics label (and tooltip-less accessible name).
  final String label;

  /// Tap handler; `null` disables the button.
  final VoidCallback? onPressed;

  /// Highlights the button as the active choice.
  final bool selected;

  /// Accent background (primary action).
  final bool filled;

  /// Toggle state exposed to accessibility, if the button is a toggle.
  final bool? toggled;

  /// Diameter (and minimum tap target).
  static const double size = 48;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    final enabled = onPressed != null;
    final background = filled ? theme.accent : theme.controlBackground;
    final foreground = filled
        ? theme.onAccent
        : (selected ? theme.accent : theme.onSurface);
    final glyph = Icon(icon, color: foreground, size: 24);
    final ring = selected && !filled
        ? Border.all(color: theme.accent, width: 1.5)
        : null;
    final face = filled
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
            ),
            child: Center(child: glyph),
          )
        : StorySurface(
            fill: background,
            radius: size / 2,
            child: DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, border: ring),
              child: Center(child: glyph),
            ),
          );
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      toggled: toggled,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox.square(dimension: size, child: face),
        ),
      ),
    );
  }
}

/// A pill-shaped text button used in panels (e.g. Done).
class EditorTextButton extends StatelessWidget {
  /// Creates the button.
  const EditorTextButton({
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.selected = false,
    super.key,
  });

  /// Text (also the semantics label).
  final String label;

  /// Tap handler; `null` disables the button.
  final VoidCallback? onPressed;

  /// Accent background.
  final bool filled;

  /// Highlights the button as the active choice.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    final foreground = filled
        ? theme.onAccent
        : (selected ? theme.accent : theme.onSurface);
    return Semantics(
      button: true,
      selected: selected,
      enabled: onPressed != null,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: EditorIconButton.size,
            minWidth: EditorIconButton.size,
          ),
          child: _PillFace(
            filled: filled,
            selected: selected,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: theme.labelStyle.copyWith(color: foreground),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PillFace extends StatelessWidget {
  const _PillFace({
    required this.filled,
    required this.selected,
    required this.child,
  });

  final bool filled;
  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    const radius = EditorIconButton.size / 2;
    if (filled) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: theme.accent,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: child,
      );
    }
    return StorySurface(
      fill: theme.controlBackground,
      radius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: selected ? Border.all(color: theme.accent, width: 1.5) : null,
        ),
        child: child,
      ),
    );
  }
}
