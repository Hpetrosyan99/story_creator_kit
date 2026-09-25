import 'package:flutter/foundation.dart';

import '../errors/story_exception.dart';

/// What happened, for analytics and issue tracking.
enum StoryEventType {
  /// The creator opened.
  opened,

  /// A photo was taken or a video recorded.
  captured,

  /// Media was picked from the gallery.
  mediaPicked,

  /// An editor tool was opened. `properties['tool']` names it.
  toolOpened,

  /// Export started.
  exportStarted,

  /// Export finished.
  exportCompleted,

  /// Export was cancelled.
  exportCancelled,

  /// The story was saved to the gallery.
  savedToGallery,

  /// The user confirmed the story.
  completed,

  /// The user left without a story.
  cancelled,

  /// A handled error. [StoryEvent.error] is set.
  error,
}

/// Callback receiving [StoryEvent]s.
typedef StoryEventCallback = void Function(StoryEvent event);

/// An event reported through `StoryCreatorConfig.onEvent`.
@immutable
class StoryEvent {
  /// Creates an event.
  const StoryEvent(
    this.type, {
    this.properties = const {},
    this.error,
    this.stackTrace,
  });

  /// Event type.
  final StoryEventType type;

  /// Extra details; values are strings, numbers or booleans.
  final Map<String, Object> properties;

  /// The error, for [StoryEventType.error] and failures.
  final StoryException? error;

  /// Where [error] happened.
  final StackTrace? stackTrace;

  @override
  String toString() =>
      'StoryEvent(${type.name}, $properties'
      '${error == null ? '' : ', $error'})';
}
