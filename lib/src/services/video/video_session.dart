import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../model/trim_range.dart';

/// Snapshot of a video player.
@immutable
class VideoPlaybackState {
  /// Creates a state.
  const VideoPlaybackState({
    this.initialized = false,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.size = Size.zero,
    this.error,
  });

  /// Whether the video is ready.
  final bool initialized;

  /// Whether it is playing.
  final bool playing;

  /// Current position in the source.
  final Duration position;

  /// Source length.
  final Duration duration;

  /// Display size of the video.
  final Size size;

  /// Playback error, if any (a `StoryException`).
  final Object? error;

  /// Returns a copy with the given values replaced.
  VideoPlaybackState copyWith({
    bool? initialized,
    bool? playing,
    Duration? position,
    Duration? duration,
    Size? size,
    Object? error,
  }) => VideoPlaybackState(
    initialized: initialized ?? this.initialized,
    playing: playing ?? this.playing,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    size: size ?? this.size,
    error: error ?? this.error,
  );
}

/// Plays the source video in the editor.
abstract class VideoSession {
  /// Player state.
  ValueListenable<VideoPlaybackState> get state;

  /// Opens a local file. Throws `StoryException(mediaUnsupported)`.
  Future<void> open(String path);

  /// The video frame, sized to the video's aspect ratio.
  Widget buildView();

  /// Starts playback.
  Future<void> play();

  /// Pauses playback.
  Future<void> pause();

  /// Seeks to [position].
  Future<void> seekTo(Duration position);

  /// Sets the audio volume, 0–1.
  Future<void> setVolume(double volume);

  /// Loops playback within [range] (whole video when `null`).
  Future<void> setPlaybackRange(TrimRange? range);

  /// Releases the player.
  Future<void> dispose();
}
