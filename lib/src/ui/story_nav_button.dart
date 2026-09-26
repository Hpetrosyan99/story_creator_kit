import 'package:flutter/material.dart';

import '../core/story_scope.dart';
import 'story_icon.dart';
import 'story_surface.dart';

/// Background of a [StoryNavButton].
enum StoryNavButtonStyle {
  /// Translucent dark circle (close, back).
  translucent,

  /// Lighter translucent circle (secondary confirm).
  subtle,

  /// Accent-filled circle (primary confirm).
  accent,
}

/// A 44 px round button with a 20 px icon, as in the design's nav bar.
///
/// The tap target is 48 px. A `null` [onPressed] disables it.
class StoryNavButton extends StatelessWidget {
  /// Creates a nav button.
  const StoryNavButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.style = StoryNavButtonStyle.translucent,
    super.key,
  });

  /// Icon.
  final StoryIcons icon;

  /// Semantics label.
  final String label;

  /// Tap handler.
  final VoidCallback? onPressed;

  /// Background style.
  final StoryNavButtonStyle style;

  /// Visual diameter.
  static const double size = 44;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    final enabled = onPressed != null;
    final circle = switch (style) {
      StoryNavButtonStyle.accent => DecoratedBox(
        decoration: BoxDecoration(color: theme.accent, shape: BoxShape.circle),
        child: Center(child: StoryIcon(icon, color: theme.onAccent)),
      ),
      StoryNavButtonStyle.translucent ||
      StoryNavButtonStyle.subtle => StorySurface(
        fill: style == StoryNavButtonStyle.subtle
            ? theme.controlBackground.withValues(
                alpha: theme.controlBackground.a / 2,
              )
            : theme.controlBackground,
        radius: size / 2,
        child: Center(child: StoryIcon(icon, color: theme.onSurface)),
      ),
    };
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 48,
            child: Center(
              child: SizedBox.square(dimension: size, child: circle),
            ),
          ),
        ),
      ),
    );
  }
}
