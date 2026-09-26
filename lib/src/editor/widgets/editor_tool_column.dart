import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/story_scope.dart';
import '../../ui/story_icon.dart';
import '../../ui/story_surface.dart';

/// One tool in the editor's right-hand column: a 20 px icon (white, accent
/// when [selected]) on a 36 px translucent dark circle, so it stays visible
/// on bright media, inside a 48 px tap target.
///
/// Takes a design icon ([icon]) or, for tools the design has no SVG for, a
/// Material glyph ([glyph]) drawn at the same size with the same shadow.
class EditorToolButton extends StatelessWidget {
  /// Creates a tool button.
  const EditorToolButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.glyph,
    this.selected = false,
    super.key,
  }) : assert(
         (icon == null) != (glyph == null),
         'Pass exactly one of icon and glyph.',
       );

  /// Design icon.
  final StoryIcons? icon;

  /// Material icon, when there is no design icon.
  final IconData? glyph;

  /// Semantics label.
  final String label;

  /// Tap handler; `null` disables the button.
  final VoidCallback? onPressed;

  /// Whether the tool is active (accent tint).
  final bool selected;

  /// Tap target side.
  static const double target = 48;

  /// Icon side.
  static const double iconSize = 20;

  /// Diameter of the backdrop circle.
  static const double backdrop = 36;

  /// The design's icon shadow (as drawn by [StoryIcon]).
  static const Shadow _shadow = StoryIcon.designShadow;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    final enabled = onPressed != null;
    final color = selected ? theme.accent : theme.onSurface;
    final design = icon;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox.square(
            dimension: target,
            child: Center(
              child: SizedBox.square(
                dimension: backdrop,
                child: StorySurface(
                  fill: theme.pillBackground,
                  radius: backdrop / 2,
                  child: Center(
                    child: design != null
                        ? StoryIcon(design, color: color)
                        : Icon(
                            glyph,
                            size: iconSize + 2,
                            color: color,
                            shadows: const [_shadow],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The editor's right-hand tool column: 36 px tool circles 6 px apart, each
/// with a full 48 px tap target (neighbouring targets overlap by 6 px; the
/// lower one wins there).
class EditorToolColumn extends StatelessWidget {
  /// Creates the column.
  const EditorToolColumn({required this.children, super.key});

  /// The tools, top to bottom.
  final List<Widget> children;

  /// Distance between tool centres: 36 px circle + 6 px gap.
  static const double pitch = EditorToolButton.backdrop + 6;

  /// Height of a column of [count] tools.
  static double heightFor(int count) =>
      count == 0 ? 0 : (count - 1) * pitch + EditorToolButton.target;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: EditorToolButton.target,
    height: heightFor(children.length),
    child: Stack(
      children: [
        for (var i = 0; i < children.length; i++)
          Positioned(
            top: i * pitch,
            left: 0,
            width: EditorToolButton.target,
            height: EditorToolButton.target,
            child: children[i],
          ),
      ],
    ),
  );
}

/// [EditorToolColumn] with the "More" tools animating in and out.
///
/// [progress] runs 0 (collapsed) → 1 (expanded). The [more] tools appear
/// one after another below [main], each fading, growing and sliding down
/// into place, while [chevron] moves down beneath them and turns over.
/// Collapsing plays the same motion backwards. Tools that are not fully
/// shown ignore taps and are hidden from screen readers.
class AnimatedEditorToolColumn extends StatelessWidget {
  /// Creates the column.
  const AnimatedEditorToolColumn({
    required this.main,
    required this.more,
    required this.chevron,
    required this.progress,
    super.key,
  });

  /// Always-visible tools, top to bottom.
  final List<Widget> main;

  /// Tools behind "More", top to bottom.
  final List<Widget> more;

  /// The More / Fewer toggle, last in the column.
  final Widget chevron;

  /// Expansion, 0–1.
  final double progress;

  /// How far a tool slides into place, as a fraction of [EditorToolColumn.pitch].
  static const double _slide = 0.6;

  /// Height of the column at [progress].
  static double heightFor(int main, int more, double progress) =>
      EditorToolColumn.heightFor(main + 1) +
      more * progress * EditorToolColumn.pitch;

  @override
  Widget build(BuildContext context) {
    const pitch = EditorToolColumn.pitch;
    const target = EditorToolButton.target;
    final count = more.length;
    return SizedBox(
      width: target,
      height: heightFor(main.length, count, progress),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < main.length; i++)
            Positioned(
              top: i * pitch,
              left: 0,
              width: target,
              height: target,
              child: main[i],
            ),
          for (var i = 0; i < count; i++)
            // Staggered: tool i starts once the previous ones are shown;
            // fully hidden tools are not built at all.
            if (progress * count - i > 0)
              _MoreTool(
                top: (main.length + i) * pitch,
                visible: (progress * count - i).clamp(0.0, 1.0),
                child: more[i],
              ),
          Positioned(
            top: (main.length + count * progress) * pitch,
            left: 0,
            width: target,
            height: target,
            child: Transform.rotate(angle: progress * math.pi, child: chevron),
          ),
        ],
      ),
    );
  }
}

class _MoreTool extends StatelessWidget {
  const _MoreTool({
    required this.top,
    required this.visible,
    required this.child,
  });

  final double top;
  final double visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const target = EditorToolButton.target;
    return Positioned(
      top:
          top -
          (1 - visible) *
              EditorToolColumn.pitch *
              AnimatedEditorToolColumn._slide,
      left: 0,
      width: target,
      height: target,
      child: IgnorePointer(
        ignoring: visible < 1,
        child: ExcludeSemantics(
          excluding: visible < 1,
          child: Opacity(
            opacity: visible,
            child: Transform.scale(scale: 0.6 + 0.4 * visible, child: child),
          ),
        ),
      ),
    );
  }
}
