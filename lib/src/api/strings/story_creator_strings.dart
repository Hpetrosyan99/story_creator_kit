import 'package:flutter/foundation.dart';

import 'camera_strings.dart';
import 'common_strings.dart';
import 'editor_strings.dart';
import 'export_strings.dart';
import 'music_strings.dart';

export 'camera_strings.dart';
export 'common_strings.dart';
export 'editor_strings.dart';
export 'export_strings.dart';
export 'music_strings.dart';

/// Every user-visible string of the story creator, including semantics labels.
///
/// Defaults are English. To localise, pass instances with your own values, for
/// example `StoryCreatorStrings(camera: CameraStrings(takePhoto: 'Foto'))`,
/// built from your app's localisation system.
@immutable
class StoryCreatorStrings {
  /// Creates the string set. Each group defaults to English.
  const StoryCreatorStrings({
    this.common = const CommonStrings(),
    this.camera = const CameraStrings(),
    this.editor = const EditorStrings(),
    this.music = const MusicStrings(),
    this.export = const ExportStrings(),
  });

  /// Strings shared by several screens (close, done, retry…).
  final CommonStrings common;

  /// Camera, gallery and permission strings.
  final CameraStrings camera;

  /// Editor, text, drawing, sticker, filter and trim strings.
  final EditorStrings editor;

  /// Music picker and segment selector strings.
  final MusicStrings music;

  /// Export, preview and save strings.
  final ExportStrings export;
}
