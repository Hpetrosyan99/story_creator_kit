import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/errors/story_exception.dart';
import '../../api/result/story_result.dart';
import 'gallery_source.dart';

/// [GallerySource] that only offers the system photo picker (Android Photo
/// Picker, iOS PHPicker) through `image_picker`.
///
/// Needs no photo library permission, so [checkAccess] and [requestAccess]
/// always report [GalleryAccess.granted]. There is no in-app grid:
/// [supportsGrid] is `false` and the grid methods throw.
class SystemPickerGallerySource implements GallerySource {
  /// Creates the source.
  SystemPickerGallerySource();

  final ImagePicker _picker = ImagePicker();

  static const Set<String> _videoExtensions = {
    'mp4',
    'm4v',
    'mov',
    '3gp',
    '3gpp',
    'webm',
    'mkv',
    'avi',
  };

  @override
  bool get supportsGrid => false;

  @override
  Future<GalleryAccess> checkAccess() async => GalleryAccess.granted;

  @override
  Future<GalleryAccess> requestAccess() async => GalleryAccess.granted;

  @override
  Future<void> manageLimitedSelection() async {}

  @override
  Future<List<GalleryAlbum>> albums({
    required bool photos,
    required bool videos,
  }) async => const [];

  @override
  Future<List<GalleryAsset>> assets(
    GalleryAlbum album, {
    required int page,
    int pageSize = 60,
  }) async => const [];

  @override
  ImageProvider thumbnail(GalleryAsset asset, {int size = 256}) =>
      throw const StoryException(
        StoryErrorCode.mediaUnavailable,
        'The system picker source has no grid thumbnails.',
      );

  @override
  Future<PickedMedia> resolve(
    GalleryAsset asset, {
    void Function(double progress)? onProgress,
  }) async => throw const StoryException(
    StoryErrorCode.mediaUnavailable,
    'The system picker source has no grid assets.',
  );

  @override
  Future<PickedMedia?> pickWithSystemPicker({
    required bool photos,
    required bool videos,
  }) async {
    final XFile? file;
    try {
      if (photos && videos) {
        // requestFullMetadata: false keeps PHPicker permission-free on iOS.
        file = await _picker.pickMedia(requestFullMetadata: false);
      } else if (videos) {
        file = await _picker.pickVideo(source: ImageSource.gallery);
      } else {
        file = await _picker.pickImage(
          source: ImageSource.gallery,
          requestFullMetadata: false,
        );
      }
    } on PlatformException catch (e, s) {
      throw StoryException(
        e.code == 'photo_access_denied'
            ? StoryErrorCode.photosPermissionDenied
            : StoryErrorCode.mediaUnavailable,
        'System picker failed: ${e.code} ${e.message ?? ''}'.trim(),
        e,
        s,
      );
    }
    if (file == null) {
      return null;
    }
    final type = typeOf(file.path, file.mimeType);
    if (type == StoryMediaType.video && !videos ||
        type == StoryMediaType.photo && !photos) {
      throw StoryException(
        StoryErrorCode.mediaUnsupported,
        'Picked a ${type.name}, which is not allowed.',
      );
    }
    return PickedMedia(path: file.path, type: type, mimeType: file.mimeType);
  }

  /// Photo or video from a MIME type, falling back to the file extension.
  static StoryMediaType typeOf(String path, String? mimeType) {
    if (mimeType != null) {
      if (mimeType.startsWith('video/')) {
        return StoryMediaType.video;
      }
      if (mimeType.startsWith('image/')) {
        return StoryMediaType.photo;
      }
    }
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    return _videoExtensions.contains(ext)
        ? StoryMediaType.video
        : StoryMediaType.photo;
  }

  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<void> dispose() async {}
}
