import 'package:flutter/widgets.dart';

import '../../core/story_scope.dart';

/// Placeholder rows shown while the first page of tracks loads: artwork
/// square and two text bars per row, in the raised surface colour.
class MusicListSkeleton extends StatelessWidget {
  /// Creates the skeleton.
  const MusicListSkeleton({this.rows = 10, super.key});

  /// Number of placeholder rows.
  final int rows;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final fill = BoxDecoration(
      color: theme.surfaceVariant,
      borderRadius: BorderRadius.circular(4),
    );
    return Semantics(
      label: scope.strings.music.loading,
      liveRegion: true,
      excludeSemantics: true,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          maxHeight: double.infinity,
          child: Column(
            key: const ValueKey('music-list-skeleton'),
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < rows; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    spacing: 8,
                    children: [
                      DecoratedBox(
                        decoration: fill.copyWith(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const SizedBox.square(dimension: 40),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 8,
                          children: [
                            FractionallySizedBox(
                              widthFactor: i.isEven ? 0.55 : 0.4,
                              child: DecoratedBox(
                                decoration: fill,
                                child: const SizedBox(height: 12),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: i.isEven ? 0.35 : 0.45,
                              child: DecoratedBox(
                                decoration: fill,
                                child: const SizedBox(height: 10),
                              ),
                            ),
                          ],
                        ),
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
