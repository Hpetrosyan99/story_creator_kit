import 'package:flutter/material.dart';

import '../../core/story_scope.dart';
import '../camera_keys.dart';
import 'permission_prompt.dart';

/// Shown when no usable camera exists or it failed; offers a retry.
class CameraUnavailableView extends StatelessWidget {
  /// Creates the view.
  const CameraUnavailableView({required this.onRetry, super.key});

  /// Tries to start the camera again.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    return Center(
      key: CameraKeys.unavailable,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.no_photography_outlined,
              size: 48,
              color: theme.onSurfaceMuted,
            ),
            const SizedBox(height: 16),
            Text(
              scope.strings.camera.cameraUnavailable,
              textAlign: TextAlign.center,
              style: theme.bodyStyle,
            ),
            const SizedBox(height: 20),
            StoryActionButton(
              label: scope.strings.common.retry,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown while the camera starts or reconnects, so a frozen frame is never
/// left on screen.
class CameraStartingView extends StatelessWidget {
  /// Creates the view.
  const CameraStartingView({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    return ColoredBox(
      key: CameraKeys.starting,
      color: theme.background,
      child: Center(
        child: Semantics(
          label: scope.strings.camera.cameraStarting,
          liveRegion: true,
          excludeSemantics: true,
          child: SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: theme.onSurfaceMuted,
            ),
          ),
        ),
      ),
    );
  }
}
