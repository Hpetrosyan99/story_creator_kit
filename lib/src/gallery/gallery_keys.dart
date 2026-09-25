import 'package:flutter/foundation.dart';

/// Keys of the gallery sheet (tests and integration tests).
abstract final class GalleryKeys {
  /// The sheet.
  static const sheet = ValueKey<String>('story_gallery_sheet');

  /// Back button.
  static const back = ValueKey<String>('story_gallery_back');

  /// Album selector ("Recent ›").
  static const albumSelector = ValueKey<String>('story_gallery_album_selector');

  /// Album list.
  static const albumList = ValueKey<String>('story_gallery_album_list');

  /// Asset grid.
  static const grid = ValueKey<String>('story_gallery_grid');

  /// Camera tile (first grid tile).
  static const cameraTile = ValueKey<String>('story_gallery_camera_tile');

  /// Limited-access banner.
  static const limitedBanner = ValueKey<String>('story_gallery_limited_banner');

  /// "Manage" button of the limited-access banner.
  static const manage = ValueKey<String>('story_gallery_manage');

  /// Permission prompt.
  static const permissionPrompt = ValueKey<String>(
    'story_gallery_permission_prompt',
  );

  /// Notice toast.
  static const notice = ValueKey<String>('story_gallery_notice');

  /// Tile of the asset with [id].
  static ValueKey<String> tile(String id) =>
      ValueKey<String>('story_gallery_tile_$id');

  /// Album row of the album with [id].
  static ValueKey<String> album(String id) =>
      ValueKey<String>('story_gallery_album_$id');
}
