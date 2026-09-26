import 'package:flutter/widgets.dart';

import '../../core/story_scope.dart';

/// Centred message of the empty, error and offline states, with an optional
/// retry pill.
class MusicListMessage extends StatelessWidget {
  /// Creates the message.
  const MusicListMessage({required this.message, this.onRetry, super.key});

  /// Text to show.
  final String message;

  /// Shows a retry pill when set.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final onRetry = this.onRetry;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.bodyStyle.copyWith(color: theme.onSurfaceMuted),
            ),
            if (onRetry != null) MusicRetryPill(onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

/// A "Try again" pill in the style of an unselected category chip, in a
/// 48 px tap target.
class MusicRetryPill extends StatelessWidget {
  /// Creates the pill.
  const MusicRetryPill({required this.onPressed, super.key});

  /// Called on tap.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final label = scope.strings.common.retry;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 88, minHeight: 48),
          child: Center(
            widthFactor: 1,
            child: Container(
              height: 28,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: theme.surfaceVariant,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.outline),
              ),
              child: Text(label, style: theme.labelStyle),
            ),
          ),
        ),
      ),
    );
  }
}
