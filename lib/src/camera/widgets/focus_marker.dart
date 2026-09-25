import 'package:flutter/widgets.dart';

import '../../core/story_scope.dart';
import '../camera_keys.dart';

/// Square marker drawn where the user tapped to focus.
class FocusMarker extends StatelessWidget {
  /// Creates the marker.
  const FocusMarker({super.key});

  /// Marker edge length.
  static const double size = 64;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    return ExcludeSemantics(
      key: CameraKeys.focusMarker,
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: theme.accent, width: 1.5),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}
