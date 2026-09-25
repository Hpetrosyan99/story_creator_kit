import 'package:flutter/widgets.dart';

import '../api/config/story_creator_config.dart';
import '../api/errors/story_exception.dart';
import '../api/events/story_event.dart';
import '../api/strings/story_creator_strings.dart';
import '../api/theme/story_creator_theme.dart';
import '../render/painters/story_paint_resources.dart';
import '../services/story_services.dart';
import 'session_files.dart';

/// Gives every widget of the story creator access to the configuration,
/// services and session.
class StoryScope extends InheritedWidget {
  /// Creates the scope.
  const StoryScope({
    required this.config,
    required this.services,
    required this.session,
    required this.resources,
    required super.child,
    super.key,
  });

  /// Host configuration.
  final StoryCreatorConfig config;

  /// Platform services.
  final StoryServices services;

  /// Session working directory.
  final SessionFiles session;

  /// Fonts, stickers and filters for painting.
  final StoryPaintResources resources;

  /// Shortcut to the theme.
  StoryCreatorTheme get theme => config.theme;

  /// Shortcut to the strings.
  StoryCreatorStrings get strings => config.strings;

  /// Reports [event] to the host; never throws.
  void report(StoryEvent event) {
    try {
      config.onEvent?.call(event);
    } on Object catch (e, s) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: s,
          library: 'story_creator_kit',
          context: ErrorDescription('while calling StoryCreatorConfig.onEvent'),
        ),
      );
    }
  }

  /// Reports a handled error.
  void reportError(StoryException error, [StackTrace? stackTrace]) => report(
    StoryEvent(
      StoryEventType.error,
      properties: {'code': error.code.name},
      error: error,
      stackTrace: stackTrace ?? error.stackTrace,
    ),
  );

  /// The nearest scope. Throws when there is none.
  static StoryScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<StoryScope>();
    assert(scope != null, 'No StoryScope above this widget.');
    return scope!;
  }

  /// The nearest scope without registering a dependency (for callbacks).
  static StoryScope read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<StoryScope>();
    assert(scope != null, 'No StoryScope above this widget.');
    return scope!;
  }

  @override
  bool updateShouldNotify(StoryScope oldWidget) =>
      config != oldWidget.config ||
      services != oldWidget.services ||
      session != oldWidget.session ||
      resources != oldWidget.resources;
}
