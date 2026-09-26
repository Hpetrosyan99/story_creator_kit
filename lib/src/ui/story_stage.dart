import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/story_scope.dart';

/// The page layout shared by the camera, editor, segment selector and
/// preview: a rounded canvas card from the top safe area down to the bottom
/// inset.
class StoryStage extends StatelessWidget {
  /// Creates the stage.
  const StoryStage({required this.card, super.key});

  /// Content of the rounded card (preview, canvas…) including its overlays.
  final Widget card;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    final padding = MediaQuery.paddingOf(context);
    return ColoredBox(
      color: theme.background,
      child: Padding(
        padding: EdgeInsets.only(
          top: padding.top,
          bottom: math.max<double>(padding.bottom, 8) + 8,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(theme.cornerRadius),
          child: card,
        ),
      ),
    );
  }
}
