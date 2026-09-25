import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../api/music/music_models.dart';
import '../../model/music_selection.dart';
import '../../model/story_document.dart';
import '../../model/story_media.dart';
import '../../model/trim_range.dart';
import '../../services/audio/music_session.dart';
import '../../services/story_services.dart';
import '../../services/video/video_session.dart';

/// Which part of playback failed.
enum PlaybackFailure {
  /// The video could not be opened or played.
  video,

  /// The music could not be loaded or played.
  music,
}

/// Plays the editor's video and music together.
///
/// The video loops within the trim range; the music segment restarts at
/// `music.start` whenever the video loops back, and both pause together.
/// For photos the music loops on its own. Session calls are serialised.
class EditorPlayback extends ChangeNotifier {
  /// Creates playback for [media].
  EditorPlayback({
    required this.services,
    required this.media,
    required this.onError,
  });

  /// Creates the sessions.
  final StoryServices services;

  /// The source media.
  final StoryMedia media;

  /// A session failed.
  final void Function(
    PlaybackFailure failure,
    Object error,
    StackTrace stackTrace,
  )
  onError;

  /// Position jump backwards treated as a loop.
  static const Duration loopJump = Duration(milliseconds: 300);

  VideoSession? _video;
  MusicSession? _music;
  bool _videoReady = false;
  bool _active = true;
  bool _userPaused = false;
  bool _scrubbing = false;
  bool _disposed = false;
  StoryDocument? _document;
  Future<void> _queue = Future.value();

  bool _rangeApplied = false;
  TrimRange? _appliedRange;
  double? _appliedVolume;
  (String?, Duration, Duration)? _musicKey;
  double? _musicVolume;
  bool _musicPlaying = false;
  Duration _lastPosition = Duration.zero;

  /// The video session once opened.
  VideoSession? get video => _videoReady ? _video : null;

  /// Whether playback should be running.
  bool get playing => _active && !_userPaused && !_scrubbing;

  /// Whether the user paused playback.
  bool get userPaused => _userPaused;

  /// Opens the video (if any) and starts playback for [document].
  Future<void> start(StoryDocument document) {
    _document = document;
    return _enqueue(() async {
      if (media.isVideo) {
        final session = _video = services.createVideoSession();
        session.state.addListener(_onVideoState);
        try {
          await session.open(media.path);
        } on Object catch (e, s) {
          onError(PlaybackFailure.video, e, s);
          return;
        }
        if (_disposed) {
          return;
        }
        _videoReady = true;
        notifyListeners();
        await _applyVideo();
      }
      await _applyMusic();
      await _applyPlayState();
    });
  }

  /// Applies trim, volumes and music of [document].
  Future<void> update(StoryDocument document) {
    _document = document;
    return _enqueue(() async {
      await _applyVideo();
      await _applyMusic();
    });
  }

  /// `false` while the editor is covered: pauses everything.
  Future<void> setActive({required bool active}) {
    if (_active == active) {
      return Future.value();
    }
    _active = active;
    notifyListeners();
    return _enqueue(_applyPlayState);
  }

  /// Toggles the user pause.
  Future<void> togglePause() {
    _userPaused = !_userPaused;
    notifyListeners();
    return _enqueue(_applyPlayState);
  }

  /// Shows [position] while a trim handle is dragged (playback paused).
  Future<void> scrub(Duration position) {
    final wasScrubbing = _scrubbing;
    _scrubbing = true;
    return _enqueue(() async {
      if (!wasScrubbing) {
        await _applyPlayState();
      }
      await _video?.seekTo(position);
    });
  }

  /// Ends scrubbing and resumes looping in the new range.
  Future<void> endScrub(StoryDocument document) {
    _scrubbing = false;
    _document = document;
    return _enqueue(() async {
      await _applyVideo();
      await _applyMusic();
      await _applyPlayState();
    });
  }

  Future<void> _enqueue(Future<void> Function() op) {
    return _queue = _queue
        .then((_) async {
          if (_disposed) {
            return;
          }
          await op();
        })
        .catchError((Object e, StackTrace s) {
          onError(
            media.isVideo ? PlaybackFailure.video : PlaybackFailure.music,
            e,
            s,
          );
        });
  }

  double get _effectiveVolume =>
      media.hasAudio ? (_document?.originalVolume ?? 1) : 0;

  Future<void> _applyVideo() async {
    final session = video;
    final document = _document;
    if (session == null || document == null) {
      return;
    }
    if (!_scrubbing && (!_rangeApplied || document.trim != _appliedRange)) {
      _rangeApplied = true;
      _appliedRange = document.trim;
      await session.setPlaybackRange(document.trim);
      await session.seekTo(document.trim?.start ?? Duration.zero);
      _lastPosition = document.trim?.start ?? Duration.zero;
      if (_musicPlaying) {
        await _restartMusic();
      }
    }
    final volume = _effectiveVolume;
    if (volume != _appliedVolume) {
      _appliedVolume = volume;
      await session.setVolume(volume);
    }
  }

  Future<void> _applyMusic() async {
    final music = _document?.music;
    final path = music?.localPath;
    if (music == null || path == null) {
      if (_musicKey != null) {
        _musicKey = null;
        _musicPlaying = false;
        await _music?.stop();
      }
      return;
    }
    final key = (path, music.start, music.duration);
    final session = _music ??= services.createMusicSession();
    if (key != _musicKey && !_scrubbing) {
      _musicKey = key;
      _musicPlaying = false;
      try {
        await session.load(MusicFileSource(path));
      } on Object catch (e, s) {
        _musicKey = null;
        onError(PlaybackFailure.music, e, s);
        return;
      }
      if (playing) {
        await _startMusic(music);
      }
    }
    if (music.volume != _musicVolume) {
      _musicVolume = music.volume;
      await session.setVolume(music.volume);
    }
  }

  Future<void> _startMusic(MusicSelection music) async {
    final session = _music;
    if (session == null || _musicKey == null) {
      return;
    }
    _musicPlaying = true;
    await session.playSegment(music.start, music.duration);
  }

  Future<void> _restartMusic() async {
    final music = _document?.music;
    if (music != null) {
      await _startMusic(music);
    }
  }

  Future<void> _applyPlayState() async {
    final session = video;
    if (playing) {
      if (session != null) {
        final start = _document?.trim?.start ?? Duration.zero;
        final position = session.state.value.position;
        final end = _document?.trim?.end;
        if (position < start || (end != null && position > end)) {
          await session.seekTo(start);
        }
        await session.play();
        // Keep music aligned with the video: restart both at the loop start.
        if (_musicKey != null) {
          await session.seekTo(start);
          _lastPosition = start;
          await _restartMusic();
        }
      } else if (_musicKey != null) {
        if (_musicPlaying) {
          await _music?.resume();
        } else {
          await _restartMusic();
        }
      }
    } else {
      await session?.pause();
      if (_musicPlaying) {
        await _music?.pause();
      }
    }
  }

  void _onVideoState() {
    final session = _video;
    if (session == null || _disposed) {
      return;
    }
    final state = session.state.value;
    final position = state.position;
    final looped = position + loopJump < _lastPosition;
    _lastPosition = position;
    if (looped && playing && _musicKey != null) {
      unawaited(_enqueue(_restartMusic));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final video = _video;
    final music = _music;
    video?.state.removeListener(_onVideoState);
    unawaited(
      _queue.whenComplete(() async {
        await video?.dispose();
        await music?.dispose();
      }),
    );
    super.dispose();
  }
}
