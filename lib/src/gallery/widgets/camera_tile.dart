import 'package:flutter/widgets.dart';

import '../../core/story_scope.dart';
import '../../ui/story_icon.dart';
import '../gallery_keys.dart';

/// First grid tile: goes back to the camera. A raised surface with the
/// camera icon.
class CameraTile extends StatelessWidget {
  /// Creates the tile.
  const CameraTile({required this.onPressed, super.key});

  /// Closes the gallery.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    return Semantics(
      key: GalleryKeys.cameraTile,
      button: true,
      label: scope.strings.camera.camera,
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: ColoredBox(
          color: theme.surfaceVariant,
          child: Center(
            child: StoryIcon(StoryIcons.camera, color: theme.onSurface),
          ),
        ),
      ),
    );
  }
}
