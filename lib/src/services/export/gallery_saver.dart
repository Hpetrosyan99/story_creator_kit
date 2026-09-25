import '../../api/result/story_result.dart';

/// Writes finished stories to the device gallery.
abstract class GallerySaver {
  /// Saves [path]; prompts for add-only access if needed. Throws
  /// `StoryException(saveToGalleryFailed | photosPermissionDenied)`.
  Future<void> save(String path, StoryMediaType type, {String? album});
}
