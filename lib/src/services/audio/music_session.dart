import 'package:flutter/foundation.dart';

import '../../api/music/music_models.dart';

/// Plays music for preview in the picker, the segment selector and the
/// editor. One instance per screen that plays music.
abstract class MusicSession {
  /// Playback position within the loaded track.
  ValueListenable<Duration> get position;

  /// Whether audio is playing.
  ValueListenable<bool> get playing;

  /// Loads [source]; returns the track length when known. Throws
  /// `StoryException(musicUnavailable)`.
  Future<Duration?> load(MusicSource source);

  /// Plays from [start] for [length], looping when [loop] is set.
  Future<void> playSegment(Duration start, Duration length, {bool loop = true});

  /// Seeks within the loaded track.
  Future<void> seek(Duration position);

  /// Sets the volume, 0–1.
  Future<void> setVolume(double volume);

  /// Pauses playback.
  Future<void> pause();

  /// Resumes playback.
  Future<void> resume();

  /// Stops and unloads.
  Future<void> stop();

  /// Releases the player.
  Future<void> dispose();
}
