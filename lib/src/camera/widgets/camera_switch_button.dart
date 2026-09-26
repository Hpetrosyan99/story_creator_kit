import 'package:flutter/widgets.dart';

import '../../core/story_scope.dart';
import '../../ui/story_icon.dart';
import '../../ui/story_surface.dart';
import '../camera_keys.dart';

/// Switches between the front and rear lens: a 44 px pill with the flip
/// icon, in a 48 px tap target.
class CameraSwitchButton extends StatelessWidget {
  /// Creates the button.
  const CameraSwitchButton({required this.onPressed, super.key});

  /// Switch handler; `null` while unavailable.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final enabled = onPressed != null;
    return Semantics(
      key: CameraKeys.switchLens,
      button: true,
      enabled: enabled,
      label: scope.strings.camera.switchCamera,
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: StorySurface(
              fill: theme.pillBackground,
              radius: 22,
              padding: const EdgeInsets.all(10),
              child: StoryIcon(StoryIcons.flip, color: theme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}
