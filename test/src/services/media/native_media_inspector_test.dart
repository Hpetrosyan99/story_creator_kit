import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/src/api/errors/story_exception.dart';
import 'package:story_creator_kit/src/native/story_native_api.g.dart';
import 'package:story_creator_kit/src/services/media/native_error_mapping.dart';
import 'package:story_creator_kit/src/services/media/native_media_inspector.dart';

import '../export/fake_native_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('probe maps every field', () async {
    final api = FakeNativeApi()
      ..probeResult = NativeMediaProbe(
        width: 360,
        height: 640,
        fileSizeBytes: 1234,
        rotationDegrees: 90,
        hasVideo: true,
        hasAudio: false,
        durationMs: 4000,
        videoCodec: 'hvc1',
        frameRate: 29.97,
      );
    final p = await NativeMediaInspector(api: api).probe('/x.mp4');
    expect((p.width, p.height, p.fileSizeBytes), (360, 640, 1234));
    expect(p.rotationDegrees, 90);
    expect((p.hasVideo, p.hasAudio), (true, false));
    expect(p.duration, const Duration(seconds: 4));
    expect(p.videoCodec, 'hvc1');
    expect(p.frameRate, 29.97);
  });

  test('images have no duration', () async {
    final api = FakeNativeApi()
      ..probeResult = NativeMediaProbe(
        width: 10,
        height: 20,
        fileSizeBytes: 1,
        rotationDegrees: 0,
        hasVideo: false,
        hasAudio: false,
      );
    expect(
      (await NativeMediaInspector(api: api).probe('/a.jpg')).duration,
      isNull,
    );
  });

  test('waveform and thumbnails pass arguments through', () async {
    final api = FakeNativeApi();
    final inspector = NativeMediaInspector(api: api);
    expect(await inspector.waveform('/a.m4a', buckets: 7), hasLength(7));
  });

  group('error mapping', () {
    Future<StoryException> probeError(String code) async {
      final api = FakeNativeApi()..error = PlatformException(code: code);
      try {
        await NativeMediaInspector(api: api).probe('/x');
      } on StoryException catch (e) {
        return e;
      }
      fail('no error');
    }

    test('unsupported_media → mediaUnsupported', () async {
      expect(
        (await probeError('unsupported_media')).code,
        StoryErrorCode.mediaUnsupported,
      );
    });

    test('invalid_input / io → mediaUnavailable', () async {
      expect(
        (await probeError('invalid_input')).code,
        StoryErrorCode.mediaUnavailable,
      );
      expect((await probeError('io')).code, StoryErrorCode.mediaUnavailable);
    });

    test('export errors', () {
      final s = StackTrace.current;
      expect(
        exportError(PlatformException(code: 'no_space'), s, 'x').code,
        StoryErrorCode.insufficientStorage,
      );
      expect(
        exportError(PlatformException(code: 'encoder'), s, 'x').code,
        StoryErrorCode.exportFailed,
      );
      expect(
        exportError(StateError('boom'), s, 'x').code,
        StoryErrorCode.exportFailed,
      );
      expect(
        isNativeCancellation(PlatformException(code: 'cancelled')),
        isTrue,
      );
      expect(isNativeCancellation(PlatformException(code: 'io')), isFalse);
    });
  });
}
