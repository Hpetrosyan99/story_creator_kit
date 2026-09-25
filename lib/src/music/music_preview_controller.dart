import 'package:flutter/foundation.dart';

import '../api/errors/story_exception.dart';
import '../api/music/music_models.dart';
import '../api/music/story_music_provider.dart';
import '../services/audio/music_session.dart';

/// Longest preview played from a row of the picker.
const Duration kMusicPreviewLength = Duration(seconds: 30);

/// Plays one track of the picker list at a time, from its beginning for at
/// most [maxLength].
///
/// The source comes from `StoryMusicProvider.resolve` and is handed to the
/// session as-is, so a URL source is streamed.
class MusicPreviewController extends ChangeNotifier {
  /// Creates a controller playing through [session].
  MusicPreviewController({
    required this.provider,
    required this.session,
    this.maxLength = kMusicPreviewLength,
  }) {
    session.playing.addListener(_onPlayingChanged);
  }

  /// The catalog.
  final StoryMusicProvider provider;

  /// The player; owned by the caller.
  final MusicSession session;

  /// Longest preview.
  final Duration maxLength;

  String? _playingId;
  int _token = 0;
  bool _switching = false;
  bool _disposed = false;

  /// Id of the track being previewed, if any.
  String? get playingId => _playingId;

  /// Whether [track] is being previewed.
  bool isPlaying(MusicTrack track) => _playingId == track.id;

  /// Starts previewing [track], or stops when it is already playing.
  ///
  /// Throws `StoryException(musicUnavailable)` when the track cannot be
  /// played. A request replaced by a newer one completes quietly.
  Future<void> toggle(MusicTrack track) async {
    if (_playingId == track.id) {
      await stop();
      return;
    }
    final token = ++_token;
    _playingId = track.id;
    _switching = true;
    _notify();
    try {
      final source = await provider.resolve(track);
      if (token != _token) {
        return;
      }
      final loaded = await session.load(source);
      if (token != _token) {
        return;
      }
      final length = loaded != null && loaded > Duration.zero
          ? loaded
          : track.duration;
      await session.playSegment(
        Duration.zero,
        length <= Duration.zero || length > maxLength ? maxLength : length,
        loop: false,
      );
    } on Object catch (e, s) {
      if (token != _token) {
        // A newer preview replaced this one; its failure is irrelevant.
        return;
      }
      _playingId = null;
      _notify();
      if (e is StoryException) {
        rethrow;
      }
      throw StoryException(
        StoryErrorCode.musicUnavailable,
        'Preview of track ${track.id} failed.',
        e,
        s,
      );
    } finally {
      if (token == _token) {
        _switching = false;
      }
    }
  }

  /// Stops any preview.
  Future<void> stop() async {
    _token++;
    _switching = false;
    if (_playingId != null) {
      _playingId = null;
      _notify();
    }
    await session.stop();
  }

  void _onPlayingChanged() {
    if (_switching || _playingId == null || session.playing.value) {
      return;
    }
    _playingId = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    session.playing.removeListener(_onPlayingChanged);
    super.dispose();
  }
}
