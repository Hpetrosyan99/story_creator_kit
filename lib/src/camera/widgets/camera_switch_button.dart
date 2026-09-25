import 'package:flutter/material.dart';

import '../../core/story_scope.dart';
import '../camera_keys.dart';
import 'round_icon_button.dart';

/// Switches between the front and rear lens.
class CameraSwitchButton extends StatelessWidget {
  /// Creates the button.
  const CameraSwitchButton({required this.onPressed, super.key});

  /// Switch handler; `null` while unavailable.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => RoundIconButton(
    key: CameraKeys.switchLens,
    icon: Icons.flip_camera_ios_outlined,
    label: StoryScope.of(context).strings.camera.switchCamera,
    onPressed: onPressed,
  );
}
