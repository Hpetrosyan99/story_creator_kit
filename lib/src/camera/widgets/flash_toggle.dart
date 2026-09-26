import 'package:flutter/widgets.dart';

import '../../core/story_scope.dart';
import '../../services/capture/capture_service.dart';
import '../../ui/story_icon.dart';
import '../camera_keys.dart';
import 'camera_cta_column.dart';

/// Cycles the flash mode. For lenses without a hardware flash it toggles
/// the screen flash (off / on).
///
/// Off is white, on is accent, auto is white with an accent dot.
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
    final label = switch (mode) {
      StoryFlashMode.off => strings.flashOff,
      StoryFlashMode.auto => strings.flashAuto,
      StoryFlashMode.on => strings.flashOn,
    };
    return CameraCtaButton(
      key: CameraKeys.flash,
      icon: StoryIcons.flash,
      label: label,
      active: mode == StoryFlashMode.on,
      badge: mode == StoryFlashMode.auto,
      onPressed: onPressed,
    );
  }
}
