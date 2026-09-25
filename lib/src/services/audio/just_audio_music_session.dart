import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../api/errors/story_exception.dart';
import '../../api/music/music_models.dart';
import 'music_session.dart';

/// [MusicSession] backed by `just_audio`.
///
/// Segments play with `setClip` and `LoopMode.one`. The audio session is set
/// to playback that mixes with other audio, so music previews and the
/// editor's video (video_player) play together.
class JustAudioMusicSession implements MusicSession {
  /// Creates a session. [player] replaces the `AudioPlayer` (tests).
  JustAudioMusicSession({AudioPlayer? player})
    : _player = player ?? AudioPlayer(handleInterruptions: false) {
    _subscriptions
      ..add(
        _player.positionStream.listen((p) => _position.value = _clipStart + p),
      )
      ..add(
        _player.playerStateStream.listen(
          (s) => _playing.value =
              s.playing && s.processingState != ProcessingState.completed,
          onError: (Object _) => _playing.value = false,
        ),
      );
  }

  final AudioPlayer _player;
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  final ValueNotifier<bool> _playing = ValueNotifier(false);
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Duration _clipStart = Duration.zero;
  bool _clipped = false;
  bool _disposed = false;

  static Future<void>? _sessionConfigured;

  /// Configures the shared audio session once per app run.
  static Future<void> configureAudioSession() =>
      _sessionConfigured ??= _configure();

  static Future<void> _configure() async {
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
      ),
    );
  }

  @override
  ValueListenable<Duration> get position => _position;

  @override
  ValueListenable<bool> get playing => _playing;

  @override
  Future<Duration?> load(MusicSource source) async {
    try {
      await configureAudioSession();
      _clipStart = Duration.zero;
      _clipped = false;
      return switch (source) {
        MusicFileSource(:final path) => await _player.setFilePath(path),
        MusicAssetSource(:final assetKey, :final package) =>
          await _player.setAsset(assetKey, package: package),
        MusicUrlSource(:final uri, :final headers) => await _player.setUrl(
          uri.toString(),
          headers: headers.isEmpty ? null : headers,
        ),
      };
    } on Object catch (e, s) {
      throw StoryException(
        StoryErrorCode.musicUnavailable,
        'Loading the music failed.',
        e,
        s,
      );
    }
  }

  @override
  Future<void> playSegment(
    Duration start,
    Duration length, {
    bool loop = true,
  }) async {
    try {
      await _player.setClip(start: start, end: start + length);
      _clipStart = start;
      _clipped = true;
      await _player.setLoopMode(loop ? LoopMode.one : LoopMode.off);
      await _player.seek(Duration.zero);
      // play() completes only when playback pauses or stops.
      unawaited(_player.play().catchError((Object _) {}));
    } on Object catch (e, s) {
      throw StoryException(
        StoryErrorCode.musicUnavailable,
        'Playing the music failed.',
        e,
        s,
      );
    }
  }

  @override
  Future<void> seek(Duration position) async {
    final target = _clipped ? position - _clipStart : position;
    await _player.seek(target < Duration.zero ? Duration.zero : target);
  }

  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0, 1).toDouble());

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() async {
    unawaited(_player.play().catchError((Object _) {}));
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _playing.value = false;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await _player.dispose();
    _position.dispose();
    _playing.dispose();
  }
}
