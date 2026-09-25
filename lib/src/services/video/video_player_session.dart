import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../../api/errors/story_exception.dart';
import '../../model/trim_range.dart';
import '../audio/just_audio_music_session.dart';
import 'video_session.dart';

/// Creates the controller for a file (replaceable in tests).
typedef VideoControllerFactory = VideoPlayerController Function(File file);

/// [VideoSession] backed by `video_player`.
///
/// video_player has no range playback, so a trim range is looped by watching
/// the position and seeking back to the start once it passes the end (the
/// preview may overshoot by up to one position update, ~100 ms; the export
/// is exact).
class VideoPlayerSession implements VideoSession {
  /// Creates a session.
  VideoPlayerSession({VideoControllerFactory? createController})
    : _createController = createController ?? _defaultController;

  static VideoPlayerController _defaultController(File file) =>
      VideoPlayerController.file(
        file,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

  final VideoControllerFactory _createController;
  final ValueNotifier<VideoPlaybackState> _state = ValueNotifier(
    const VideoPlaybackState(),
  );
  VideoPlayerController? _controller;
  TrimRange? _range;
  bool _seekingBack = false;
  bool _disposed = false;

  @override
  ValueListenable<VideoPlaybackState> get state => _state;

  @override
  Future<void> open(String path) async {
    await _release();
    final controller = _createController(File(path));
    _controller = controller;
    try {
      await controller.initialize();
      // Plugins override each other's audio session; restore ours so music
      // previews keep playing next to the video.
      unawaited(
        JustAudioMusicSession.configureAudioSession().catchError((Object _) {}),
      );
    } on Object catch (e, s) {
      final error = StoryException(
        StoryErrorCode.mediaUnsupported,
        'The video cannot be played.',
        e,
        s,
      );
      _state.value = _state.value.copyWith(error: error);
      throw error;
    }
    if (_disposed || _controller != controller) {
      await controller.dispose();
      return;
    }
    await controller.setLooping(_range == null);
    controller.addListener(_onTick);
    _onTick();
  }

  void _onTick() {
    final controller = _controller;
    if (controller == null || _disposed) {
      return;
    }
    final value = controller.value;
    final range = _range;
    if (range != null && value.isPlaying && !_seekingBack) {
      final end = range.end < value.duration ? range.end : value.duration;
      if (value.position >= end || value.position < range.start) {
        _seekingBack = true;
        unawaited(
          controller
              .seekTo(range.start)
              .whenComplete(() => _seekingBack = false),
        );
      }
    } else if (range != null && value.isCompleted && !_seekingBack) {
      // Reached the end of the file with a range ending there.
      _seekingBack = true;
      unawaited(
        controller
            .seekTo(range.start)
            .then((_) => controller.play())
            .whenComplete(() => _seekingBack = false),
      );
    }
    _state.value = VideoPlaybackState(
      initialized: value.isInitialized,
      playing: value.isPlaying,
      position: value.position,
      duration: value.duration,
      size: value.size,
      error: value.hasError
          ? StoryException(
              StoryErrorCode.mediaUnsupported,
              value.errorDescription,
            )
          : null,
    );
  }

  @override
  Widget buildView() {
    final controller = _controller;
    if (controller == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<VideoPlaybackState>(
      valueListenable: _state,
      builder: (context, state, _) => state.initialized
          ? AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            )
          : const SizedBox.shrink(),
    );
  }

  @override
  Future<void> play() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final range = _range;
    if (range != null && !range.contains(controller.value.position)) {
      await controller.seekTo(range.start);
    }
    await controller.play();
  }

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> seekTo(Duration position) async => _controller?.seekTo(position);

  @override
  Future<void> setVolume(double volume) async =>
      _controller?.setVolume(volume.clamp(0, 1).toDouble());

  @override
  Future<void> setPlaybackRange(TrimRange? range) async {
    _range = range;
    final controller = _controller;
    if (controller == null) {
      return;
    }
    await controller.setLooping(range == null);
    if (range != null && !range.contains(controller.value.position)) {
      await controller.seekTo(range.start);
    }
  }

  Future<void> _release() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_onTick);
      await controller.dispose();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _release();
    _state.dispose();
  }
}
