import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../api/config/capture_options.dart';
import '../api/config/media_constraints.dart';
import '../api/errors/story_exception.dart';
import '../api/result/story_result.dart';
import '../core/media_import.dart';
import '../model/story_media.dart';
import '../services/capture/capture_service.dart';
import '../services/gallery/gallery_source.dart';
import '../services/permissions/permission_service.dart';
import 'text_story_background.dart';

/// What the camera screen shows.
enum CameraStatus {
  /// Reading the camera permission.
  checkingPermission,

  /// Camera access not granted yet; the user can be asked.
  permissionRequired,

  /// Camera access denied permanently; only the settings app helps.
  permissionBlocked,

  /// The camera is starting or reconnecting.
  starting,

  /// The preview is live.
  ready,

  /// No usable camera (none present, or it failed).
  unavailable,

  /// Released because the app is in the background.
  paused,
}

/// What a tap on the shutter does.
enum CameraCaptureMode {
  /// Tap takes a photo; press and hold records a video.
  photo,

  /// Tap starts and stops a recording; press and hold also records.
  video,
}

/// A short message shown over the camera.
enum CameraNotice {
  /// Videos are recorded without sound.
  microphoneDenied,

  /// The shutter was released before the minimum video length.
  recordingTooShort,

  /// An interrupted recording was too short to keep.
  recordingDiscarded,

  /// The camera session was interrupted.
  interrupted,

  /// A picked video is shorter than the minimum.
  videoTooShort,

  /// A picked file is larger than the import limit.
  mediaTooLarge,

  /// The file type cannot be used.
  mediaUnsupported,

  /// The file could not be read.
  mediaUnavailable,

  /// Taking the photo or video failed.
  captureFailed,
}

/// State and actions of the camera screen.
///
/// Owns one [CaptureService] (created per screen) and handles permissions,
/// the recording timer (the camera plugin ignores max durations), app
/// lifecycle and session interruptions:
/// * background (inactive/paused/hidden): a running recording is stopped
///   and kept, the camera is released;
/// * resume: permissions are read again (the user may come back from the
///   settings app); a kept clip is imported and opens the editor, otherwise
///   the camera starts again;
/// * [CaptureInterrupted] / [CaptureFailed] events are handled the same way.
///
/// Lifecycle changes that happen while a permission prompt is showing are
/// ignored (iOS reports the prompt as `inactive`).
class StoryCameraController extends ChangeNotifier with WidgetsBindingObserver {
  /// Creates the controller. Call [start] once.
  StoryCameraController({
    required this._capture,
    required this._permissions,
    required this._gallery,
    required this._importer,
    required CaptureOptions options,
    required this._constraints,
    required this._onMediaReady,
    required this._onError,
    this.screenFlashDelay = const Duration(milliseconds: 180),
    this.tick = const Duration(milliseconds: 50),
    this.noticeDuration = const Duration(milliseconds: 2800),
    this.focusMarkerDuration = const Duration(milliseconds: 900),
  }) : _options = options,
       _lens = options.initialLens;

  final CaptureService _capture;
  final PermissionService _permissions;
  final GallerySource _gallery;
  final MediaImporter _importer;
  final CaptureOptions _options;
  final MediaConstraints _constraints;
  final ValueChanged<StoryMedia> _onMediaReady;
  final void Function(StoryException error) _onError;

  /// How long the front-camera screen flash shows before the photo is
  /// taken, so the exposure adapts to the extra light.
  final Duration screenFlashDelay;

  /// Recording timer resolution.
  final Duration tick;

  /// How long a notice stays visible.
  final Duration noticeDuration;

  /// How long the focus marker stays visible.
  final Duration focusMarkerDuration;

  /// Elapsed recording time (resets on each recording).
  final ValueNotifier<Duration> elapsed = ValueNotifier(Duration.zero);

  /// The notice currently shown, if any.
  final ValueNotifier<CameraNotice?> notice = ValueNotifier(null);

  CameraStatus _status = CameraStatus.checkingPermission;
  CaptureCapabilities? _caps;
  StoryCameraLens _lens;
  StoryFlashMode _flash = StoryFlashMode.off;
  late CameraCaptureMode _mode = photoEnabled
      ? CameraCaptureMode.photo
      : CameraCaptureMode.video;
  double _zoom = 1;
  bool _recording = false;
  bool _locked = false;
  bool _busy = false;
  bool _capturing = false;
  bool _switching = false;
  bool _screenFlash = false;
  bool _audioEnabled = false;
  bool _micDenied = false;
  bool _micRequested = false;
  bool _micNoticeShown = false;
  Offset? _focusPoint;
  int _focusId = 0;

  bool _started = false;
  bool _disposed = false;
  bool _suspended = false;
  bool _permissionPrompt = false;
  bool _stopping = false;
  int _generation = 0;
  CapturedFile? _pendingClip;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  Future<void> _queue = Future<void>.value();
  Future<void>? _startingRecording;
  StreamSubscription<CaptureEvent>? _events;
  Timer? _ticker;
  Timer? _noticeTimer;
  Timer? _focusTimer;
  double? _pendingZoom;
  bool _zoomInFlight = false;

  /// Current screen state.
  CameraStatus get status => _status;

  /// Capabilities of the live camera, if any.
  CaptureCapabilities? get capabilities => _caps;

  /// The capture service (for its preview widget).
  CaptureService get capture => _capture;

  /// The lens in use (or to be used).
  StoryCameraLens get lens => _lens;

  /// Selected flash mode.
  StoryFlashMode get flashMode => _flash;

  /// Current zoom factor.
  double get zoom => _zoom;

  /// What a tap on the shutter does.
  CameraCaptureMode get captureMode => _mode;

  /// Whether the Video | Photo toggle is shown (both are enabled).
  bool get captureModeSelectable => photoEnabled && videoEnabled;

  /// Whether a recording runs.
  bool get isRecording => _recording;

  /// Whether the running recording is hands-free (tap to stop).
  bool get isLocked => _locked;

  /// Whether media is being imported.
  bool get isBusy => _busy;

  /// Whether the white screen flash for front-camera photos is showing.
  bool get screenFlashVisible => _screenFlash;

  /// Where the focus marker is (0–1 preview coordinates), if visible.
  Offset? get focusPoint => _focusPoint;

  /// Changes each time focus is requested (restarts the marker).
  int get focusId => _focusId;

  /// Whether videos are recorded with sound.
  bool get audioEnabled => _audioEnabled;

  /// Whether the preview is live and nothing blocks capturing.
  bool get isReady =>
      _status == CameraStatus.ready && !_busy && !_capturing && !_switching;

  /// Whether photos can be taken.
  bool get photoEnabled => _options.enablePhoto && _constraints.allowPhotos;

  /// Whether videos can be recorded.
  bool get videoEnabled => _options.enableVideo && _constraints.allowVideos;

  /// Whether the flash control is shown: a hardware flash, or a front lens
  /// (screen flash for photos).
  bool get flashAvailable {
    final caps = _caps;
    if (!_options.enableFlash || caps == null) {
      return false;
    }
    return caps.hasFlash || caps.lens == StoryCameraLens.front;
  }

  /// Whether the lens switch is shown.
  bool get lensSwitchAvailable =>
      _options.enableLensSwitch && (_caps?.canSwitchLens ?? false);

  /// Whether the flash only lights the screen (no hardware flash).
  bool get usesScreenFlash => flashAvailable && !(_caps?.hasFlash ?? false);

  /// Maximum recording length.
  Duration get maxDuration => _constraints.maxVideoDuration;

  /// Starts listening to the app lifecycle and opens the camera.
  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _events = _capture.events.listen(_onCaptureEvent);
    await _enqueue(() => _openCamera(request: false));
  }

  /// Asks for camera access (from the permission view).
  Future<void> requestPermission() =>
      _enqueue(() => _openCamera(request: true));

  /// Opens the app's system settings (camera permanently denied).
  Future<void> openSettings() async {
    try {
      await _permissions.openSettings();
    } on StoryException catch (e) {
      _onError(e);
    }
  }

  /// Tries to start the camera again (from the unavailable view).
  Future<void> retry() => _enqueue(() => _openCamera(request: false));

  // ---------------------------------------------------------------------
  // Camera start

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _queue.then((_) => _disposed ? null : action());
    _queue = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> _openCamera({required bool request}) async {
    final generation = ++_generation;
    if (_status != CameraStatus.ready) {
      _setStatus(CameraStatus.checkingPermission);
    }
    final PermissionState camera;
    try {
      camera = request
          ? await _duringPrompt(_permissions.requestCamera)
          : await _permissions.checkCamera();
    } on StoryException catch (e) {
      _onError(e);
      _setStatus(CameraStatus.unavailable);
      return;
    }
    if (_stale(generation)) {
      return;
    }
    if (camera != PermissionState.granted) {
      _setStatus(
        camera == PermissionState.denied
            ? CameraStatus.permissionRequired
            : CameraStatus.permissionBlocked,
      );
      return;
    }
    await _resolveMicrophone();
    if (_stale(generation)) {
      return;
    }
    await _initialize(generation);
  }

  Future<void> _resolveMicrophone() async {
    if (!videoEnabled || !_options.enableAudio) {
      _audioEnabled = false;
      _micDenied = false;
      return;
    }
    try {
      var mic = await _permissions.checkMicrophone();
      if (mic == PermissionState.denied && !_micRequested) {
        _micRequested = true;
        mic = await _duringPrompt(_permissions.requestMicrophone);
      }
      _audioEnabled = mic == PermissionState.granted;
    } on StoryException catch (e) {
      _onError(e);
      _audioEnabled = false;
    }
    _micDenied = !_audioEnabled;
  }

  Future<T> _duringPrompt<T>(Future<T> Function() prompt) async {
    _permissionPrompt = true;
    try {
      return await prompt();
    } finally {
      _permissionPrompt = false;
    }
  }

  Future<void> _initialize(int generation) async {
    _setStatus(CameraStatus.starting);
    final CaptureCapabilities caps;
    try {
      caps = await _capture.initialize(
        _lens,
        resolution: _options.resolution,
        enableAudio: _audioEnabled,
      );
    } on StoryException catch (e) {
      if (_stale(generation)) {
        return;
      }
      await _handleInitError(e, generation);
      return;
    }
    if (_stale(generation)) {
      // Paused or disposed while starting.
      await _releaseQuietly();
      return;
    }
    _caps = caps;
    _lens = caps.lens;
    _zoom = caps.minZoom;
    if (!flashAvailable) {
      _flash = StoryFlashMode.off;
    } else if (caps.hasFlash) {
      await _applyFlash();
    } else if (_flash == StoryFlashMode.auto) {
      _flash = StoryFlashMode.on;
    }
    _setStatus(CameraStatus.ready);
  }

  Future<void> _handleInitError(StoryException e, int generation) async {
    switch (e.code) {
      case StoryErrorCode.microphonePermissionDenied when _audioEnabled:
        _audioEnabled = false;
        _micDenied = true;
        await _initialize(generation);
      case StoryErrorCode.cameraPermissionDenied:
        PermissionState state;
        try {
          state = await _permissions.checkCamera();
        } on StoryException {
          state = PermissionState.permanentlyDenied;
        }
        _setStatus(
          state == PermissionState.denied
              ? CameraStatus.permissionRequired
              : CameraStatus.permissionBlocked,
        );
      default:
        _onError(e);
        _setStatus(CameraStatus.unavailable);
    }
  }

  bool _stale(int generation) => _disposed || generation != _generation;

  Future<void> _releaseQuietly() async {
    try {
      await _capture.release();
    } on StoryException catch (e) {
      _onError(e);
    }
  }

  // ---------------------------------------------------------------------
  // Lifecycle and interruptions

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_permissionPrompt) {
          return;
        }
        unawaited(_enqueue(_suspend));
      case AppLifecycleState.resumed:
        unawaited(_enqueue(_resume));
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _suspend() async {
    if (_suspended) {
      return;
    }
    _suspended = true;
    _generation++;
    if (_recording) {
      final clip = await _stopForInterruption();
      if (clip != null) {
        _pendingClip = clip;
      }
    }
    await _releaseQuietly();
    _caps = null;
    _setStatus(CameraStatus.paused);
  }

  Future<void> _resume() async {
    if (!_suspended) {
      return;
    }
    _suspended = false;
    if (await _importPending()) {
      return;
    }
    await _openCamera(request: false);
  }

  void _onCaptureEvent(CaptureEvent event) {
    switch (event) {
      case CaptureInterrupted(:final partialRecording):
        _generation++;
        _endRecordingState();
        if (partialRecording != null) {
          _pendingClip = partialRecording;
        }
        _caps = null;
        if (_lifecycle == AppLifecycleState.resumed && !_suspended) {
          _setStatus(CameraStatus.starting);
          unawaited(
            _enqueue(() async {
              if (_pendingClip == null) {
                _showNotice(CameraNotice.interrupted);
              } else if (await _importPending()) {
                return;
              }
              await _openCamera(request: false);
            }),
          );
        } else {
          _suspended = true;
          _setStatus(CameraStatus.paused);
        }
      case CaptureFailed(:final error):
        _generation++;
        _endRecordingState();
        _caps = null;
        _onError(
          error is StoryException
              ? error
              : StoryException(
                  StoryErrorCode.cameraUnavailable,
                  'The camera failed.',
                  error,
                ),
        );
        _setStatus(CameraStatus.unavailable);
    }
  }

  /// Imports a clip kept from an interruption. Returns whether the editor
  /// was opened.
  Future<bool> _importPending() async {
    final clip = _pendingClip;
    if (clip == null) {
      return false;
    }
    _pendingClip = null;
    return _import(
      () => _importer.importCaptured(clip),
      tooShort: CameraNotice.recordingDiscarded,
    );
  }

  Future<CapturedFile?> _stopForInterruption() async {
    await _awaitRecordingStart();
    _endRecordingState();
    try {
      return await _capture.stopRecording();
    } on StoryException catch (e) {
      _onError(e);
      _showNotice(CameraNotice.recordingDiscarded);
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // Capture

  /// Takes a photo and imports it.
  Future<void> takePhoto() async {
    if (!isReady || !photoEnabled || _recording) {
      return;
    }
    _capturing = true;
    final screenFlash = usesScreenFlash && _flash != StoryFlashMode.off;
    if (screenFlash) {
      _screenFlash = true;
      _notify();
      await Future<void>.delayed(screenFlashDelay);
    }
    CapturedFile? file;
    try {
      unawaited(HapticFeedback.lightImpact());
      file = await _capture.takePhoto();
    } on StoryException catch (e) {
      _onError(e);
      _showNotice(CameraNotice.captureFailed);
    } finally {
      _capturing = false;
      _screenFlash = false;
      _notify();
    }
    if (file == null || _disposed) {
      return;
    }
    final captured = file;
    await _import(
      () => _importer.importCaptured(captured),
      tooShort: CameraNotice.recordingTooShort,
    );
  }

  /// Starts a video recording.
  Future<void> startRecording() async {
    if (!isReady || !videoEnabled || _recording) {
      return;
    }
    _recording = true;
    _locked = false;
    elapsed.value = Duration.zero;
    _notify();
    unawaited(HapticFeedback.mediumImpact());
    if (_micDenied && !_micNoticeShown) {
      _micNoticeShown = true;
      _showNotice(CameraNotice.microphoneDenied);
    }
    final starting = _capture.startRecording();
    _startingRecording = starting;
    try {
      await starting;
    } on StoryException catch (e) {
      _endRecordingState();
      _onError(e);
      _showNotice(CameraNotice.captureFailed);
      return;
    } finally {
      if (identical(_startingRecording, starting)) {
        _startingRecording = null;
      }
    }
    if (!_recording || _disposed) {
      return;
    }
    _ticker = Timer.periodic(tick, _onTick);
  }

  void _onTick(Timer timer) {
    final value = tick * timer.tick;
    final max = _constraints.maxVideoDuration;
    elapsed.value = value > max ? max : value;
    if (value >= max) {
      timer.cancel();
      unawaited(stopRecording());
    }
  }

  /// Makes the running recording hands-free.
  void lockRecording() {
    if (!_recording || _locked) {
      return;
    }
    _locked = true;
    unawaited(HapticFeedback.selectionClick());
    _notify();
  }

  /// Stops the recording and imports the clip.
  Future<void> stopRecording() async {
    if (!_recording || _stopping) {
      return;
    }
    _stopping = true;
    try {
      if (!await _awaitRecordingStart()) {
        return;
      }
      _endRecordingState();
      unawaited(HapticFeedback.mediumImpact());
      final CapturedFile file;
      try {
        file = await _capture.stopRecording();
      } on StoryException catch (e) {
        _onError(e);
        _showNotice(CameraNotice.captureFailed);
        return;
      }
      await _import(
        () => _importer.importCaptured(file),
        tooShort: CameraNotice.recordingTooShort,
      );
    } finally {
      _stopping = false;
    }
  }

  /// Waits for a start call still in flight. Returns `false` when it
  /// failed (the recording never began).
  Future<bool> _awaitRecordingStart() async {
    final starting = _startingRecording;
    if (starting == null) {
      return true;
    }
    try {
      await starting;
      return true;
    } on StoryException {
      // Already reported by startRecording.
      return false;
    }
  }

  void _endRecordingState() {
    _ticker?.cancel();
    _ticker = null;
    if (_recording || _locked) {
      _recording = false;
      _locked = false;
      _notify();
    }
  }

  /// Picks with the system picker and imports the result.
  Future<void> pickWithSystemPicker() async {
    if (_busy || _recording) {
      return;
    }
    final PickedMedia? picked;
    try {
      picked = await _gallery.pickWithSystemPicker(
        photos: _constraints.allowPhotos,
        videos: _constraints.allowVideos,
      );
    } on StoryException catch (e) {
      _onError(e);
      _showNotice(_noticeFor(e));
      return;
    }
    if (picked != null) {
      await importPicked(picked);
    }
  }

  /// Imports media picked from the gallery.
  Future<void> importPicked(PickedMedia media) async {
    await _import(
      () => _importer.importPicked(media),
      tooShort: CameraNotice.videoTooShort,
    );
  }

  Future<bool> _import(
    Future<StoryMedia> Function() import, {
    required CameraNotice tooShort,
  }) async {
    _busy = true;
    _notify();
    try {
      final media = await import();
      if (_disposed) {
        return false;
      }
      _onMediaReady(media);
      return true;
    } on MediaTooShortException {
      _showNotice(tooShort);
      return false;
    } on StoryException catch (e) {
      _onError(e);
      _showNotice(_noticeFor(e));
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  static CameraNotice _noticeFor(StoryException e) => switch (e.code) {
    StoryErrorCode.mediaTooLarge => CameraNotice.mediaTooLarge,
    StoryErrorCode.mediaUnsupported => CameraNotice.mediaUnsupported,
    StoryErrorCode.mediaUnavailable ||
    StoryErrorCode.photosPermissionDenied => CameraNotice.mediaUnavailable,
    _ => CameraNotice.captureFailed,
  };

  /// Starts a text-only story: renders a 1080×1920 vertical gradient from
  /// [top] to [bottom] into the session directory and imports it as a
  /// photo.
  Future<void> createTextStory({
    required Color top,
    required Color bottom,
  }) async {
    if (_busy || _recording || _capturing || !_constraints.allowPhotos) {
      return;
    }
    await _import(() async {
      final path = _importer.session.newPath('png', prefix: 'text');
      await writeTextStoryBackground(path, top: top, bottom: bottom);
      return _importer.importCaptured(
        CapturedFile(path: path, type: StoryMediaType.photo, lens: _lens),
      );
    }, tooShort: CameraNotice.captureFailed);
  }

  // ---------------------------------------------------------------------
  // Controls

  /// Selects what a tap on the shutter does. Ignored while recording or
  /// when [mode] is not enabled.
  void setCaptureMode(CameraCaptureMode mode) {
    if (_recording || mode == _mode) {
      return;
    }
    final allowed = switch (mode) {
      CameraCaptureMode.photo => photoEnabled,
      CameraCaptureMode.video => videoEnabled,
    };
    if (!allowed) {
      return;
    }
    _mode = mode;
    unawaited(HapticFeedback.selectionClick());
    _notify();
  }

  /// Cycles the flash: off → auto → on (hardware flash) or off → on
  /// (screen flash).
  Future<void> toggleFlash() async {
    if (!flashAvailable) {
      return;
    }
    final hardware = _caps?.hasFlash ?? false;
    _flash = switch (_flash) {
      StoryFlashMode.off => hardware ? StoryFlashMode.auto : StoryFlashMode.on,
      StoryFlashMode.auto => StoryFlashMode.on,
      StoryFlashMode.on => StoryFlashMode.off,
    };
    _notify();
    if (hardware) {
      await _applyFlash();
    }
  }

  Future<void> _applyFlash() async {
    try {
      await _capture.setFlashMode(_flash);
    } on StoryException catch (e) {
      _onError(e);
    }
  }

  /// Switches between front and rear lens. Not available while recording.
  Future<void> switchLens() async {
    if (!lensSwitchAvailable || !isReady || _recording) {
      return;
    }
    _switching = true;
    _notify();
    final generation = _generation;
    try {
      final caps = await _capture.switchLens();
      if (_stale(generation)) {
        return;
      }
      _caps = caps;
      _lens = caps.lens;
      _zoom = caps.minZoom;
      if (!flashAvailable) {
        _flash = StoryFlashMode.off;
      } else if (caps.hasFlash) {
        await _applyFlash();
      } else if (_flash == StoryFlashMode.auto) {
        _flash = StoryFlashMode.on;
      }
    } on StoryException catch (e) {
      if (_stale(generation)) {
        return;
      }
      _onError(e);
      _caps = null;
      _setStatus(CameraStatus.unavailable);
    } finally {
      _switching = false;
      _notify();
    }
  }

  /// Sets the zoom factor (clamped). Calls to the camera are coalesced.
  void setZoom(double value) {
    final caps = _caps;
    if (!_options.enableZoom || caps == null || _status != CameraStatus.ready) {
      return;
    }
    final clamped = value.clamp(caps.minZoom, caps.maxZoom);
    if (clamped == _zoom) {
      return;
    }
    _zoom = clamped;
    _notify();
    _pendingZoom = clamped;
    if (!_zoomInFlight) {
      unawaited(_flushZoom());
    }
  }

  Future<void> _flushZoom() async {
    _zoomInFlight = true;
    try {
      while (_pendingZoom != null && !_disposed) {
        final value = _pendingZoom!;
        _pendingZoom = null;
        try {
          await _capture.setZoom(value);
        } on StoryException catch (e) {
          _onError(e);
          _pendingZoom = null;
        }
      }
    } finally {
      _zoomInFlight = false;
    }
  }

  /// Focuses and meters where the user tapped.
  ///
  /// [viewPoint] is 0–1 in the visible preview area, whose width / height
  /// is [viewAspectRatio]. The preview covers that area, so the point is
  /// mapped into the (partly cropped) camera frame before it is sent.
  Future<void> focusAt(
    Offset viewPoint, {
    required double viewAspectRatio,
  }) async {
    final caps = _caps;
    if (_status != CameraStatus.ready || _capturing || caps == null) {
      return;
    }
    _focusPoint = viewPoint;
    _focusId++;
    _focusTimer?.cancel();
    _focusTimer = Timer(focusMarkerDuration, () {
      _focusPoint = null;
      _notify();
    });
    _notify();
    try {
      await _capture.focusAt(
        coverToFrame(
          viewPoint,
          viewAspectRatio: viewAspectRatio,
          frameAspectRatio: caps.previewAspectRatio,
        ),
      );
    } on StoryException catch (e) {
      _onError(e);
    }
  }

  /// Maps a 0–1 point of a view to the 0–1 point of a frame drawn into it
  /// with `BoxFit.cover` (centred crop).
  static Offset coverToFrame(
    Offset viewPoint, {
    required double viewAspectRatio,
    required double frameAspectRatio,
  }) {
    if (viewAspectRatio <= 0 || frameAspectRatio <= 0) {
      return viewPoint;
    }
    var x = viewPoint.dx;
    var y = viewPoint.dy;
    if (frameAspectRatio > viewAspectRatio) {
      // Frame is wider: its sides are cropped.
      x = 0.5 + (x - 0.5) * (viewAspectRatio / frameAspectRatio);
    } else {
      // Frame is taller: top and bottom are cropped.
      y = 0.5 + (y - 0.5) * (frameAspectRatio / viewAspectRatio);
    }
    return Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
  }

  void _showNotice(CameraNotice value) {
    if (_disposed) {
      return;
    }
    _noticeTimer?.cancel();
    notice.value = value;
    _noticeTimer = Timer(noticeDuration, () => notice.value = null);
  }

  void _setStatus(CameraStatus value) {
    if (_disposed) {
      return;
    }
    _status = value;
    notifyListeners();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
    }
    unawaited(_events?.cancel());
    _ticker?.cancel();
    _noticeTimer?.cancel();
    _focusTimer?.cancel();
    final recording = _recording;
    unawaited(_shutDown(discardRecording: recording));
    elapsed.dispose();
    notice.dispose();
    super.dispose();
  }

  /// Stops and deletes an unfinished recording (it lives outside the
  /// session directory), then disposes the camera.
  Future<void> _shutDown({required bool discardRecording}) async {
    if (discardRecording) {
      try {
        await _awaitRecordingStart();
        final file = await _capture.stopRecording();
        final f = File(file.path);
        if (f.existsSync()) {
          await f.delete();
        }
      } on StoryException catch (e) {
        _onError(e);
      } on FileSystemException catch (e, s) {
        _onError(
          StoryException(
            StoryErrorCode.unknown,
            'Could not delete a discarded recording.',
            e,
            s,
          ),
        );
      }
    }
    try {
      await _capture.dispose();
    } on StoryException catch (e) {
      _onError(e);
    }
  }
}
