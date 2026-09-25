import 'package:flutter/material.dart';

import '../../api/music/music_models.dart';
import '../../core/story_scope.dart';

/// Horizontal row of category chips.
///
/// The selected chip is outlined in the accent colour. When it is not the
/// first category it also shows a small ✕, and tapping it goes back to the
/// first category.
class CategoryChips extends StatelessWidget {
  /// Creates the row.
  const CategoryChips({
    required this.categories,
    required this.selected,
    required this.onSelected,
    required this.onCleared,
    super.key,
  });

  /// Categories in display order.
  final List<MusicCategory> categories;

  /// The selected category.
  final MusicCategory selected;

  /// Called with a newly tapped category.
  final ValueChanged<MusicCategory> onSelected;

  /// Called when the selected (non-first) chip is tapped.
  final VoidCallback onCleared;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: categories.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final category = categories[index];
        final isSelected = category == selected;
        final clearable = isSelected && index != 0;
        return _CategoryChip(
          key: ValueKey('music-category-${category.id}'),
          category: category,
          selected: isSelected,
          clearable: clearable,
          onTap: clearable
              ? onCleared
              : isSelected
              ? null
              : () => onSelected(category),
        );
      },
    ),
  );
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.clearable,
    required this.onTap,
    super.key,
  });

  final MusicCategory category;
  final bool selected;
  final bool clearable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final radius = BorderRadius.circular(theme.chipRadius);
    return Semantics(
      button: true,
      selected: selected,
      hint: clearable ? scope.strings.music.clearCategory : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 34,
            constraints: const BoxConstraints(minWidth: 48),
            alignment: Alignment.center,
            padding: EdgeInsets.only(left: 14, right: clearable ? 8 : 14),
            decoration: BoxDecoration(
              color: selected ? null : theme.surfaceVariant,
              borderRadius: radius,
              border: Border.all(
                color: selected ? theme.accent : theme.surfaceVariant,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(category.label, style: theme.labelStyle),
                if (clearable) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.close, size: 14, color: theme.onSurface),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
