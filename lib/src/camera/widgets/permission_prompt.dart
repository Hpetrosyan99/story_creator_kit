import 'package:flutter/material.dart';

import '../../core/story_scope.dart';

/// A pill button (≥ 48 px high): accent-filled, or outlined when not
/// [primary].
class StoryActionButton extends StatelessWidget {
  /// Creates the button.
  const StoryActionButton({
    required this.label,
    required this.onPressed,
    this.primary = true,
    super.key,
  });

  /// Button text (also its semantics label).
  final String label;

  /// Tap handler.
  final VoidCallback? onPressed;

  /// Accent fill when `true`, outlined otherwise.
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      excludeSemantics: true,
      label: label,
      onTap: onPressed,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 96),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: primary ? theme.accent : theme.surfaceVariant,
                border: primary ? null : Border.all(color: theme.outline),
                borderRadius: BorderRadius.circular(theme.chipRadius),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: theme.bodyEmphasisStyle.copyWith(
                      color: primary ? theme.onAccent : theme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The round illustration above a prompt's title: [icon] on a raised
/// surface circle.
class PromptBadge extends StatelessWidget {
  /// Creates the badge.
  const PromptBadge({required this.icon, super.key});

  /// Icon.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 64,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.surfaceVariant,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 28, color: theme.onSurfaceSecondary),
        ),
      ),
    );
  }
}

/// Explains a missing permission (or another blocking state) and offers
/// actions.
class PermissionPrompt extends StatelessWidget {
  /// Creates the prompt.
  const PermissionPrompt({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    super.key,
  });

  /// Illustration icon.
  final IconData icon;

  /// Title.
  final String title;

  /// Explanation.
  final String message;

  /// Primary action label.
  final String actionLabel;

  /// Primary action.
  final VoidCallback? onAction;

  /// Optional secondary action label.
  final String? secondaryLabel;

  /// Optional secondary action.
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    final secondary = secondaryLabel;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PromptBadge(icon: icon),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: theme.titleStyle,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.bodyStyle.copyWith(color: theme.onSurfaceSecondary),
            ),
            const SizedBox(height: 20),
            StoryActionButton(label: actionLabel, onPressed: onAction),
            if (secondary != null) ...[
              const SizedBox(height: 12),
              StoryActionButton(
                label: secondary,
                onPressed: onSecondary,
                primary: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
