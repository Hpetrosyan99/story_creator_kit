import 'package:flutter/material.dart';

import '../../core/story_scope.dart';
import '../gallery_keys.dart';

/// First grid tile: goes back to the camera.
class CameraTile extends StatelessWidget {
  /// Creates the tile.
  const CameraTile({required this.onPressed, super.key});

  /// Closes the gallery.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final label = scope.strings.camera.camera;
    return Semantics(
      key: GalleryKeys.cameraTile,
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: ColoredBox(
          color: theme.surfaceVariant,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.photo_camera_outlined,
                size: 30,
                color: theme.onSurface,
              ),
              const SizedBox(height: 6),
              Text(label, style: theme.labelStyle),
            ],
          ),
        ),
      ),
    );
  }
}
