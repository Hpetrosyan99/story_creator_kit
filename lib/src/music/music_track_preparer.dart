import 'package:flutter/foundation.dart';

import '../api/errors/story_exception.dart';
import '../api/music/music_models.dart';
import '../api/music/story_music_provider.dart';
import '../services/audio/music_session.dart';
import '../services/media/media_inspector.dart';
import 'music_file_cache.dart';

/// A track ready for the segment selector and the exporter.
@immutable
class PreparedMusicTrack {
  /// Creates a prepared track.
  const PreparedMusicTrack({
    required this.track,
    required this.localPath,
    required this.duration,
    required this.peaks,
  });

  /// The track.
  final MusicTrack track;

  /// Local audio file.
  final String localPath;

  /// Length of the local file, or `MusicTrack.duration` when the player does
  /// not report one.
  final Duration duration;

  /// Waveform peaks (0–1); empty when unavailable.
  final List<double> peaks;
}

/// Resolves a picked track to a local file, loads it into the session (which
/// reports its real length) and reads its waveform.
class MusicTrackPreparer {
  /// Creates a preparer.
  MusicTrackPreparer({
    required this.provider,
    required this.cache,
    required this.session,
    required this.inspector,
    this.waveformBuckets = 120,
    this.onNonFatalError,
  });

  /// The catalog.
  final StoryMusicProvider provider;

  /// Local file cache of the story session.
  final MusicFileCache cache;

  /// The player; left loaded with the local file.
  final MusicSession session;

  /// Extracts waveform peaks when the track carries none.
  final MediaInspector inspector;

  /// Number of waveform peaks to extract.
  final int waveformBuckets;

  /// Receives failures that do not stop the selection (a missing waveform).
  final void Function(StoryException error)? onNonFatalError;

  /// Prepares [track].
  ///
  /// Throws `StoryException(musicUnavailable)` on failure and
  /// [MusicCancelledException] when [cancel] fires.
  Future<PreparedMusicTrack> prepare(
    MusicTrack track, {
    MusicProgressCallback? onProgress,
    MusicCancelToken? cancel,
  }) async {
    try {
      var path = cache.cachedPath(track.id);
      if (path == null) {
        final source = await provider.resolve(track);
        cancel?.throwIfCancelled();
        path = await cache.localPath(
          track,
          source,
          onProgress: onProgress,
          cancel: cancel,
        );
      } else {
        onProgress?.call(1);
      }
      cancel?.throwIfCancelled();
      final loaded = await session.load(MusicFileSource(path));
      cancel?.throwIfCancelled();
      final peaks = track.waveform ?? await _waveform(path);
      cancel?.throwIfCancelled();
      return PreparedMusicTrack(
        track: track,
        localPath: path,
        duration: loaded != null && loaded > Duration.zero
            ? loaded
            : track.duration,
        peaks: peaks,
      );
    } on MusicCancelledException {
      rethrow;
    } on StoryException catch (e) {
      if (e.code == StoryErrorCode.musicUnavailable) {
        rethrow;
      }
      throw StoryException(
        StoryErrorCode.musicUnavailable,
        'Track ${track.id} could not be prepared.',
        e,
        e.stackTrace,
      );
    } on Object catch (e, s) {
      throw StoryException(
        StoryErrorCode.musicUnavailable,
        'Track ${track.id} could not be prepared.',
        e,
        s,
      );
    }
  }

  Future<List<double>> _waveform(String path) async {
    try {
      return await inspector.waveform(path, buckets: waveformBuckets);
    } on Object catch (e, s) {
      onNonFatalError?.call(
        e is StoryException
            ? e
            : StoryException(
                StoryErrorCode.musicUnavailable,
                'Waveform extraction failed.',
                e,
                s,
              ),
      );
      return const [];
    }
  }
}
