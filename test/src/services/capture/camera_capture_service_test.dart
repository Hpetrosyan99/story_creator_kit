import 'dart:async';
import 'dart:math';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:story_creator_kit/services.dart';
import 'package:story_creator_kit/src/services/capture/camera_capture_service.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

/// In-memory camera platform recording the calls it receives.
class FakeCameraPlatform extends CameraPlatform
    with MockPlatformInterfaceMixin {
  FakeCameraPlatform({List<CameraDescription>? cameras})
    : cameras = cameras ?? [back, front];

  static const back = CameraDescription(
    name: 'back',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );
  static const front = CameraDescription(
    name: 'front',
    lensDirection: CameraLensDirection.front,
    sensorOrientation: 270,
  );

  List<CameraDescription> cameras;
  final List<String> calls = [];
  final List<FlashMode> flashModes = [];
  MediaSettings? lastSettings;
  CameraException? initializeError;
  CameraException? flashError;
  Point<double>? focusPoint;
  double? zoom;
  int _nextId = 1;
  final Map<int, StreamController<CameraInitializedEvent>> _initialized = {};
  final Map<int, StreamController<CameraErrorEvent>> _errors = {};
  int? lastId;

  StreamController<CameraInitializedEvent> _init(int id) =>
      _initialized.putIfAbsent(id, StreamController.broadcast);

  StreamController<CameraErrorEvent> _error(int id) =>
      _errors.putIfAbsent(id, StreamController.broadcast);

  /// Reports a camera error on the current camera.
  void emitError(String description) =>
      _error(lastId!).add(CameraErrorEvent(lastId!, description));

  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings? mediaSettings,
  ) async {
    calls.add('create:${cameraDescription.name}');
    lastSettings = mediaSettings;
    return lastId = _nextId++;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    if (initializeError != null) {
      throw initializeError!;
    }
    scheduleMicrotask(
      () => _init(cameraId).add(
        CameraInitializedEvent(
          cameraId,
          1280,
          720,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      ),
    );
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      _init(cameraId).stream;

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      _error(cameraId).stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Future<void> lockCaptureOrientation(
    int cameraId,
    DeviceOrientation orientation,
  ) async => calls.add('lock:${orientation.name}');

  @override
  Future<void> prepareForVideoRecording() async => calls.add('prepare');

  @override
  Future<double> getMinZoomLevel(int cameraId) async => 1;

  @override
  Future<double> getMaxZoomLevel(int cameraId) async => 8;

  @override
  Future<void> setZoomLevel(int cameraId, double zoom) async =>
      this.zoom = zoom;

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {
    if (flashError != null) {
      throw flashError!;
    }
    flashModes.add(mode);
  }

  @override
  Future<void> setFocusPoint(int cameraId, Point<double>? point) async =>
      focusPoint = point;

  @override
  Future<void> setExposurePoint(int cameraId, Point<double>? point) async {}

  @override
  Future<XFile> takePicture(int cameraId) async {
    calls.add('takePicture');
    return XFile('/tmp/photo_$cameraId.jpg');
  }

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async =>
      calls.add('startVideo');

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    calls.add('stopVideo');
    return XFile('/tmp/video_$cameraId.mp4');
  }

  @override
  Widget buildPreview(int cameraId) => const SizedBox.expand();

  @override
  Future<void> dispose(int cameraId) async => calls.add('dispose:$cameraId');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeCameraPlatform platform;
  late CameraCaptureService service;

  setUp(() {
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    service = CameraCaptureService();
  });

  tearDown(() async {
    await service.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  Future<CaptureCapabilities> init({
    StoryCameraLens lens = StoryCameraLens.back,
    bool audio = true,
  }) => service.initialize(
    lens,
    resolution: CaptureResolution.high,
    enableAudio: audio,
  );

  Matcher code(StoryErrorCode c) =>
      isA<StoryException>().having((e) => e.code, 'code', c);

  test('no cameras → cameraUnavailable', () async {
    platform.cameras = [];
    await expectLater(init(), throwsA(code(StoryErrorCode.cameraUnavailable)));
  });

  test('initialize reports capabilities and configures the session', () async {
    final caps = await init();

    expect(caps.lens, StoryCameraLens.back);
    expect(caps.availableLenses, {StoryCameraLens.back, StoryCameraLens.front});
    expect(caps.canSwitchLens, isTrue);
    expect(caps.minZoom, 1);
    expect(caps.maxZoom, 8);
    expect(caps.previewAspectRatio, closeTo(720 / 1280, 1e-9));
    expect(caps.hasFlash, isTrue);
    expect(service.isInitialized, isTrue);
    expect(platform.calls, contains('lock:portraitUp'));
    expect(platform.lastSettings?.enableAudio, isTrue);
    expect(platform.lastSettings?.resolutionPreset, ResolutionPreset.veryHigh);
    expect(platform.lastSettings?.fps, 30);
    expect(platform.lastSettings?.videoBitrate, 10000000);
  });

  test('Android front lens has no flash', () async {
    final caps = await init(lens: StoryCameraLens.front);
    expect(caps.lens, StoryCameraLens.front);
    expect(caps.hasFlash, isFalse);
  });

  test('iOS probes the flash by setting it', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    platform.flashError = CameraException(
      'setFlashModeFailed',
      'Device does not have flash capabilities',
    );
    final caps = await init();
    expect(caps.hasFlash, isFalse);
    expect(platform.calls, contains('prepare'));
  });

  test('a missing lens falls back to the first camera', () async {
    platform.cameras = [FakeCameraPlatform.back];
    final caps = await init(lens: StoryCameraLens.front);
    expect(caps.lens, StoryCameraLens.back);
    expect(caps.canSwitchLens, isFalse);
  });

  test('permission errors are typed', () async {
    platform.initializeError = CameraException('CameraAccessDenied', 'no');
    await expectLater(
      init(),
      throwsA(code(StoryErrorCode.cameraPermissionDenied)),
    );
    platform.initializeError = CameraException('AudioAccessDenied', 'no');
    await expectLater(
      init(),
      throwsA(code(StoryErrorCode.microphonePermissionDenied)),
    );
    platform.initializeError = CameraException('weird', 'no');
    await expectLater(init(), throwsA(code(StoryErrorCode.cameraUnavailable)));
  });

  test('photo flash modes map to the plugin modes', () async {
    await init();
    await service.setFlashMode(StoryFlashMode.auto);
    await service.setFlashMode(StoryFlashMode.on);
    await service.setFlashMode(StoryFlashMode.off);
    expect(platform.flashModes.skip(1), [
      FlashMode.auto,
      FlashMode.always,
      FlashMode.off,
    ]);
  });

  test('flash on lights the torch while recording', () async {
    await init();
    await service.setFlashMode(StoryFlashMode.on);
    await service.startRecording();
    expect(platform.flashModes.last, FlashMode.torch);
    expect(service.isRecording, isTrue);

    final file = await service.stopRecording();
    expect(platform.flashModes.last, FlashMode.always);
    expect(file.type, StoryMediaType.video);
    expect(file.duration, isNotNull);
    expect(file.path, endsWith('.mp4'));
    expect(file.mirrored, isFalse);
  });

  test('front captures on Android are flagged mirrored', () async {
    await init(lens: StoryCameraLens.front);
    final photo = await service.takePhoto();
    expect(photo.lens, StoryCameraLens.front);
    expect(photo.mirrored, isTrue);
  });

  test('the lens cannot be switched while recording', () async {
    await init();
    await service.startRecording();
    await expectLater(
      service.switchLens(),
      throwsA(code(StoryErrorCode.captureFailed)),
    );
    await service.stopRecording();

    final caps = await service.switchLens();
    expect(caps.lens, StoryCameraLens.front);
    expect(platform.calls.where((c) => c.startsWith('create:')), [
      'create:back',
      'create:front',
    ]);
  });

  test('zoom is clamped; focus flips x for the front lens', () async {
    await init(lens: StoryCameraLens.front);
    await service.setZoom(20);
    expect(platform.zoom, 8);
    await service.focusAt(const Offset(0.2, 0.7));
    expect(platform.focusPoint!.x, closeTo(0.8, 1e-9));
    expect(platform.focusPoint!.y, closeTo(0.7, 1e-9));
  });

  test('a camera error while recording keeps the clip and releases', () async {
    await init();
    final events = <CaptureEvent>[];
    final sub = service.events.listen(events.add);
    await service.startRecording();

    platform.emitError('Camera is already in use');
    await pumpEventQueue();

    final event = events.single as CaptureInterrupted;
    expect(event.partialRecording?.path, endsWith('.mp4'));
    expect(service.isInitialized, isFalse);
    await sub.cancel();
  });

  test('a fatal error without a recording is a failure', () async {
    await init();
    final events = <CaptureEvent>[];
    final sub = service.events.listen(events.add);

    platform.emitError('cameraFatalError: reboot needed');
    await pumpEventQueue();

    final event = events.single as CaptureFailed;
    expect(event.error, code(StoryErrorCode.cameraUnavailable));
    await sub.cancel();
  });

  test('release while recording hands the partial clip over', () async {
    await init();
    final events = <CaptureEvent>[];
    final sub = service.events.listen(events.add);
    await service.startRecording();

    await service.release();
    await pumpEventQueue();

    expect(platform.calls, containsAllInOrder(['stopVideo', 'dispose:1']));
    expect((events.single as CaptureInterrupted).partialRecording, isNotNull);
    expect(service.isInitialized, isFalse);
    expect(service.capabilities, isNull);
    await sub.cancel();

    // It can start again.
    await init();
    expect(service.isInitialized, isTrue);
  });

  test('calls before initialize are typed errors', () async {
    await expectLater(
      service.takePhoto(),
      throwsA(code(StoryErrorCode.cameraUnavailable)),
    );
  });

  test('after dispose the service refuses to start', () async {
    await service.dispose();
    await expectLater(init(), throwsA(code(StoryErrorCode.cameraUnavailable)));
  });

  group('mirrorRule', () {
    bool rule(StoryCameraLens lens, StoryMediaType type, TargetPlatform p) =>
        CameraCaptureService.mirrorRule(lens: lens, type: type, platform: p);

    test('rear captures are never mirrored', () {
      for (final p in [TargetPlatform.iOS, TargetPlatform.android]) {
        for (final t in StoryMediaType.values) {
          expect(rule(StoryCameraLens.back, t, p), isFalse);
        }
      }
    });

    test('iOS front files are saved mirrored already', () {
      for (final t in StoryMediaType.values) {
        expect(rule(StoryCameraLens.front, t, TargetPlatform.iOS), isFalse);
      }
    });

    test('Android front files need a flip', () {
      for (final t in StoryMediaType.values) {
        expect(rule(StoryCameraLens.front, t, TargetPlatform.android), isTrue);
      }
    });
  });
}
