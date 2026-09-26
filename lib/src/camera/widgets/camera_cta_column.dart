import 'package:flutter/widgets.dart';

import '../../core/story_scope.dart';
import '../../ui/story_icon.dart';

/// One icon of the camera's left CTA column: a 20 px [StoryIcon] with a
/// 48 px tap target.
class CameraCtaButton extends StatelessWidget {
  /// Creates the button.
  const CameraCtaButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.badge = false,
    super.key,
  });

  /// Icon.
  final StoryIcons icon;

  /// Semantics label.
  final String label;

  /// Tap handler; `null` disables the button.
  final VoidCallback? onPressed;

  /// Tints the icon with the accent (e.g. flash on).
  final bool active;

  /// Shows a small accent dot at the icon's top-right (e.g. flash auto).
  final bool badge;

  /// Tap target side.
  static const double target = 48;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox.square(
          dimension: target,
          child: Center(
            child: Opacity(
              opacity: enabled ? 1 : 0.4,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  StoryIcon(
                    icon,
                    color: active ? theme.accent : theme.onSurface,
                  ),
                  if (badge)
                    Positioned(
                      right: -3,
                      top: -3,
                      child: SizedBox.square(
                        dimension: 7,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: theme.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The camera's vertical CTA column: 20 px icons 13 px apart (a 33 px
/// pitch), each with a 48 px tap target. Neighbouring targets overlap
/// slightly so the icons keep the design's spacing.
class CameraCtaColumn extends StatelessWidget {
  /// Creates the column.
  const CameraCtaColumn({required this.children, super.key});

  /// The buttons, usually [CameraCtaButton]s, top to bottom.
  final List<Widget> children;

  /// Icon size plus gap.
  static const double pitch = 33;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: CameraCtaButton.target,
      height: CameraCtaButton.target + (children.length - 1) * pitch,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < children.length; i++)
            Positioned(
              left: 0,
              top: i * pitch,
              width: CameraCtaButton.target,
              height: CameraCtaButton.target,
              child: children[i],
            ),
        ],
      ),
    );
  }
}
