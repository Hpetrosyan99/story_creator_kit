import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/story_scope.dart';
import '../../ui/story_icon.dart';
import '../../ui/story_surface.dart';
import '../camera_controller.dart';
import '../camera_keys.dart';

/// Horizontal drag (to the left) that locks a held recording.
const double kShutterLockDistance = 56;

/// Vertical drag (upwards) that zooms from minimum to maximum.
const double kShutterZoomDragDistance = 320;

/// Delay before a press turns into a recording.
const Duration kShutterHoldDelay = Duration(milliseconds: 250);

/// The shutter: the design's 60 px shutter icon (red while recording) with
/// an accent progress ring around it while a recording runs.
///
/// In photo mode a tap takes a photo; in video mode a tap starts and stops
/// a hands-free recording. In both modes pressing and holding records
/// (drag up to zoom, drag left onto the lock to keep recording
/// hands-free). While media is imported the shutter is dimmed.
///
/// Screen readers get a tap action for the primary function and, in photo
/// mode, a long press action that starts a hands-free recording.
class ShutterButton extends StatefulWidget {
  /// Creates the shutter.
  const ShutterButton({required this.controller, super.key});

  /// Camera state.
  final StoryCameraController controller;

  /// Side of the tap target (larger than the 60 px icon).
  static const double hitSize = 80;

  /// Diameter of the recording progress ring.
  static const double ringSize = 72;

  @override
  State<ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<ShutterButton> {
  double _baseZoom = 1;
  bool _holding = false;

  StoryCameraController get _c => widget.controller;

  bool get _photoMode =>
      _c.photoEnabled &&
      (_c.captureMode == CameraCaptureMode.photo || !_c.videoEnabled);

  void _onTap() {
    if (_c.isRecording) {
      _c.stopRecording();
    } else if (_photoMode) {
      _c.takePhoto();
    } else if (_c.videoEnabled) {
      _startHandsFree();
    }
  }

  Future<void> _startHandsFree() async {
    await _c.startRecording();
    _c.lockRecording();
  }

  void _onHoldStart(LongPressStartDetails details) {
    if (!_c.videoEnabled || _c.isRecording) {
      return;
    }
    _holding = true;
    _baseZoom = _c.zoom;
    _c.startRecording();
  }

  void _onHoldMove(LongPressMoveUpdateDetails details) {
    if (!_holding || !_c.isRecording || _c.isLocked) {
      return;
    }
    final offset = details.localOffsetFromOrigin;
    if (offset.dx <= -kShutterLockDistance) {
      _c.lockRecording();
      return;
    }
    final caps = _c.capabilities;
    if (caps != null) {
      final up = math.max(0, -offset.dy);
      _c.setZoom(
        _baseZoom +
            up / kShutterZoomDragDistance * (caps.maxZoom - caps.minZoom),
      );
    }
  }

  void _onHoldEndDetails(LongPressEndDetails details) => _onHoldEnd();

  void _onHoldEnd() {
    if (!_holding) {
      return;
    }
    _holding = false;
    if (!_c.isLocked) {
      _c.stopRecording();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final strings = scope.strings.camera;
    final recording = _c.isRecording;
    final enabled = recording || _c.isReady;
    final animate = !MediaQuery.disableAnimationsOf(context);
    final duration = animate
        ? const Duration(milliseconds: 180)
        : Duration.zero;
    final photoMode = _photoMode;
    final String label;
    final String? hint;
    if (recording) {
      label = strings.stopRecording;
      hint = null;
    } else if (photoMode) {
      label = strings.takePhoto;
      hint = _c.videoEnabled ? strings.shutterHint : null;
    } else {
      label = strings.startRecording;
      hint = strings.videoModeHint;
    }
    final canHold = _c.videoEnabled && photoMode && !recording;
    return Semantics(
      key: CameraKeys.shutter,
      button: true,
      enabled: enabled,
      label: label,
      hint: hint,
      onTap: enabled ? _onTap : null,
      onLongPress: enabled && canHold ? _startHandsFree : null,
      child: RawGestureDetector(
        excludeFromSemantics: true,
        behavior: HitTestBehavior.opaque,
        gestures: {
          TapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                TapGestureRecognizer.new,
                (r) => r.onTap = enabled ? _onTap : null,
              ),
          if (_c.videoEnabled)
            LongPressGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  LongPressGestureRecognizer
                >(
                  () => LongPressGestureRecognizer(duration: kShutterHoldDelay),
                  (r) {
                    r
                      ..onLongPressStart = enabled ? _onHoldStart : null
                      ..onLongPressMoveUpdate = _onHoldMove
                      ..onLongPressCancel = _onHoldEnd
                      ..onLongPressEnd = _onHoldEndDetails;
                  },
                ),
        },
        child: SizedBox.square(
          dimension: ShutterButton.hitSize,
          child: Center(
            child: SizedBox.square(
              dimension: ShutterButton.ringSize,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (recording)
                    ValueListenableBuilder<Duration>(
                      valueListenable: _c.elapsed,
                      builder: (context, elapsed, _) => CustomPaint(
                        painter: ShutterRingPainter(
                          progress:
                              (elapsed.inMilliseconds /
                                      math.max(
                                        1,
                                        _c.maxDuration.inMilliseconds,
                                      ))
                                  .clamp(0.0, 1.0),
                          track: theme.onSurface.withValues(alpha: 0.3),
                          progressColor: theme.accent,
                          strokeWidth: 3,
                        ),
                      ),
                    ),
                  Center(
                    child: AnimatedOpacity(
                      duration: duration,
                      opacity: _c.isBusy ? 0.4 : 1,
                      child: StoryIcon(
                        recording
                            ? StoryIcons.shutterRecording
                            : StoryIcons.shutterPhoto,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the shutter ring and the recording progress arc.
class ShutterRingPainter extends CustomPainter {
  /// Creates the painter.
  const ShutterRingPainter({
    required this.progress,
    required this.track,
    required this.progressColor,
    required this.strokeWidth,
  });

  /// 0–1 of the maximum recording length.
  final double progress;

  /// Ring colour.
  final Color track;

  /// Progress arc colour.
  final Color progressColor;

  /// Ring width.
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final ring = rect.deflate(strokeWidth / 2);
    canvas.drawOval(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = track,
    );
    if (progress > 0) {
      canvas.drawArc(
        ring,
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = progressColor,
      );
    }
  }

  @override
  bool shouldRepaint(ShutterRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.track != track ||
      oldDelegate.progressColor != progressColor ||
      oldDelegate.strokeWidth != strokeWidth;
}

/// The lock target shown in place of the gallery thumbnail while a
/// recording is held.
class RecordingLockTarget extends StatelessWidget {
  /// Creates the lock target.
  const RecordingLockTarget({required this.onLock, super.key});

  /// Locks the recording (tap alternative to dragging).
  final VoidCallback onLock;

  /// Side of the target (the gallery thumbnail's size).
  static const double size = 60;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    return Semantics(
      key: CameraKeys.lock,
      button: true,
      label: scope.strings.camera.lockRecording,
      excludeSemantics: true,
      onTap: onLock,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onLock,
        child: SizedBox.square(
          dimension: size,
          child: StorySurface(
            fill: theme.pillBackground,
            radius: size / 2,
            child: Center(
              child: Icon(
                Icons.lock_outline_rounded,
                size: 24,
                color: theme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
