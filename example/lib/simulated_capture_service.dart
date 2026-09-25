import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:story_creator_kit/services.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

/// Whether the app runs in the iOS Simulator, which has no camera.
Future<bool> detectIosSimulator() async {
  if (!Platform.isIOS) {
    return false;
  }
  final info = await DeviceInfoPlugin().iosInfo;
  return !info.isPhysicalDevice;
}

/// A stand-in camera for the iOS Simulator: shows an animated gradient,
/// "takes" photos by rendering a frame, and "records" by returning a bundled
/// sample clip. Shows how hosts can replace a `StoryServices` member.
class SimulatedCaptureService implements CaptureService {
  final StreamController<CaptureEvent> _events = StreamController.broadcast();
  CaptureCapabilities? _capabilities;
  bool _recording = false;
  DateTime _recordingStart = DateTime.now();

  @override
  CaptureCapabilities? get capabilities => _capabilities;

  @override
  bool get isInitialized => _capabilities != null;

  @override
  bool get isRecording => _recording;

  @override
  Stream<CaptureEvent> get events => _events.stream;

  @override
  Future<CaptureCapabilities> initialize(
    StoryCameraLens lens, {
    required CaptureResolution resolution,
    required bool enableAudio,
  }) async => _capabilities = CaptureCapabilities(
    lens: lens,
    availableLenses: const {StoryCameraLens.back, StoryCameraLens.front},
    hasFlash: false,
    minZoom: 1,
    maxZoom: 4,
    previewAspectRatio: 9 / 16,
  );

  @override
  Widget buildPreview() =>
      _SimulatedPreview(front: _capabilities?.lens == StoryCameraLens.front);

  @override
  Future<CaptureCapabilities> switchLens() => initialize(
    _capabilities?.lens == StoryCameraLens.front
        ? StoryCameraLens.back
        : StoryCameraLens.front,
    resolution: CaptureResolution.high,
    enableAudio: true,
  );

  @override
  Future<void> setFlashMode(StoryFlashMode mode) async {}

  @override
  Future<void> setZoom(double zoom) async {}

  @override
  Future<void> focusAt(Offset point) async {}

  @override
  Future<CapturedFile> takePhoto() async {
    const size = ui.Size(1080, 1920);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final t = DateTime.now().millisecondsSinceEpoch / 4000;
    canvas.drawRect(
      Offset.zero & size,
      ui.Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, size.height),
          [
            HSVColor.fromAHSV(1, (t * 60) % 360, 0.6, 0.9).toColor(),
            HSVColor.fromAHSV(1, (t * 60 + 120) % 360, 0.7, 0.5).toColor(),
          ],
        ),
    );
    final image = await recorder.endRecording().toImage(1080, 1920);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File(
      '${(await getTemporaryDirectory()).path}/sim_photo_'
      '${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    return CapturedFile(
      path: file.path,
      type: StoryMediaType.photo,
      lens: _capabilities!.lens,
    );
  }

  @override
  Future<void> startRecording() async {
    _recording = true;
    _recordingStart = DateTime.now();
  }

  @override
  Future<CapturedFile> stopRecording() async {
    _recording = false;
    final data = await rootBundle.load('assets/sim/sim_clip.mp4');
    final file = File(
      '${(await getTemporaryDirectory()).path}/sim_video_'
      '${DateTime.now().microsecondsSinceEpoch}.mp4',
    );
    await file.writeAsBytes(data.buffer.asUint8List());
    return CapturedFile(
      path: file.path,
      type: StoryMediaType.video,
      lens: _capabilities!.lens,
      duration: DateTime.now().difference(_recordingStart),
    );
  }

  @override
  Future<void> release() async => _capabilities = null;

  @override
  Future<void> dispose() => _events.close();
}

class _SimulatedPreview extends StatefulWidget {
  const _SimulatedPreview({required this.front});

  final bool front;

  @override
  State<_SimulatedPreview> createState() => _SimulatedPreviewState();
}

class _SimulatedPreviewState extends State<_SimulatedPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final hue = _controller.value * 360;
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              HSVColor.fromAHSV(1, hue, 0.6, 0.9).toColor(),
              HSVColor.fromAHSV(1, (hue + 120) % 360, 0.7, 0.5).toColor(),
            ],
          ),
        ),
        child: Center(
          child: Text(
            widget.front ? 'Simulated front camera' : 'Simulated camera',
            style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 18),
          ),
        ),
      );
    },
  );
}

/// Permissions for the simulated camera: it uses neither the camera nor the
/// microphone (recordings are a bundled clip), so both count as granted.
/// Settings still open the real system page.
class SimulatedCameraPermissions implements PermissionService {
  SimulatedCameraPermissions(this._real);

  final PermissionService _real;

  @override
  Future<PermissionState> checkCamera() async => PermissionState.granted;

  @override
  Future<PermissionState> requestCamera() async => PermissionState.granted;

  @override
  Future<PermissionState> checkMicrophone() async => PermissionState.granted;

  @override
  Future<PermissionState> requestMicrophone() async => PermissionState.granted;

  @override
  Future<bool> openSettings() => _real.openSettings();
}
