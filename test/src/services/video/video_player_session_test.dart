import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:story_creator_kit/src/api/errors/story_exception.dart';
import 'package:story_creator_kit/src/model/trim_range.dart';
import 'package:story_creator_kit/src/services/video/video_player_session.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A player whose position advances only when the test says so.
class _FakePlatform extends VideoPlayerPlatform
    with MockPlatformInterfaceMixin {
  final StreamController<VideoEvent> events = StreamController();
  Duration position = Duration.zero;
  final List<Duration> seeks = [];
  bool looping = false;
  bool playing = false;
  double volume = 1;
  bool failInit = false;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async => 1;

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    if (failInit) {
      scheduleMicrotask(
        () => events.addError(
          PlatformException(code: 'VideoError', message: 'cannot decode'),
        ),
      );
    } else {
      scheduleMicrotask(
        () => events.add(
          VideoEvent(
            eventType: VideoEventType.initialized,
            duration: const Duration(seconds: 10),
            size: const Size(1080, 1920),
          ),
        ),
      );
    }
    return 1;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events.stream;

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async =>
      this.looping = looping;

  @override
  Future<void> play(int playerId) async => playing = true;

  @override
  Future<void> pause(int playerId) async => playing = false;

  @override
  Future<void> setVolume(int playerId, double volume) async =>
      this.volume = volume;

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seeks.add(position);
    this.position = position;
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => position;

  @override
  Widget buildView(int playerId) => const SizedBox();

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakePlatform platform;

  setUp(() {
    platform = _FakePlatform();
    VideoPlayerPlatform.instance = platform;
  });

  test('opens, reports state and loops the whole video by default', () async {
    final session = VideoPlayerSession();
    await session.open('/v.mp4');
    expect(session.state.value.initialized, isTrue);
    expect(session.state.value.duration, const Duration(seconds: 10));
    expect(session.state.value.size, const Size(1080, 1920));
    expect(platform.looping, isTrue);
    await session.setVolume(0.3);
    expect(platform.volume, 0.3);
    await session.dispose();
  });

  test('a playback range seeks back to its start past its end', () async {
    final session = VideoPlayerSession();
    await session.open('/v.mp4');
    await session.setPlaybackRange(
      TrimRange(const Duration(seconds: 2), const Duration(seconds: 4)),
    );
    expect(platform.looping, isFalse);
    expect(platform.seeks.last, const Duration(seconds: 2));
    await session.play();
    expect(platform.playing, isTrue);
    platform.position = const Duration(milliseconds: 4100);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(platform.seeks.last, const Duration(seconds: 2));
    expect(platform.position, const Duration(seconds: 2));
    await session.setPlaybackRange(null);
    expect(platform.looping, isTrue);
    await session.pause();
    await session.dispose();
  });

  test('an undecodable file is mediaUnsupported', () async {
    platform.failInit = true;
    final session = VideoPlayerSession();
    await expectLater(
      session.open('/bad.mp4'),
      throwsA(
        isA<StoryException>().having(
          (e) => e.code,
          'code',
          StoryErrorCode.mediaUnsupported,
        ),
      ),
    );
    expect(session.state.value.error, isA<StoryException>());
    await session.dispose();
  });
}
