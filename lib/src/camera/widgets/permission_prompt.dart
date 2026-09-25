import 'package:flutter/widgets.dart';

import '../../core/story_scope.dart';

/// An accent pill button (≥ 48 px high).
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
    return Semantics(
      button: true,
      enabled: onPressed != null,
      excludeSemantics: true,
      label: label,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 120),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: primary ? theme.accent : null,
              border: primary ? null : Border.all(color: theme.outline),
              borderRadius: BorderRadius.circular(theme.chipRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.labelStyle.copyWith(
                    fontSize: 14,
                    color: primary ? theme.onAccent : theme.onSurface,
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
            Icon(icon, size: 48, color: theme.onSurfaceMuted),
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
              style: theme.bodyStyle.copyWith(color: theme.onSurfaceMuted),
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
