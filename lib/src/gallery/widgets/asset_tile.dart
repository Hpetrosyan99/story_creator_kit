import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../api/result/story_result.dart';
import '../../camera/widgets/recording_indicator.dart';
import '../../core/story_scope.dart';
import '../../services/gallery/gallery_source.dart';
import '../gallery_keys.dart';

/// One 9:16 photo or video in the grid: thumbnail, video duration and a
/// 20 px selection circle. While the item is being loaded (e.g. downloaded from
/// iCloud) a progress overlay shows; tapping again cancels.
class AssetTile extends StatelessWidget {
  /// Creates the tile.
  AssetTile({
    required this.asset,
    required this.image,
    required this.onPressed,
    this.progress,
    Key? key,
  }) : super(key: key ?? GalleryKeys.tile(asset.id));

  /// The item.
  final GalleryAsset asset;

  /// Its thumbnail.
  final ImageProvider image;

  /// Selects (or cancels loading of) the item.
  final VoidCallback onPressed;

  /// Load progress (0–1) while the item is being resolved, else `null`.
  final ValueListenable<double>? progress;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final strings = scope.strings.camera;
    final duration = asset.duration;
    final isVideo = asset.type == StoryMediaType.video;
    final loading = progress;
    final label = isVideo
        ? duration == null
              ? strings.videoItem
              : '${strings.videoItem}, ${formatStoryDuration(duration)}'
        : strings.photoItem;
    return Semantics(
      button: true,
      selected: loading != null,
      label: loading == null
          ? label
          : '$label, ${strings.downloadingFromCloud}',
      hint: loading == null ? strings.selectMedia : strings.cancelDownload,
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: ColoredBox(
          color: theme.surfaceVariant,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image(
                image: image,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
                errorBuilder: (context, _, _) =>
                    ColoredBox(color: theme.surfaceVariant),
              ),
              if (isVideo && duration != null)
                Positioned(
                  right: 6,
                  bottom: 4,
                  child: Text(
                    formatStoryDuration(duration),
                    style: theme.labelStyle.copyWith(
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(
                          color: theme.scrim,
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                top: 4,
                right: 4,
                child: SizedBox.square(
                  dimension: 20,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: loading != null ? theme.accent : null,
                      border: Border.all(color: theme.onSurface, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: theme.scrim.withValues(
                            alpha: theme.scrim.a * 0.5,
                          ),
                          blurRadius: 2.5,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (loading != null)
                Positioned.fill(
                  child: ColoredBox(
                    color: theme.scrim,
                    child: Center(
                      child: ValueListenableBuilder<double>(
                        valueListenable: loading,
                        builder: (context, value, _) => SizedBox.square(
                          dimension: 32,
                          child: CircularProgressIndicator(
                            value: value <= 0 || value >= 1 ? null : value,
                            strokeWidth: 3,
                            color: theme.accent,
                            backgroundColor: theme.outline,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
