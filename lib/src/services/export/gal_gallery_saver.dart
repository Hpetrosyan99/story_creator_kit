import 'package:gal/gal.dart';

import '../../api/errors/story_exception.dart';
import '../../api/result/story_result.dart';
import 'gallery_saver.dart';

/// [GallerySaver] using the `gal` package (add-only access on iOS, MediaStore
/// on Android).
class GalGallerySaver implements GallerySaver {
  /// Creates the saver.
  GalGallerySaver();

  @override
  Future<void> save(String path, StoryMediaType type, {String? album}) async {
    final toAlbum = album != null;
    try {
      if (!await Gal.hasAccess(toAlbum: toAlbum) &&
          !await Gal.requestAccess(toAlbum: toAlbum)) {
        throw const StoryException(
          StoryErrorCode.photosPermissionDenied,
          'Gallery access was denied.',
        );
      }
      switch (type) {
        case StoryMediaType.photo:
          await Gal.putImage(path, album: album);
        case StoryMediaType.video:
          await Gal.putVideo(path, album: album);
      }
    } on StoryException {
      rethrow;
    } on GalException catch (e, s) {
      throw StoryException(
        e.type == GalExceptionType.accessDenied
            ? StoryErrorCode.photosPermissionDenied
            : StoryErrorCode.saveToGalleryFailed,
        'Saving to the gallery failed: ${e.type.name}',
        e,
        s,
      );
    } on Object catch (e, s) {
      throw StoryException(
        StoryErrorCode.saveToGalleryFailed,
        'Saving to the gallery failed.',
        e,
        s,
      );
    }
  }
}
