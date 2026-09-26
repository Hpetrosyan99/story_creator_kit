import 'package:flutter/widgets.dart';

import '../core/story_scope.dart';
import 'story_surface.dart';

/// A pill switcher on the canvas, e.g. "Video | Photo".
///
/// A capsule sits behind the selected option and slides to another option
/// when it is tapped, with a smooth ease-out. The capsule can also be
/// dragged sideways: it follows the finger and settles on the nearest
/// option on release. The selected label is semibold primary, the others
/// regular secondary, cross-fading as the capsule moves.
class StoryPillToggle<T> extends StatefulWidget {
  /// Creates the toggle.
  const StoryPillToggle({
    required this.options,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  /// Values and labels in display order.
  final List<(T, String)> options;

  /// Selected value.
  final T selected;

  /// Called with the picked value; `null` disables the toggle.
  final ValueChanged<T>? onChanged;

  @override
  State<StoryPillToggle<T>> createState() => _StoryPillToggleState<T>();
}

class _StoryPillToggleState<T> extends State<StoryPillToggle<T>>
    with SingleTickerProviderStateMixin {
  // The pill is 34 px tall (6 px padding + 22 px text); the capsule sits
  // 2 px inside it and the whole 48 px height is the tap/drag target.
  static const double _height = 48;
  static const double _pillHeight = 34;
  static const double _inset = 2;
  static const double _padding = 12;
  static const Duration _duration = Duration(milliseconds: 300);

  /// Capsule position, 0 (first option) – 1 (last option).
  late final AnimationController _position = AnimationController(
    vsync: this,
    duration: _duration,
    value: _fraction(_index(widget.selected)),
  );

  /// Capsule position at the start of a drag, and the drag distance.
  double? _dragStart;
  double _dragDelta = 0;

  int get _last => widget.options.length - 1;

  int _index(T value) {
    final i = widget.options.indexWhere((o) => o.$1 == value);
    return i < 0 ? 0 : i;
  }

  @override
  void didUpdateWidget(StoryPillToggle<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dragStart == null && oldWidget.selected != widget.selected) {
      _animateTo(_index(widget.selected));
    }
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  double _fraction(int index) => _last == 0 ? 0 : index / _last;

  void _animateTo(int index) {
    final target = _fraction(index);
    if (MediaQuery.disableAnimationsOf(context)) {
      _position.value = target;
    } else {
      _position.animateTo(target, curve: Curves.easeOutCubic);
    }
  }

  void _pick(int index) {
    final onChanged = widget.onChanged;
    if (onChanged == null) {
      return;
    }
    _animateTo(index);
    final value = widget.options[index].$1;
    if (value != widget.selected) {
      onChanged(value);
    }
  }

  /// Option widths: each label at the selected (semibold) style plus
  /// padding, so the layout does not shift when the selection changes.
  List<double> _widths(TextStyle style) => [
    for (final (_, label) in widget.options)
      (TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout()).width.ceilToDouble() +
          _padding * 2,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    final selectedStyle = theme.titleStyle;
    final otherStyle = theme.bodyLargeStyle.copyWith(
      color: theme.onSurfaceSecondary,
    );
    final widths = _widths(selectedStyle);
    final lefts = <double>[];
    var x = _inset;
    for (final w in widths) {
      lefts.add(x);
      x += w;
    }
    final total = x + _inset;
    final enabled = widget.onChanged != null;
    return SizedBox(
      width: total,
      height: _height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: !enabled || _last == 0
            ? null
            : (_) {
                _position.stop();
                _dragStart = _position.value;
                _dragDelta = 0;
              },
        onHorizontalDragUpdate: !enabled || _last == 0
            ? null
            : (details) {
                final start = _dragStart;
                if (start == null) {
                  return;
                }
                _dragDelta += details.delta.dx;
                // One option's width of travel moves the capsule one step.
                final step = (total - _inset * 2) / widget.options.length;
                _position.value = (start + _dragDelta / step / _last).clamp(
                  0.0,
                  1.0,
                );
              },
        onHorizontalDragEnd: !enabled || _last == 0
            ? null
            : (_) {
                _dragStart = null;
                _pick((_position.value * _last).round());
              },
        onHorizontalDragCancel: () {
          if (_dragStart != null) {
            _dragStart = null;
            _animateTo(_index(widget.selected));
          }
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: total,
              height: _pillHeight,
              child: StorySurface(
                fill: theme.pillBackground,
                radius: _pillHeight / 2,
                child: const SizedBox.expand(),
              ),
            ),
            AnimatedBuilder(
              animation: _position,
              builder: (context, _) {
                // Interpolate the capsule between neighbouring options.
                final pos = _position.value * _last;
                final i = pos.floor().clamp(0, _last);
                final j = (i + 1).clamp(0, _last);
                final f = pos - i;
                final left = lefts[i] + (lefts[j] - lefts[i]) * f;
                final width = widths[i] + (widths[j] - widths[i]) * f;
                return Stack(
                  children: [
                    Positioned(
                      left: left,
                      width: width,
                      top: (_height - _pillHeight) / 2 + _inset,
                      height: _pillHeight - _inset * 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.onSurface.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(_pillHeight / 2),
                        ),
                      ),
                    ),
                    for (var k = 0; k < widget.options.length; k++)
                      Positioned(
                        left: lefts[k],
                        width: widths[k],
                        top: 0,
                        bottom: 0,
                        child: _Option(
                          label: widget.options[k].$2,
                          // 1 when the capsule is on this option.
                          emphasis: (1 - (pos - k).abs()).clamp(0.0, 1.0),
                          selected: widget.options[k].$1 == widget.selected,
                          selectedStyle: selectedStyle,
                          otherStyle: otherStyle,
                          onTap: enabled ? () => _pick(k) : null,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.emphasis,
    required this.selected,
    required this.selectedStyle,
    required this.otherStyle,
    required this.onTap,
  });

  final String label;
  final double emphasis;
  final bool selected;
  final TextStyle selectedStyle;
  final TextStyle otherStyle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle.lerp(otherStyle, selectedStyle, emphasis),
        ),
      ),
    ),
  );
}
