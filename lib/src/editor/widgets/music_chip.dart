import 'package:flutter/material.dart';

import '../../core/story_scope.dart';
import '../../model/music_selection.dart';
import '../../ui/story_icon.dart';
import '../../ui/story_surface.dart';

/// The selected track at the bottom-right of the canvas: artwork, title and
/// "Artist | mm:ss". Tapping it changes the music.
class MusicChip extends StatelessWidget {
  /// Creates the chip.
  const MusicChip({required this.music, required this.onPressed, super.key});

  /// The selected music.
  final MusicSelection music;

  /// Opens the music picker.
  final VoidCallback? onPressed;

  /// Chip corner radius (design radius xl).
  static const double radius = 20;

  /// Artwork side.
  static const double artworkSize = 40;

  /// Artwork corner radius (design radius md).
  static const double artworkRadius = 12;

  /// `mm:ss` of [duration] (minutes are not wrapped at an hour).
  static String formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final track = music.track;
    final subtitle = '${track.artist} | ${formatDuration(track.duration)}';
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: scope.strings.editor.selectedMusic,
      value: '${track.title}, ${track.artist}',
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: StorySurface(
          fill: theme.surface,
          radius: radius,
          padding: const EdgeInsets.all(10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              _Artwork(image: track.artwork),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: theme.bodyStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: theme.captionStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.image});

  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    final placeholder = ColoredBox(
      color: theme.surfaceVariant,
      child: Center(
        child: StoryIcon(StoryIcons.music, color: theme.onSurfaceMuted),
      ),
    );
    final artwork = image;
    return ClipRRect(
      borderRadius: BorderRadius.circular(MusicChip.artworkRadius),
      child: SizedBox.square(
        dimension: MusicChip.artworkSize,
        child: artwork == null
            ? placeholder
            : Image(
                image: artwork,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, _, _) => placeholder,
              ),
      ),
    );
  }
}
