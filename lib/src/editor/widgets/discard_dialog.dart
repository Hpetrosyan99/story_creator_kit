import 'package:flutter/material.dart';

import '../../api/strings/common_strings.dart';
import '../../api/theme/story_creator_theme.dart';
import 'editor_icon_button.dart';

/// Asks whether to discard the edits. Pops `true` to discard.
///
/// Built outside the creator's `StoryScope` (dialogs live on the root
/// navigator), so theme and strings are passed in.
class DiscardDialog extends StatelessWidget {
  /// Creates the dialog.
  const DiscardDialog({required this.theme, required this.strings, super.key});

  /// Colours and text styles.
  final StoryCreatorTheme theme;

  /// Labels.
  final CommonStrings strings;

  /// Shows the dialog; completes with `true` when the user discards.
  static Future<bool> show(
    BuildContext context, {
    required StoryCreatorTheme theme,
    required CommonStrings strings,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: theme.scrim,
      builder: (context) => DiscardDialog(theme: theme, strings: strings),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: theme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(theme.cornerRadius),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(strings.discardTitle, style: theme.titleStyle),
          ),
          const SizedBox(height: 8),
          Text(
            strings.discardMessage,
            style: theme.bodyStyle.copyWith(color: theme.onSurfaceMuted),
          ),
          const SizedBox(height: 20),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: 8,
            children: [
              _DialogButton(
                label: strings.keepEditing,
                color: theme.onSurface,
                style: theme.labelStyle,
                onPressed: () => Navigator.of(context).pop(false),
              ),
              _DialogButton(
                label: strings.discard,
                color: theme.error,
                style: theme.labelStyle,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.color,
    required this.style,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final TextStyle style;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: onPressed,
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: EditorIconButton.size,
          minWidth: EditorIconButton.size,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(
            widthFactor: 1,
            child: Text(label, style: style.copyWith(color: color)),
          ),
        ),
      ),
    ),
  );
}
