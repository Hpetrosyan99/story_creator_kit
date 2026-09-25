import 'package:flutter/foundation.dart';

import '../events/story_event.dart';
import '../music/story_music_provider.dart';
import '../strings/story_creator_strings.dart';
import '../theme/story_creator_theme.dart';
import 'capture_options.dart';
import 'editor_options.dart';
import 'media_constraints.dart';
import 'output_options.dart';

/// Everything the host can configure.
@immutable
class StoryCreatorConfig {
  /// Creates a configuration. Every value has a default.
  const StoryCreatorConfig({
    this.theme = const StoryCreatorTheme(),
    this.strings = const StoryCreatorStrings(),
    this.capture = const CaptureOptions(),
    this.constraints = const MediaConstraints(),
    this.editor = const EditorOptions(),
    this.output = const OutputOptions(),
    this.musicProvider,
    this.onEvent,
  });

  /// Colours and text styles.
  final StoryCreatorTheme theme;

  /// User-visible strings.
  final StoryCreatorStrings strings;

  /// Camera and gallery options.
  final CaptureOptions capture;

  /// Duration and type limits.
  final MediaConstraints constraints;

  /// Editor tools and choices.
  final EditorOptions editor;

  /// Export settings.
  final OutputOptions output;

  /// Music catalog. The music tool is hidden when `null`.
  final StoryMusicProvider? musicProvider;

  /// Receives analytics and error events.
  final StoryEventCallback? onEvent;

  /// Whether the music tool is available.
  bool get musicEnabled => editor.enableMusic && musicProvider != null;
}
