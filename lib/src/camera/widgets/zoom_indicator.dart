import 'package:flutter/widgets.dart';

import '../../core/story_scope.dart';
import '../camera_keys.dart';

/// Pill with the zoom factor, e.g. `2.0×`.
class ZoomIndicator extends StatelessWidget {
  /// Creates the indicator.
  const ZoomIndicator({required this.zoom, super.key});

  /// Zoom factor.
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final text = '${zoom.toStringAsFixed(1)}×';
    return Semantics(
      key: CameraKeys.zoom,
      label: '${scope.strings.camera.zoomLevel} $text',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.controlBackground,
          borderRadius: BorderRadius.circular(theme.chipRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(text, style: theme.labelStyle),
        ),
      ),
    );
  }
}
