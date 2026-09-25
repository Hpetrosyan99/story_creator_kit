import 'package:flutter/material.dart';

import '../../core/story_scope.dart';
import '../../services/capture/capture_service.dart';
import '../camera_keys.dart';
import 'round_icon_button.dart';

/// Cycles the flash mode. For lenses without a hardware flash it toggles
/// the screen flash (off / on).
class FlashToggle extends StatelessWidget {
  /// Creates the toggle.
  const FlashToggle({required this.mode, required this.onPressed, super.key});

  /// Current mode.
  final StoryFlashMode mode;

  /// Called to switch to the next mode.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final strings = StoryScope.of(context).strings.camera;
    final (icon, label) = switch (mode) {
      StoryFlashMode.off => (Icons.flash_off_rounded, strings.flashOff),
      StoryFlashMode.auto => (Icons.flash_auto_rounded, strings.flashAuto),
      StoryFlashMode.on => (Icons.flash_on_rounded, strings.flashOn),
    };
    return RoundIconButton(
      key: CameraKeys.flash,
      icon: icon,
      label: label,
      selected: mode != StoryFlashMode.off,
      onPressed: onPressed,
    );
  }
}
