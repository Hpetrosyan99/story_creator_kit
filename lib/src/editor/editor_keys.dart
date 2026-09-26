import 'package:flutter/foundation.dart';

/// Keys of the editor's controls (tests and integration tests).
abstract final class EditorKeys {
  /// The chevron that shows or hides the extra tools.
  static const moreTools = ValueKey<String>('story_editor_more_tools');

  /// The gallery thumbnail that replaces the media.
  static const replaceMedia = ValueKey<String>('story_editor_replace_media');

  /// The selected-music chip.
  static const musicChip = ValueKey<String>('story_editor_music_chip');
}
