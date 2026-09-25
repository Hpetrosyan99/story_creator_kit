import 'dart:async';

import 'package:camera/camera.dart' as cam;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../api/config/capture_options.dart';
import '../../api/errors/story_exception.dart';
import '../../api/result/story_result.dart';
import 'capture_service.dart';

/// [CaptureService] backed by the official `camera` plugin (CameraX on
/// Android, AVFoundation on iOS).
///
/// One controller serves photos and videos. Notes on plugin behaviour this
/// class compensates for:
/// * `camera` has no max-duration: the caller runs its own timer.
/// * There is no "has flash" query. On iOS, setting the flash mode fails on
///   lenses without a flash, which is used as the probe; on Android the rear
///   lens is assumed to have a flash and front lenses not.
/// * Flash "on" does not light up videos; the torch is switched on for the
///   duration of a recording instead.
/// * Camera errors arrive as free-text `CameraValue.errorDescription`; they
///   are reported as [CaptureInterrupted] (recoverable) or [CaptureFailed]
///   (fatal) on [events], after salvaging a running recording.
/// * The lens cannot be switched during a recording: the saved clip would
///   mix mirrored and unmirrored segments (see [mirrorRule]).
class CameraCaptureService implements CaptureService {
  /// Creates the service. The camera starts with [initialize].
  CameraCaptureService();

  final StreamController<CaptureEvent> _events =
      StreamController<CaptureEvent>.broadcast();

  List<cam.CameraDescription>? _cameras;
  cam.CameraController? _controller;
  CaptureCapabilities? _caps;
  bool _enableAudio = true;
  StoryFlashMode _flashMode = StoryFlashMode.off;
  bool _torchOn = false;
  bool _disposed = false;
  String? _lastError;
  final Stopwatch _recordWatch = Stopwatch();

  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  CaptureCapabilities? get capabilities => _caps;

  @override
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  @override
  bool get isRecording => _controller?.value.isRecordingVideo ?? false;

  @override
  Stream<CaptureEvent> get events => _events.stream;

  @override
  Future<CaptureCapabilities> initialize(
    StoryCameraLens lens, {
    required CaptureResolution resolution,
    required bool enableAudio,
  }) async {
    _checkNotDisposed();
    await _releaseController();
    _enableAudio = enableAudio;
    final cameras = await _availableCameras();
    final description = _descriptionFor(cameras, lens);
    final controller = cam.CameraController(
      description,
      _preset(resolution),
      enableAudio: enableAudio,
      fps: 30,
      videoBitrate: _videoBitrate(resolution),
      audioBitrate: enableAudio ? 128000 : null,
      // Only affects image streams, which are not used; set explicitly so
      // both platforms use their native, cheapest format.
      imageFormatGroup: _isIOS
          ? cam.ImageFormatGroup.bgra8888
          : cam.ImageFormatGroup.yuv420,
    );
    _controller = controller;
    _lastError = null;
    try {
      await controller.initialize();
    } on cam.CameraException catch (e, s) {
      _controller = null;
      await _disposeQuietly(controller);
      throw _map(e, s, StoryErrorCode.cameraUnavailable);
    }
    controller.addListener(_onControllerValue);
    return _caps = await _configure(controller, cameras);
  }

  Future<CaptureCapabilities> _configure(
    cam.CameraController controller,
    List<cam.CameraDescription> cameras,
  ) async {
    final lens = _lensOf(controller.description);
    await _nonFatal(
      () => controller.lockCaptureOrientation(DeviceOrientation.portraitUp),
    );
    if (_isIOS && _enableAudio) {
      // Adds the audio input now instead of at record start, which would
      // freeze the preview briefly.
      await _nonFatal(controller.prepareForVideoRecording);
    }
    var minZoom = 1.0;
    var maxZoom = 1.0;
    await _nonFatal(() async {
      minZoom = await controller.getMinZoomLevel();
      maxZoom = await controller.getMaxZoomLevel();
    });
    if (maxZoom < minZoom) {
      maxZoom = minZoom;
    }
    final hasFlash = await _probeFlash(controller, lens);
    final size = controller.value.previewSize;
    return CaptureCapabilities(
      lens: lens,
      availableLenses: {for (final c in cameras) _lensOf(c)},
      hasFlash: hasFlash,
      minZoom: minZoom,
      maxZoom: maxZoom,
      // previewSize is in sensor (landscape) orientation.
      previewAspectRatio: size == null || size.width == 0
          ? 9 / 16
          : size.height / size.width,
    );
  }

  Future<bool> _probeFlash(
    cam.CameraController controller,
    StoryCameraLens lens,
  ) async {
    if (!_isIOS) {
      // CameraX has no flash-unit query through the plugin; front lenses
      // practically never have one.
      if (lens == StoryCameraLens.front) {
        return false;
      }
      await _nonFatal(() => _applyFlash(controller, recording: false));
      return true;
    }
    try {
      await controller.setFlashMode(cam.FlashMode.off);
    } on cam.CameraException {
      // "Device does not have flash capabilities".
      return false;
    }
    try {
      await _applyFlash(controller, recording: false);
    } on StoryException {
      return false;
    }
    return true;
  }

  @override
  Widget buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.expand();
    }
    return _CoverPreview(controller: controller);
  }

  @override
  Future<CaptureCapabilities> switchLens() async {
    final controller = _requireController();
    final caps = _caps!;
    if (controller.value.isRecordingVideo) {
      throw const StoryException(
        StoryErrorCode.captureFailed,
        'The lens cannot be switched while recording.',
      );
    }
    final next = caps.lens == StoryCameraLens.back
        ? StoryCameraLens.front
        : StoryCameraLens.back;
    final cameras = await _availableCameras();
    final description = _descriptionFor(cameras, next);
    _torchOn = false;
    try {
      await controller.setDescription(description);
    } on cam.CameraException catch (e, s) {
      throw _map(e, s, StoryErrorCode.cameraUnavailable);
    }
    return _caps = await _configure(controller, cameras);
  }

  @override
  Future<void> setFlashMode(StoryFlashMode mode) async {
    _flashMode = mode;
    final controller = _controller;
    if (controller == null || !(_caps?.hasFlash ?? false)) {
      return;
    }
    await _applyFlash(controller, recording: controller.value.isRecordingVideo);
  }

  Future<void> _applyFlash(
    cam.CameraController controller, {
    required bool recording,
  }) async {
    final cam.FlashMode mode;
    if (recording) {
      mode = _flashMode == StoryFlashMode.on
          ? cam.FlashMode.torch
          : cam.FlashMode.off;
    } else {
      mode = switch (_flashMode) {
        StoryFlashMode.off => cam.FlashMode.off,
        StoryFlashMode.auto => cam.FlashMode.auto,
        StoryFlashMode.on => cam.FlashMode.always,
      };
    }
    try {
      await controller.setFlashMode(mode);
      _torchOn = mode == cam.FlashMode.torch;
    } on cam.CameraException catch (e, s) {
      throw _map(e, s, StoryErrorCode.captureFailed);
    }
  }

  @override
  Future<void> setZoom(double zoom) async {
    final controller = _requireController();
    final caps = _caps!;
    final value = zoom.clamp(caps.minZoom, caps.maxZoom);
    try {
      await controller.setZoomLevel(value);
    } on cam.CameraException catch (e, s) {
      throw _map(e, s, StoryErrorCode.captureFailed);
    }
  }

  @override
  Future<void> focusAt(Offset point) async {
    final controller = _requireController();
    // The front preview is shown mirrored while the plugin expects sensor
    // coordinates (flutter/flutter#108745).
    final x = _caps?.lens == StoryCameraLens.front ? 1 - point.dx : point.dx;
    final target = Offset(x.clamp(0.0, 1.0), point.dy.clamp(0.0, 1.0));
    try {
      if (controller.value.focusPointSupported) {
        await controller.setFocusPoint(target);
      }
      if (controller.value.exposurePointSupported) {
        await controller.setExposurePoint(target);
      }
    } on cam.CameraException catch (e, s) {
      throw _map(e, s, StoryErrorCode.captureFailed);
    }
  }

  @override
  Future<CapturedFile> takePhoto() async {
    final controller = _requireController();
    final lens = _caps!.lens;
    try {
      final file = await controller.takePicture();
      return CapturedFile(
        path: file.path,
        type: StoryMediaType.photo,
        lens: lens,
        mirrored: mirrorRule(
          lens: lens,
          type: StoryMediaType.photo,
          platform: defaultTargetPlatform,
        ),
      );
    } on cam.CameraException catch (e, s) {
      throw _map(e, s, StoryErrorCode.captureFailed);
    }
  }

  @override
  Future<void> startRecording() async {
    final controller = _requireController();
    try {
      if (_caps!.hasFlash && _flashMode == StoryFlashMode.on) {
        await _applyFlash(controller, recording: true);
      }
      // Persistent recording (the default) keeps Android from stopping the
      // recording on lifecycle events; we stop it ourselves.
      await controller.startVideoRecording();
      _recordWatch
        ..reset()
        ..start();
    } on cam.CameraException catch (e, s) {
      await _restorePhotoFlash(controller);
      throw _map(e, s, StoryErrorCode.captureFailed);
    }
  }

  @override
  Future<CapturedFile> stopRecording() async {
    final controller = _requireController();
    final lens = _caps!.lens;
    try {
      final file = await controller.stopVideoRecording();
      _recordWatch.stop();
      return CapturedFile(
        path: file.path,
        type: StoryMediaType.video,
        lens: lens,
        duration: _recordWatch.elapsed,
        mirrored: mirrorRule(
          lens: lens,
          type: StoryMediaType.video,
          platform: defaultTargetPlatform,
        ),
      );
    } on cam.CameraException catch (e, s) {
      throw _map(e, s, StoryErrorCode.captureFailed);
    } finally {
      await _restorePhotoFlash(controller);
    }
  }

  Future<void> _restorePhotoFlash(cam.CameraController controller) async {
    if (!_torchOn || !controller.value.isInitialized) {
      return;
    }
    await _nonFatal(() => _applyFlash(controller, recording: false));
  }

  @override
  Future<void> release() async {
    final partial = await _salvageRecording();
    await _releaseController();
    if (partial != null && !_events.isClosed) {
      _events.add(CaptureInterrupted('released', partialRecording: partial));
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    await release();
    _disposed = true;
    await _events.close();
  }

  /// Whether a saved file must be flipped horizontally to look like the
  /// preview the user saw.
  ///
  /// Previews of front lenses are mirrored on both platforms. What is saved
  /// differs (camera 0.12.1, camera_avfoundation 0.10.3, CameraX 0.7.4):
  /// * iOS video: the video data connection sets `isVideoMirrored = true`
  ///   for front lenses, so the file is already mirrored → `false`.
  /// * iOS photo: `AVCapturePhotoOutput` keeps AVFoundation's automatic
  ///   mirroring for front lenses, so the file is mirrored → `false`.
  /// * Android video: the plugin never sets a `MirrorMode`; CameraX
  ///   defaults to `MIRROR_MODE_OFF`, so the file is not mirrored → `true`.
  /// * Android photo: `ImageCapture` saves the sensor image un-mirrored on
  ///   most devices (OEM-dependent, flutter/flutter#72243) → `true`.
  /// * Rear lenses are never mirrored → `false`.
  ///
  /// Verify on devices when upgrading the camera plugins.
  @visibleForTesting
  static bool mirrorRule({
    required StoryCameraLens lens,
    required StoryMediaType type,
    required TargetPlatform platform,
  }) {
    if (lens != StoryCameraLens.front) {
      return false;
    }
    return switch (platform) {
      TargetPlatform.iOS || TargetPlatform.macOS => false,
      _ => true,
    };
  }

  void _onControllerValue() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final description = controller.value.errorDescription;
    if (description == null || description == _lastError) {
      return;
    }
    _lastError = description;
    unawaited(_handleCameraError(description));
  }

  Future<void> _handleCameraError(String description) async {
    final partial = await _salvageRecording();
    await _releaseController();
    if (_events.isClosed) {
      return;
    }
    if (partial == null && _isFatal(description)) {
      _events.add(
        CaptureFailed(
          StoryException(StoryErrorCode.cameraUnavailable, description),
        ),
      );
    } else {
      // With a salvaged clip the caller keeps it and re-initialises; a
      // fatal error then surfaces from that initialisation.
      _events.add(CaptureInterrupted(description, partialRecording: partial));
    }
  }

  /// CameraX error strings (android_camera_camerax.dart, `CameraStateError`)
  /// that need more than a re-initialisation.
  static bool _isFatal(String description) {
    return description.toLowerCase().contains('fatal');
  }

  Future<CapturedFile?> _salvageRecording() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        !controller.value.isRecordingVideo) {
      return null;
    }
    try {
      return await stopRecording();
    } on StoryException {
      // The platform could not finalise the file; there is nothing to keep.
      return null;
    }
  }

  Future<void> _releaseController() async {
    final controller = _controller;
    _controller = null;
    _caps = null;
    _torchOn = false;
    if (controller == null) {
      return;
    }
    controller.removeListener(_onControllerValue);
    await _disposeQuietly(controller);
  }

  static Future<void> _disposeQuietly(cam.CameraController controller) async {
    try {
      await controller.dispose();
    } on cam.CameraException catch (e, s) {
      // Disposing a camera that already failed can throw; the controller is
      // unusable either way.
      _debugLog('dispose', e, s);
    } on PlatformException catch (e, s) {
      _debugLog('dispose', e, s);
    }
  }

  Future<List<cam.CameraDescription>> _availableCameras() async {
    final cached = _cameras;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    final List<cam.CameraDescription> cameras;
    try {
      cameras = await cam.availableCameras();
    } on cam.CameraException catch (e, s) {
      throw _map(e, s, StoryErrorCode.cameraUnavailable);
    } on PlatformException catch (e, s) {
      throw StoryException(
        StoryErrorCode.cameraUnavailable,
        'Listing cameras failed.',
        e,
        s,
      );
    }
    if (cameras.isEmpty) {
      throw const StoryException(
        StoryErrorCode.cameraUnavailable,
        'This device has no camera.',
      );
    }
    return _cameras = cameras;
  }

  static cam.CameraDescription _descriptionFor(
    List<cam.CameraDescription> cameras,
    StoryCameraLens lens,
  ) {
    for (final camera in cameras) {
      if (_lensOf(camera) == lens) {
        return camera;
      }
    }
    return cameras.first;
  }

  static StoryCameraLens _lensOf(cam.CameraDescription description) =>
      description.lensDirection == cam.CameraLensDirection.front
      ? StoryCameraLens.front
      : StoryCameraLens.back;

  static cam.ResolutionPreset _preset(CaptureResolution resolution) =>
      switch (resolution) {
        CaptureResolution.medium => cam.ResolutionPreset.high,
        CaptureResolution.high => cam.ResolutionPreset.veryHigh,
        CaptureResolution.max => cam.ResolutionPreset.max,
      };

  static int? _videoBitrate(CaptureResolution resolution) =>
      switch (resolution) {
        CaptureResolution.medium => 5000000,
        CaptureResolution.high => 10000000,
        CaptureResolution.max => null,
      };

  cam.CameraController _requireController() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw const StoryException(
        StoryErrorCode.cameraUnavailable,
        'The camera is not initialised.',
      );
    }
    return controller;
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw const StoryException(
        StoryErrorCode.cameraUnavailable,
        'The capture service was disposed.',
      );
    }
  }

  /// Maps plugin errors to typed errors. Permission codes are the ones
  /// documented by `camera`; everything else falls back to [fallback].
  static StoryException _map(
    cam.CameraException e,
    StackTrace s,
    StoryErrorCode fallback,
  ) {
    final code = e.code;
    final StoryErrorCode mapped;
    if (code.startsWith('CameraAccess')) {
      mapped = StoryErrorCode.cameraPermissionDenied;
    } else if (code.startsWith('AudioAccess')) {
      mapped = StoryErrorCode.microphonePermissionDenied;
    } else if (code == 'Disposed CameraController' ||
        code.contains('Uninitialized')) {
      mapped = StoryErrorCode.captureInterrupted;
    } else {
      mapped = fallback;
    }
    return StoryException(mapped, '${e.code}: ${e.description}', e, s);
  }

  /// Runs an optional configuration step. Failures only disable the
  /// feature (e.g. orientation lock, zoom range), so they are logged in
  /// debug builds and otherwise ignored.
  static Future<void> _nonFatal(Future<void> Function() action) async {
    try {
      await action();
    } on cam.CameraException catch (e, s) {
      _debugLog('optional camera setup', e, s);
    } on StoryException catch (e, s) {
      _debugLog('optional camera setup', e, s);
    } on PlatformException catch (e, s) {
      _debugLog('optional camera setup', e, s);
    }
  }

  static void _debugLog(String what, Object error, StackTrace stackTrace) {
    assert(() {
      debugPrint('story_creator_kit: $what failed: $error');
      return true;
    }(), 'debug log');
  }
}

/// The camera preview scaled to cover its parent without distortion.
class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.controller});

  final cam.CameraController controller;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.previewSize;
    if (size == null) {
      return const SizedBox.expand();
    }
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          // previewSize is landscape; the UI is locked to portrait.
          width: size.height,
          height: size.width,
          child: cam.CameraPreview(controller),
        ),
      ),
    );
  }
}
