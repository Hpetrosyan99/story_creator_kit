import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../api/result/story_result.dart';

/// Photo library access state.
enum GalleryAccess {
  /// Full access.
  granted,

  /// Access to a user-selected subset.
  limited,

  /// Denied; can be requested again.
  denied,

  /// Denied permanently or restricted; only the settings app can change it.
  permanentlyDenied,
}

/// An album (collection) of the photo library.
@immutable
class GalleryAlbum {
  /// Creates an album.
  const GalleryAlbum({
    required this.id,
    required this.name,
    required this.count,
    this.isAll = false,
  });

  /// Platform id.
  final String id;

  /// Display name.
  final String name;

  /// Number of photos and videos.
  final int count;

  /// Whether this is the "all recent" album.
  final bool isAll;
}

/// A photo or video in the library.
@immutable
class GalleryAsset {
  /// Creates an asset.
  const GalleryAsset({
    required this.id,
    required this.type,
    required this.width,
    required this.height,
    this.duration,
  });

  /// Platform id.
  final String id;

  /// Photo or video.
  final StoryMediaType type;

  /// Pixel width.
  final int width;

  /// Pixel height.
  final int height;

  /// Video length.
  final Duration? duration;

  @override
  bool operator ==(Object other) => other is GalleryAsset && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A picked item available as a local file.
@immutable
class PickedMedia {
  /// Creates picked media.
  const PickedMedia({required this.path, required this.type, this.mimeType});

  /// Absolute path of a readable local file.
  final String path;

  /// Photo or video.
  final StoryMediaType type;

  /// MIME type, if known.
  final String? mimeType;
}

/// Access to existing photos and videos.
///
/// All methods throw `StoryException` on failure.
abstract class GallerySource {
  /// Whether this source can list assets for an in-app grid. `false` means
  /// only [pickWithSystemPicker] is available.
  bool get supportsGrid;

  /// Current access without prompting.
  Future<GalleryAccess> checkAccess();

  /// Prompts for access if needed.
  Future<GalleryAccess> requestAccess();

  /// Lets the user change the limited selection.
  Future<void> manageLimitedSelection();

  /// Albums, "all recent" first.
  Future<List<GalleryAlbum>> albums({
    required bool photos,
    required bool videos,
  });

  /// One page of an album's assets, newest first.
  Future<List<GalleryAsset>> assets(
    GalleryAlbum album, {
    required int page,
    int pageSize = 60,
  });

  /// Square thumbnail of [asset].
  ImageProvider thumbnail(GalleryAsset asset, {int size = 256});

  /// Makes [asset] available as a local file (downloading from iCloud when
  /// needed). [onProgress] receives 0–1.
  Future<PickedMedia> resolve(
    GalleryAsset asset, {
    void Function(double progress)? onProgress,
  });

  /// Opens the system picker; `null` when the user cancels.
  Future<PickedMedia?> pickWithSystemPicker({
    required bool photos,
    required bool videos,
  });

  /// Fires when the library changes (new photo, selection changed).
  Stream<void> get changes;

  /// Releases resources.
  Future<void> dispose();
}
