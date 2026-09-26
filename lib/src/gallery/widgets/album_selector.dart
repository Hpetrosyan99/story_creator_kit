import 'package:flutter/widgets.dart';

import '../../core/story_scope.dart';
import '../../services/gallery/gallery_source.dart';
import '../../ui/story_icon.dart';
import '../gallery_keys.dart';

/// Display name of [album]: the localised "Recent" for the all-media album.
String galleryAlbumName(BuildContext context, GalleryAlbum album) =>
    album.isAll ? StoryScope.of(context).strings.camera.recent : album.name;

/// The "Recent ›" header button (Body/S Emphasis with a soft shadow and a
/// chevron) that opens the album list.
class AlbumSelector extends StatelessWidget {
  /// Creates the selector.
  const AlbumSelector({
    required this.name,
    required this.open,
    required this.onPressed,
    super.key,
  });

  /// Name of the shown album.
  final String name;

  /// Whether the album list is open.
  final bool open;

  /// Toggles the album list; `null` when there is nothing to choose.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final animate = !MediaQuery.disableAnimationsOf(context);
    return Semantics(
      key: GalleryKeys.albumSelector,
      button: true,
      expanded: open,
      enabled: onPressed != null,
      label: '${scope.strings.camera.selectAlbum}: $name',
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 2,
              children: [
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyEmphasisStyle.copyWith(
                      shadows: [
                        Shadow(
                          color: theme.scrim.withValues(
                            alpha: theme.scrim.a * 0.6,
                          ),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: open ? 0.25 : 0,
                  duration: animate
                      ? const Duration(milliseconds: 160)
                      : Duration.zero,
                  child: StoryIcon(
                    StoryIcons.chevronRight,
                    color: theme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// List of albums with their item counts.
class AlbumList extends StatelessWidget {
  /// Creates the list.
  const AlbumList({
    required this.albums,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  /// Albums, "all recent" first.
  final List<GalleryAlbum> albums;

  /// The shown album.
  final GalleryAlbum? selected;

  /// Called with the chosen album.
  final ValueChanged<GalleryAlbum> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    return ListView.builder(
      key: GalleryKeys.albumList,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        final isSelected = album.id == selected?.id;
        final name = galleryAlbumName(context, album);
        return Semantics(
          key: GalleryKeys.album(album.id),
          button: true,
          selected: isSelected,
          label: '$name, ${album.count}',
          excludeSemantics: true,
          onTap: () => onSelected(album),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelected(album),
            child: ColoredBox(
              color: isSelected ? theme.surface : theme.background,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: isSelected
                              ? theme.titleStyle
                              : theme.bodyLargeStyle,
                        ),
                      ),
                      Text('${album.count}', style: theme.captionStyle),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
