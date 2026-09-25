import 'package:flutter/material.dart';

import '../../core/story_scope.dart';

/// Pill-shaped search field with an accent search icon and a clear button.
class MusicSearchField extends StatelessWidget {
  /// Creates the field.
  const MusicSearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onCleared,
    super.key,
  });

  /// Text of the field.
  final TextEditingController controller;

  /// Called on every edit.
  final ValueChanged<String> onChanged;

  /// Called when the keyboard's search action is pressed.
  final ValueChanged<String> onSubmitted;

  /// Called after the clear button emptied the field.
  final VoidCallback onCleared;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final strings = scope.strings.music;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(theme.chipRadius),
      borderSide: BorderSide.none,
    );
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      style: theme.bodyStyle,
      cursorColor: theme.accent,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: theme.surfaceVariant,
        hintText: strings.searchHint,
        hintStyle: theme.bodyStyle.copyWith(color: theme.onSurfaceMuted),
        prefixIcon: Icon(Icons.search, color: theme.accent, size: 22),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: strings.clearSearch,
                  icon: Icon(
                    Icons.close,
                    color: theme.onSurfaceMuted,
                    size: 20,
                  ),
                  onPressed: () {
                    controller.clear();
                    onCleared();
                  },
                ),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: border,
        enabledBorder: border,
        focusedBorder: border,
      ),
    );
  }
}
