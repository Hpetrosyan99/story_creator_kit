import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/errors/story_exception.dart';
import '../../core/story_scope.dart';
import '../../services/gallery/gallery_source.dart';
import '../camera_keys.dart';

/// Rounded thumbnail (60 px, radius 16, 1 px white border) of the newest
/// gallery item that opens the gallery.
///
/// Shows a generic icon when there is no grid (system picker), no access
/// yet (it never prompts) or the library is empty. Refreshes on library
/// changes.
class GalleryShortcut extends StatefulWidget {
  /// Creates the shortcut.
  const GalleryShortcut({required this.onPressed, super.key});

  /// Opens the gallery.
  final VoidCallback? onPressed;

  /// Side of the thumbnail.
  static const double size = 60;

  @override
  State<GalleryShortcut> createState() => _GalleryShortcutState();
}

class _GalleryShortcutState extends State<GalleryShortcut> {
  GallerySource? _source;
  StreamSubscription<void>? _changes;
  ImageProvider? _thumbnail;
  int _loads = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final source = StoryScope.of(context).services.gallery;
    if (!identical(source, _source)) {
      _source = source;
      unawaited(_changes?.cancel());
      _changes = source.supportsGrid
          ? source.changes.listen((_) => unawaited(_load()))
          : null;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final source = _source;
    if (source == null || !source.supportsGrid) {
      return;
    }
    final load = ++_loads;
    final constraints = StoryScope.read(context).config.constraints;
    ImageProvider? thumbnail;
    try {
      final access = await source.checkAccess();
      if (access == GalleryAccess.granted || access == GalleryAccess.limited) {
        final albums = await source.albums(
          photos: constraints.allowPhotos,
          videos: constraints.allowVideos,
        );
        if (albums.isNotEmpty) {
          final all = albums.firstWhere(
            (a) => a.isAll,
            orElse: () => albums.first,
          );
          final latest = await source.assets(all, page: 0, pageSize: 1);
          if (latest.isNotEmpty) {
            thumbnail = source.thumbnail(latest.first, size: 180);
          }
        }
      }
    } on StoryException {
      // The shortcut falls back to the generic gallery icon; the gallery
      // sheet shows and reports real errors when opened.
      thumbnail = null;
    }
    if (mounted && load == _loads) {
      setState(() => _thumbnail = thumbnail);
    }
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final thumbnail = _thumbnail;
    final radius = BorderRadius.circular(theme.cornerRadius);
    final placeholder = ColoredBox(
      color: theme.surfaceVariant,
      child: Center(
        child: Icon(
          Icons.photo_library_outlined,
          size: 24,
          color: theme.onSurface,
        ),
      ),
    );
    return Semantics(
      key: CameraKeys.gallery,
      button: true,
      enabled: widget.onPressed != null,
      label: scope.strings.camera.openGallery,
      excludeSemantics: true,
      onTap: widget.onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: SizedBox.square(
          dimension: GalleryShortcut.size,
          child: ClipRRect(
            borderRadius: radius,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: theme.onSurface),
              ),
              child: thumbnail == null
                  ? placeholder
                  : Image(
                      image: thumbnail,
                      fit: BoxFit.cover,
                      width: GalleryShortcut.size,
                      height: GalleryShortcut.size,
                      gaplessPlayback: true,
                      errorBuilder: (context, _, _) => placeholder,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
