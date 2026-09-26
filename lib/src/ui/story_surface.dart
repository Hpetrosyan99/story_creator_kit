import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../core/story_scope.dart';

/// A translucent control background on the canvas: flat [fill] by default,
/// or "liquid glass" when `StoryCreatorTheme.isLiquidGlassEnabled` is set.
///
/// Glass is a backdrop blur with a saturation boost, a faint tint, a
/// diagonal sheen and a bright-to-dim rim. It uses `BackdropFilter.grouped`,
/// so every glass control under the story creator's `BackdropGroup` shares
/// one backdrop read.
class StorySurface extends StatelessWidget {
  /// Creates a surface with the given corner [radius].
  const StorySurface({
    required this.fill,
    required this.radius,
    required this.child,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  /// Flat fill (and, softened, the glass tint).
  final Color fill;

  /// Corner radius; use half the height for circles and pills.
  final double radius;

  /// Content.
  final Widget child;

  /// Inner padding.
  final EdgeInsetsGeometry padding;

  static const double _blurSigma = 14;
  static const double _saturation = 1.7;

  static final ui.ImageFilter _glassFilter = ui.ImageFilter.compose(
    outer: ColorFilter.matrix(_saturationMatrix(_saturation)),
    inner: ui.ImageFilter.blur(
      sigmaX: _blurSigma,
      sigmaY: _blurSigma,
      tileMode: TileMode.mirror,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    final shape = BorderRadius.circular(radius);
    // A glass surface re-blurs its backdrop every frame. Under a disabled
    // TickerMode (the editor while export or preview covers it, offstage
    // routes) it draws flat instead: those hidden blurs competed with the
    // video encoder for the GPU and stalled exports.
    final visible = TickerMode.valuesOf(context).enabled;
    if (!theme.isLiquidGlassEnabled || !visible) {
      return DecoratedBox(
        decoration: BoxDecoration(color: fill, borderRadius: shape),
        child: Padding(padding: padding, child: child),
      );
    }
    final tint = fill.withValues(alpha: fill.a * 0.45);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter.grouped(
          filter: _glassFilter,
          child: CustomPaint(
            foregroundPainter: _GlassRimPainter(radius),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: shape,
                color: tint,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0x2EFFFFFF),
                    Color(0x05FFFFFF),
                    Color(0x14FFFFFF),
                  ],
                  stops: [0, 0.55, 1],
                ),
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }

  static List<double> _saturationMatrix(double s) {
    const r = 0.2126;
    const g = 0.7152;
    const b = 0.0722;
    final i = 1 - s;
    return [
      r * i + s, g * i, b * i, 0, 0, //
      r * i, g * i + s, b * i, 0, 0,
      r * i, g * i, b * i + s, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }
}

/// The glass rim: brighter along the top-left, fading to the bottom-right.
class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter(this.radius);

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.5),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x80FFFFFF), Color(0x14FFFFFF), Color(0x40FFFFFF)],
        stops: [0, 0.5, 1],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_GlassRimPainter oldDelegate) =>
      oldDelegate.radius != radius;
}
