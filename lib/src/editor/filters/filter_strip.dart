import 'package:flutter/material.dart';

import '../../api/assets/story_filter.dart';
import '../../core/story_scope.dart';
import '../widgets/editor_panel.dart';

/// Named filters, each with a small preview of the media through it.
class FilterStrip extends StatelessWidget {
  /// Creates the strip.
  const FilterStrip({
    required this.filters,
    required this.selectedIndex,
    required this.preview,
    required this.onSelected,
    super.key,
  });

  /// Filters offered.
  final List<StoryFilter> filters;

  /// Index of the current filter.
  final int selectedIndex;

  /// Small image of the media (photo or first video frame), if available.
  final ImageProvider? preview;

  /// A filter was chosen.
  final ValueChanged<StoryFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    return EditorPanel(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Semantics(
        container: true,
        label: scope.strings.editor.filters,
        child: SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: filters.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) => _FilterTile(
              filter: filters[index],
              selected: index == selectedIndex,
              preview: preview,
              onTap: onSelected,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterTile extends StatelessWidget {
  const _FilterTile({
    required this.filter,
    required this.selected,
    required this.preview,
    required this.onTap,
  });

  final StoryFilter filter;
  final bool selected;
  final ImageProvider? preview;
  final ValueChanged<StoryFilter> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    final image = preview;
    var thumb = image == null
        ? ColoredBox(color: theme.surfaceVariant)
        : Image(
            image: image,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) =>
                ColoredBox(color: theme.surfaceVariant),
          );
    if (!filter.isIdentity) {
      thumb = ColorFiltered(
        colorFilter: ColorFilter.matrix(filter.matrix),
        child: thumb,
      );
    }
    return Semantics(
      button: true,
      selected: selected,
      label: filter.label,
      excludeSemantics: true,
      onTap: () => onTap(filter),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(filter),
        child: SizedBox(
          width: 60,
          child: Column(
            children: [
              DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(theme.cornerRadius),
                  border: Border.all(
                    color: selected ? theme.accent : theme.outline,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(theme.cornerRadius),
                  child: SizedBox(width: 60, height: 68, child: thumb),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                filter.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.captionStyle.copyWith(
                  color: selected ? theme.accent : theme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The filter name shown briefly after a swipe.
class FilterNameLabel extends StatelessWidget {
  /// Creates the label.
  const FilterNameLabel({required this.label, super.key});

  /// The name, or `null` to hide.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final text = label;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: text == null ? 0 : 1,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        child: text == null
            ? const SizedBox.shrink()
            : Semantics(
                liveRegion: true,
                child: Text(
                  text,
                  style: theme.titleStyle.copyWith(fontSize: 28),
                ),
              ),
      ),
    );
  }
}
