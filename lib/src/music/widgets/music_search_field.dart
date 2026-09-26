import 'package:flutter/material.dart';

import '../../core/story_scope.dart';
import '../../ui/story_icon.dart';

/// The design's search field: 52 px high, 1 px outline, fully rounded, an
/// accent magnifier and a clear button once text is entered.
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

  /// Field height.
  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final strings = scope.strings.music;
    return Container(
      height: height,
      padding: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: theme.outline),
      ),
      child: Row(
        spacing: 8,
        children: [
          StoryIcon(StoryIcons.search, color: theme.accent),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              textInputAction: TextInputAction.search,
              style: theme.bodyLargeStyle,
              cursorColor: theme.accent,
              decoration: InputDecoration(
                isDense: true,
                // 22 px line + 26 = a 48 px tap target inside the 52 px pill.
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
                border: InputBorder.none,
                hintText: strings.searchHint,
                hintStyle: theme.bodyLargeStyle.copyWith(
                  color: theme.onSurfaceMuted,
                ),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                // With the 8 px gap: the design's 12 px right padding.
                ? const SizedBox(width: 4)
                : Semantics(
                    button: true,
                    label: strings.clearSearch,
                    excludeSemantics: true,
                    onTap: _clear,
                    child: GestureDetector(
                      key: const ValueKey('music-search-clear'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _clear,
                      child: SizedBox.square(
                        dimension: 48,
                        child: Center(
                          child: StoryIcon(
                            StoryIcons.close,
                            color: theme.onSurfaceMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _clear() {
    controller.clear();
    onCleared();
  }
}
