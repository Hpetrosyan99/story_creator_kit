import 'package:flutter/widgets.dart';

import '../../api/music/music_models.dart';
import '../../core/story_scope.dart';
import '../../ui/story_icon.dart';

/// Horizontal row of category chips (28 px high, in a 48 px tap row).
///
/// The selected chip has a 10 % accent fill, an accent border and a ✕;
/// tapping it calls [onCleared] (empty the search, back to the first
/// category). The others have the raised surface colour and an outline.
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

  /// Called when the selected chip is tapped.
  final VoidCallback onCleared;

  /// Height of the row (the tap target).
  static const double rowHeight = 48;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: rowHeight,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: categories.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final category = categories[index];
        final isSelected = category == selected;
        return _CategoryChip(
          key: ValueKey('music-category-${category.id}'),
          category: category,
          selected: isSelected,
          onTap: isSelected ? onCleared : () => onSelected(category),
        );
      },
    ),
  );
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
    super.key,
  });

  static const double _height = 28;

  final MusicCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    return Semantics(
      button: true,
      selected: selected,
      label: category.label,
      hint: selected ? scope.strings.music.clearCategory : null,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48),
          child: Center(
            child: Container(
              height: _height,
              alignment: Alignment.center,
              padding: EdgeInsets.only(left: 12, right: selected ? 6 : 12),
              decoration: BoxDecoration(
                color: selected
                    ? theme.accent.withValues(alpha: 0.1)
                    : theme.surfaceVariant,
                borderRadius: BorderRadius.circular(_height / 2),
                border: Border.all(
                  color: selected ? theme.accent : theme.outline,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 10,
                children: [
                  Text(category.label, style: theme.labelStyle),
                  if (selected)
                    StoryIcon(StoryIcons.chipClose, color: theme.accent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
