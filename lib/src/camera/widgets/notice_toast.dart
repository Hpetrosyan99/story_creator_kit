import 'package:flutter/widgets.dart';

import '../../core/story_scope.dart';
import '../../ui/story_surface.dart';

/// A translucent pill with a short message; announced to screen readers.
class NoticeToast extends StatelessWidget {
  /// Creates the toast.
  const NoticeToast({required this.message, super.key});

  /// The message.
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: StorySurface(
        fill: theme.surface.withValues(alpha: 0.9),
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.bodyStyle,
        ),
      ),
    );
  }
}
