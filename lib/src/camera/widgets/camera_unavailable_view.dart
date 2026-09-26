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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PromptBadge(icon: Icons.no_photography_outlined),
            const SizedBox(height: 16),
            Text(
              scope.strings.camera.cameraUnavailable,
              textAlign: TextAlign.center,
              style: theme.bodyStyle.copyWith(color: theme.onSurfaceSecondary),
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

/// Shown while the camera starts or reconnects: the plain dark card, so a
/// frozen frame is never left on screen and nothing spins. The preview
/// simply replaces it when it is ready.
class CameraStartingView extends StatelessWidget {
  /// Creates the view.
  const CameraStartingView({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    return Semantics(
      key: CameraKeys.starting,
      label: scope.strings.camera.cameraStarting,
      liveRegion: true,
      container: true,
      child: ColoredBox(color: scope.theme.surface),
    );
  }
}
