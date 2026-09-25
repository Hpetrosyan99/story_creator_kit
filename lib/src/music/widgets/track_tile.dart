import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../api/music/music_models.dart';
import '../../core/story_scope.dart';
import '../segment_math.dart';
import 'equalizer_bars.dart';

/// One row of the music list.
///
/// Tapping the row (artwork, title and artist) toggles the preview. The
/// trailing "use" button (`MusicStrings.useTrack`) picks the track and opens
/// the segment selector; while the track is being prepared that button shows
/// the download progress instead.
class TrackTile extends StatelessWidget {
  /// Creates a row.
  const TrackTile({
    required this.track,
    required this.bookmarked,
    required this.showBookmark,
    required this.previewing,
    required this.onPreview,
    required this.onBookmark,
    required this.onUse,
    this.progress,
    super.key,
  });

  /// The track.
  final MusicTrack track;

  /// Whether the track is bookmarked.
  final bool bookmarked;

  /// Whether the bookmark button is shown.
  final bool showBookmark;

  /// Whether this row is previewing.
  final bool previewing;

  /// Toggles the preview.
  final VoidCallback onPreview;

  /// Toggles the bookmark.
  final VoidCallback onBookmark;

  /// Picks the track; `null` disables the button.
  final VoidCallback? onUse;

  /// Download progress while this track is prepared (`null` value while the
  /// size is unknown); `null` when the track is not being prepared.
  final ValueListenable<double?>? progress;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final strings = scope.strings.music;
    final progress = this.progress;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Row(
        children: [
          Expanded(
            child: MergeSemantics(
              child: Semantics(
                button: true,
                hint: previewing ? strings.stopPreview : strings.preview,
                child: InkWell(
                  onTap: onPreview,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    child: Row(
                      children: [
                        _Artwork(track: track),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TrackText(
                            track: track,
                            previewing: previewing,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (showBookmark)
            IconButton(
              tooltip: bookmarked ? strings.removeBookmark : strings.bookmark,
              onPressed: onBookmark,
              icon: Icon(
                bookmarked ? Icons.bookmark : Icons.bookmark_border,
                color: bookmarked ? theme.accent : theme.onSurface,
              ),
            ),
          if (progress != null)
            Semantics(
              label: strings.downloading,
              child: SizedBox.square(
                dimension: 48,
                child: Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: ValueListenableBuilder<double?>(
                      valueListenable: progress,
                      builder: (context, value, _) => CircularProgressIndicator(
                        value: value,
                        strokeWidth: 2.5,
                        color: theme.accent,
                        backgroundColor: theme.outline,
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            IconButton(
              tooltip: strings.useTrack,
              onPressed: onUse,
              icon: Icon(Icons.add_circle_outline, color: theme.onSurface),
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _TrackText extends StatelessWidget {
  const _TrackText({required this.track, required this.previewing});

  final MusicTrack track;
  final bool previewing;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: previewing
                    ? theme.bodyStyle.copyWith(color: theme.accent)
                    : theme.bodyStyle,
              ),
            ),
            if (previewing) ...[
              const SizedBox(width: 6),
              EqualizerBars(color: theme.accent, size: 12),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${track.artist} | ${formatMusicTime(track.duration)}',
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
    final theme = StoryScope.of(context).theme;
    final artwork = track.artwork;
    const placeholder = _ArtworkPlaceholder();
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(theme.cornerRadius / 2),
        child: SizedBox.square(
          dimension: 48,
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
      child: Center(child: Icon(Icons.music_note, color: theme.onSurfaceMuted)),
    );
  }
}
