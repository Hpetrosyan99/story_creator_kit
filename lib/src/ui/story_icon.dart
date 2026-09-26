import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The design's icons, bundled as SVGs in `assets/icons/`.
///
/// Each entry records the icon's layout box in the design and how far the
/// SVG extends past that box (its bleed, room for a drop shadow or stroke),
/// so the SVG is drawn at its own size exactly where the design puts it.
enum StoryIcons {
  /// Close (✕), 20 px.
  close('close', 20, 20, 20),

  /// Confirm (✓), 20 px.
  check('check', 20, 20, 20),

  /// Back chevron, 24 px.
  chevronLeft('chevron_left', 24, 24, 24),

  /// Album selector chevron, 20 px, with shadow.
  chevronRight('chevron_right', 20, 20, 20, shadow: true),

  /// Flash, 20 px, with shadow.
  flash(
    'flash',
    20,
    24,
    29.0001,
    bleed: EdgeInsets.symmetric(horizontal: 2, vertical: 4.5),
    shadow: true,
  ),

  /// Text tool, 20 px, with shadow.
  text(
    'text',
    20,
    21.5,
    23.1667,
    bleed: EdgeInsets.symmetric(horizontal: 0.75, vertical: 1.584),
    shadow: true,
  ),

  /// Layouts / stickers (four squares), 20 px, with shadow.
  layouts('layouts', 20, 24, 24, bleed: EdgeInsets.all(2), shadow: true),

  /// Music notes, 20 px, with shadow.
  music(
    'music',
    20,
    25.8752,
    27.125,
    bleed: EdgeInsets.fromLTRB(3.876, 3.876, 2, 3.25),
    shadow: true,
  ),

  /// Lens switch, 24 px, with shadow.
  flip(
    'flip',
    24,
    28,
    27.635,
    bleed: EdgeInsets.symmetric(horizontal: 2, vertical: 1.817),
    shadow: true,
  ),

  /// Camera (gallery camera tile), 24 px, with shadow.
  camera(
    'camera',
    24,
    30,
    27,
    bleed: EdgeInsets.fromLTRB(3, 2, 3, 1),
    shadow: true,
  ),

  /// Search magnifier, 24 px (accent in the design).
  search('search', 24, 24, 24),

  /// Chip clear (✕), 16 px (accent in the design).
  chipClose('chip_close', 16, 16, 16),

  /// Bookmark outline, 24 px.
  bookmark('bookmark', 24, 24, 24),

  /// Bookmark filled, 24 px (accent in the design).
  bookmarkFilled('bookmark_filled', 24, 24, 24),

  /// Vertical "more", 24 px.
  moreVertical('more_vertical', 24, 24, 24),

  /// Photo shutter, 60 px.
  shutterPhoto('shutter_photo', 60, 60, 60),

  /// Recording shutter, 60 px.
  shutterRecording('shutter_recording', 60, 60, 60);

  const StoryIcons(
    this.asset,
    this.box,
    this.svgWidth,
    this.svgHeight, {
    this.bleed = EdgeInsets.zero,
    this.shadow = false,
  });

  /// File name in `assets/icons/`, without extension.
  final String asset;

  /// Side of the square layout box in the design.
  final double box;

  /// The SVG's own width.
  final double svgWidth;

  /// The SVG's own height.
  final double svgHeight;

  /// How far the SVG extends past [box] on each side.
  final EdgeInsets bleed;

  /// Whether the design gives the icon a soft drop shadow (black 40%, blur
  /// 2.5). The SVGs describe it with a filter that `flutter_svg` does not
  /// render, so [StoryIcon] draws it.
  final bool shadow;

  /// Asset key inside this package.
  String get assetKey => 'assets/icons/$asset.svg';
}

/// Draws one of the design's [StoryIcons].
///
/// [color] recolours a single-colour icon (all but the shutters); `null`
/// keeps the design's colours. The widget takes the icon's layout box size;
/// its bleed is painted outside that box.
///
/// The design's drop shadow is rasterised once per icon and pixel ratio and
/// then drawn as a plain image, so no blur is computed per frame (a live
/// blur on every icon starved the GPU during video export).
class StoryIcon extends StatelessWidget {
  /// Creates an icon.
  const StoryIcon(this.icon, {this.color, super.key});

  /// Which icon.
  final StoryIcons icon;

  /// Recolouring, or `null` for the design's colours.
  final Color? color;

  static const Color _shadowColor = Color(0x66000000);
  static const double _shadowSigma = 2.5;

  /// The design's icon drop shadow, for Material icons shown next to
  /// [StoryIcon]s.
  static const Shadow designShadow = Shadow(
    color: _shadowColor,
    blurRadius: _shadowSigma * 2,
  );
  static const String _package = 'story_creator_kit';

  @override
  Widget build(BuildContext context) {
    final tint = color;
    final svg = SvgPicture.asset(
      icon.assetKey,
      package: _package,
      width: icon.svgWidth,
      height: icon.svgHeight,
      colorFilter: tint == null
          ? null
          : ColorFilter.mode(tint, BlendMode.srcIn),
      excludeFromSemantics: true,
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: icon.box,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (icon.shadow)
              Positioned(
                left: -icon.bleed.left - _ShadowCache.margin,
                top: -icon.bleed.top - _ShadowCache.margin,
                width: icon.svgWidth + _ShadowCache.margin * 2,
                height: icon.svgHeight + _ShadowCache.margin * 2,
                child: _IconShadow(icon: icon),
              ),
            Positioned(
              left: -icon.bleed.left,
              top: -icon.bleed.top,
              width: icon.svgWidth,
              height: icon.svgHeight,
              child: svg,
            ),
          ],
        ),
      ),
    );
  }
}

/// The pre-rendered shadow of one icon.
class _IconShadow extends StatefulWidget {
  const _IconShadow({required this.icon});

  final StoryIcons icon;

  @override
  State<_IconShadow> createState() => _IconShadowState();
}

class _IconShadowState extends State<_IconShadow> {
  ui.Image? _image;
  double? _ratio;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ratio = MediaQuery.devicePixelRatioOf(context);
    if (ratio != _ratio) {
      _ratio = ratio;
      final cached = _ShadowCache.peek(widget.icon, ratio);
      if (cached != null) {
        _image = cached;
      } else {
        _ShadowCache.load(widget.icon, ratio).then((image) {
          if (mounted && _ratio == ratio) {
            setState(() => _image = image);
          }
        }, onError: (Object _) {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return const SizedBox.shrink();
    }
    return RawImage(image: image, scale: _ratio ?? 1, fit: BoxFit.fill);
  }
}

/// Shadow bitmaps, rendered once per icon and pixel ratio for the app's
/// lifetime (a handful of small images).
abstract final class _ShadowCache {
  /// Room around the SVG for the blur to fade out (3 sigma).
  static const double margin = StoryIcon._shadowSigma * 3;

  static final Map<String, ui.Image> _images = {};
  static final Map<String, Future<ui.Image>> _pending = {};

  static String _key(StoryIcons icon, double ratio) => '${icon.name}@$ratio';

  static ui.Image? peek(StoryIcons icon, double ratio) =>
      _images[_key(icon, ratio)];

  static Future<ui.Image> load(StoryIcons icon, double ratio) {
    final key = _key(icon, ratio);
    return _pending[key] ??= _render(icon, ratio).then((image) {
      _images[key] = image;
      return image;
    });
  }

  static Future<ui.Image> _render(StoryIcons icon, double ratio) async {
    final info = await vg.loadPicture(
      SvgAssetLoader(icon.assetKey, packageName: StoryIcon._package),
      null,
    );
    try {
      final width = icon.svgWidth + margin * 2;
      final height = icon.svgHeight + margin * 2;
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..scale(ratio)
        ..saveLayer(
          Rect.fromLTWH(0, 0, width, height),
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: StoryIcon._shadowSigma,
              sigmaY: StoryIcon._shadowSigma,
              tileMode: TileMode.decal,
            ),
        )
        ..saveLayer(
          Rect.fromLTWH(0, 0, width, height),
          Paint()
            ..colorFilter = const ColorFilter.mode(
              StoryIcon._shadowColor,
              BlendMode.srcIn,
            ),
        )
        ..translate(margin, margin)
        ..scale(
          icon.svgWidth / info.size.width,
          icon.svgHeight / info.size.height,
        )
        ..drawPicture(info.picture)
        ..restore()
        ..restore();
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(
          (width * ratio).ceil(),
          (height * ratio).ceil(),
        );
      } finally {
        picture.dispose();
      }
    } finally {
      info.picture.dispose();
    }
  }
}
