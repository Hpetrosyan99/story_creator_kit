import 'package:flutter/material.dart';

import '../../api/theme/story_creator_theme.dart';

/// Export failure: message, Retry (accent) and Back.
class ExportFailureView extends StatelessWidget {
  /// Creates the view.
  const ExportFailureView({
    required this.message,
    required this.retryLabel,
    required this.backLabel,
    required this.theme,
    required this.onRetry,
    required this.onBack,
    super.key,
  });

  /// What went wrong, for the user.
  final String message;

  /// Retry button label.
  final String retryLabel;

  /// Back button label.
  final String backLabel;

  /// Colours and text styles.
  final StoryCreatorTheme theme;

  /// Starts the export again.
  final VoidCallback onRetry;

  /// Returns to the editor.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline_rounded, color: theme.error, size: 48),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(
            message,
            style: theme.bodyStyle,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: onBack,
              style: TextButton.styleFrom(
                minimumSize: const Size(112, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(theme.chipRadius),
                  side: BorderSide(color: theme.outline),
                ),
              ),
              child: Text(backLabel, style: theme.labelStyle),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                minimumSize: const Size(112, 48),
                backgroundColor: theme.accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(theme.chipRadius),
                ),
              ),
              child: Text(
                retryLabel,
                style: theme.labelStyle.copyWith(color: theme.onAccent),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
