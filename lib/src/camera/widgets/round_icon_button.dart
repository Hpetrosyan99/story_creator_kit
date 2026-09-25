import 'package:flutter/widgets.dart';

import '../../core/story_scope.dart';

/// A 48 px round, translucent icon button used over the camera and canvas.
class RoundIconButton extends StatelessWidget {
  /// Creates the button.
  const RoundIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 48,
    this.iconSize = 24,
    this.background = true,
    this.selected = false,
    super.key,
  });

  /// The icon.
  final IconData icon;

  /// Semantics label.
  final String label;

  /// Tap handler; `null` disables the button.
  final VoidCallback? onPressed;

  /// Diameter (at least 48 for accessibility).
  final double size;

  /// Icon size.
  final double iconSize;

  /// Whether to draw the translucent circle.
  final bool background;

  /// Semantics toggled state, for toggles.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox.square(
          dimension: size < 48 ? 48 : size,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: background ? theme.controlBackground : null,
              ),
              child: SizedBox.square(
                dimension: size,
                child: Icon(
                  icon,
                  size: iconSize,
                  color: enabled
                      ? theme.onSurface
                      : theme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
