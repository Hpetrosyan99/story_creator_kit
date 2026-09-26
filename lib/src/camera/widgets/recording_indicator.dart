import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/story_scope.dart';
import '../../ui/story_surface.dart';
import '../camera_keys.dart';

/// Formats [d] as `m:ss` (or `h:mm:ss`).
String formatStoryDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}

/// Red dot and elapsed time while recording, on a translucent pill.
class RecordingIndicator extends StatelessWidget {
  /// Creates the indicator.
  const RecordingIndicator({required this.elapsed, super.key});

  /// Elapsed recording time.
  final ValueListenable<Duration> elapsed;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    return ValueListenableBuilder<Duration>(
      valueListenable: elapsed,
      builder: (context, value, _) {
        final text = _mmss(value);
        return Semantics(
          key: CameraKeys.recordingIndicator,
          label: '${scope.strings.camera.recording} $text',
          excludeSemantics: true,
          child: StorySurface(
            fill: theme.pillBackground,
            radius: 17,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  text,
                  style: theme.titleStyle.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _mmss(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
