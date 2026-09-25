import 'package:flutter/material.dart';

import '../../core/story_scope.dart';

/// Centered message of the empty, error and offline states, with an optional
/// retry button.
class MusicListMessage extends StatelessWidget {
  /// Creates the message.
  const MusicListMessage({
    required this.message,
    this.icon,
    this.onRetry,
    super.key,
  });

  /// Text to show.
  final String message;

  /// Icon above the text.
  final IconData? icon;

  /// Shows a retry button when set.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final icon = this.icon;
    final onRetry = this.onRetry;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: theme.onSurfaceMuted, size: 36),
              const SizedBox(height: 12),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.bodyStyle.copyWith(color: theme.onSurfaceMuted),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: theme.accent,
                  minimumSize: const Size(88, 48),
                ),
                child: Text(
                  scope.strings.common.retry,
                  style: theme.labelStyle.copyWith(color: theme.accent),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
