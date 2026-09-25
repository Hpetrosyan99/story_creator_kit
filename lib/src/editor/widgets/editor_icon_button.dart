import 'package:flutter/material.dart';

import '../../core/story_scope.dart';

/// A round 48×48 icon button on the canvas: translucent by default, filled
/// with the accent when [filled], accent icon when [selected].
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
        child: SizedBox.square(
          dimension: size,
          child: Material(
            color: background,
            shape: CircleBorder(
              side: selected && !filled
                  ? BorderSide(color: theme.accent, width: 1.5)
                  : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: Icon(icon, color: foreground, size: 24),
            ),
          ),
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: EditorIconButton.size,
          minWidth: EditorIconButton.size,
        ),
        child: Material(
          color: filled ? theme.accent : theme.controlBackground,
          shape: StadiumBorder(
            side: selected && !filled
                ? BorderSide(color: theme.accent, width: 1.5)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
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
