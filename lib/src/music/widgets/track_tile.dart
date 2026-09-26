import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../api/music/music_models.dart';
import '../../core/story_scope.dart';
import '../../ui/story_icon.dart';
import '../segment_math.dart';
import 'equalizer_bars.dart';

/// One row of the music list: optional rank, artwork, title, "Artist |
/// mm:ss" and a trailing bookmark (or ⋮ menu on ranked rows).
///
/// Tapping the row picks the track (the caller opens the segment selector);
/// a long press toggles a preview. The [highlighted] row (selected, being
/// prepared or previewing) gets the surface background, an accent title and
/// the equaliser, which bounces while [playing]. While the track is being
/// prepared the trailing button shows a small progress ring.
class TrackTile extends StatelessWidget {
  /// Creates a row.
  const TrackTile({
    required this.track,
    required this.bookmarked,
    required this.showBookmark,
    required this.onSelect,
    required this.onPreview,
    required this.onBookmark,
    this.rank,
    this.highlighted = false,
    this.playing = false,
    this.previewing = false,
    this.progress,
    super.key,
  });

  /// The track.
  final MusicTrack track;

  /// Whether the track is bookmarked.
  final bool bookmarked;

  /// Whether bookmarking is offered (the bookmark button or the ⋮ menu).
  final bool showBookmark;

  /// Picks the track; `null` disables the row.
  final VoidCallback? onSelect;

  /// Toggles the preview (long press); `null` disables it.
  final VoidCallback? onPreview;

  /// Toggles the bookmark.
  final VoidCallback onBookmark;

  /// 1-based position on a ranked list; `null` for none. Ranked rows show
  /// the ⋮ menu instead of the bookmark button.
  final int? rank;

  /// Whether the row is styled as the selected one.
  final bool highlighted;

  /// Whether the equaliser of a [highlighted] row bounces.
  final bool playing;

  /// Whether this row is previewing (selects the preview action's label).
  final bool previewing;

  /// Download progress while this track is prepared (`null` value while the
  /// size is unknown); `null` when the track is not being prepared.
  final ValueListenable<double?>? progress;

  /// Row height: 40 px artwork plus 8 px above and below.
  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final strings = scope.strings.music;
    final progress = this.progress;
    final rank = this.rank;
    final onPreview = this.onPreview;
    final Widget? trailing;
    if (progress != null) {
      trailing = _PreparingRing(progress: progress);
    } else if (!showBookmark) {
      trailing = null;
    } else if (rank != null) {
      trailing = _MoreButton(bookmarked: bookmarked, onBookmark: onBookmark);
    } else {
      trailing = _TrailingButton(
        key: const ValueKey('music-bookmark'),
        label: bookmarked ? strings.removeBookmark : strings.bookmark,
        selected: bookmarked,
        onPressed: onBookmark,
        icon: bookmarked
            ? StoryIcon(StoryIcons.bookmarkFilled, color: theme.accent)
            : StoryIcon(StoryIcons.bookmark, color: theme.onSurface),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: highlighted ? theme.surface : null),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            Expanded(
              child: MergeSemantics(
                child: Semantics(
                  button: true,
                  selected: highlighted,
                  hint: strings.useTrack,
                  customSemanticsActions: onPreview == null
                      ? null
                      : {
                          CustomSemanticsAction(
                            label: previewing
                                ? strings.stopPreview
                                : strings.preview,
                          ): onPreview,
                        },
                  child: GestureDetector(
                    key: const ValueKey('music-track-select'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onSelect,
                    onLongPress: onPreview,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: trailing == null ? 16 : 8,
                      ),
                      child: Row(
                        spacing: 8,
                        children: [
                          if (rank != null)
                            SizedBox(
                              width: 15,
                              child: Text(
                                '$rank',
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.visible,
                                style: theme.bodyStyle.copyWith(
                                  color: theme.onSurfaceSecondary,
                                ),
                              ),
                            ),
                          _Artwork(track: track),
                          Expanded(
                            child: _TrackText(
                              track: track,
                              highlighted: highlighted,
                              playing: playing,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (trailing != null) ...[
              trailing,
              // The 24 px icon ends 16 px from the edge, like the design.
              const SizedBox(width: 4),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrackText extends StatelessWidget {
  const _TrackText({
    required this.track,
    required this.highlighted,
    required this.playing,
  });

  final MusicTrack track;
  final bool highlighted;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          spacing: 4,
          children: [
            if (highlighted)
              EqualizerBars(color: theme.accent, animating: playing),
            Flexible(
              child: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: highlighted
                    ? theme.bodyStyle.copyWith(color: theme.accent)
                    : theme.bodyStyle,
              ),
            ),
          ],
        ),
        Text(
          '${track.artist} | ${formatMusicClock(track.duration)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.captionStyle,
        ),
      ],
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.track});

  final MusicTrack track;

  @override
  Widget build(BuildContext context) {
    final artwork = track.artwork;
    const placeholder = _ArtworkPlaceholder();
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox.square(
          dimension: 40,
          child: artwork == null
              ? placeholder
              : Image(
                  image: artwork,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => placeholder,
                ),
        ),
      ),
    );
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    return ColoredBox(
      color: theme.surfaceVariant,
      child: Center(
        child: StoryIcon(StoryIcons.music, color: theme.onSurfaceMuted),
      ),
    );
  }
}

/// A 48 px tap target around a 24 px icon.
class _TrailingButton extends StatelessWidget {
  const _TrailingButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.selected,
    super.key,
  });

  final String label;
  final Widget icon;
  final VoidCallback onPressed;
  final bool? selected;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    toggled: selected,
    label: label,
    excludeSemantics: true,
    onTap: onPressed,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: SizedBox.square(dimension: 48, child: Center(child: icon)),
    ),
  );
}

/// The ⋮ of a ranked row: a small menu with the bookmark toggle.
class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.bookmarked, required this.onBookmark});

  final bool bookmarked;
  final VoidCallback onBookmark;

  Future<void> _open(BuildContext context) async {
    final scope = StoryScope.read(context);
    final theme = scope.theme;
    final strings = scope.strings.music;
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );
    final picked = await showMenu<bool>(
      context: context,
      position: position,
      color: theme.surfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        side: BorderSide(color: theme.outline),
      ),
      items: [
        PopupMenuItem<bool>(
          key: const ValueKey('music-more-bookmark'),
          value: true,
          child: Row(
            spacing: 8,
            children: [
              if (bookmarked)
                StoryIcon(StoryIcons.bookmarkFilled, color: theme.accent)
              else
                StoryIcon(StoryIcons.bookmark, color: theme.onSurface),
              Text(
                bookmarked ? strings.removeBookmark : strings.bookmark,
                style: theme.bodyStyle,
              ),
            ],
          ),
        ),
      ],
    );
    if (picked ?? false) {
      onBookmark();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    return _TrailingButton(
      key: const ValueKey('music-more'),
      label: scope.strings.music.moreActions,
      onPressed: () => unawaited(_open(context)),
      icon: StoryIcon(StoryIcons.moreVertical, color: scope.theme.onSurface),
    );
  }
}

class _PreparingRing extends StatelessWidget {
  const _PreparingRing({required this.progress});

  final ValueListenable<double?> progress;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    return Semantics(
      label: scope.strings.music.downloading,
      liveRegion: true,
      excludeSemantics: true,
      child: SizedBox.square(
        key: const ValueKey('music-preparing'),
        dimension: 48,
        child: Center(
          child: SizedBox.square(
            dimension: 18,
            child: ValueListenableBuilder<double?>(
              valueListenable: progress,
              builder: (context, value, _) => CircularProgressIndicator(
                value: value,
                strokeWidth: 2,
                color: theme.accent,
                backgroundColor: theme.outline,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
