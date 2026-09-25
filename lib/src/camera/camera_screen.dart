import 'dart:async';

import 'package:flutter/material.dart';

import '../api/config/capture_options.dart';
import '../api/strings/story_creator_strings.dart';
import '../core/media_import.dart';
import '../core/story_scope.dart';
import '../gallery/gallery_sheet.dart';
import '../model/story_media.dart';
import 'camera_controller.dart';
import 'camera_keys.dart';
import 'widgets/camera_switch_button.dart';
import 'widgets/camera_unavailable_view.dart';
import 'widgets/flash_toggle.dart';
import 'widgets/focus_marker.dart';
import 'widgets/gallery_shortcut.dart';
import 'widgets/notice_toast.dart';
import 'widgets/permission_prompt.dart';
import 'widgets/recording_indicator.dart';
import 'widgets/round_icon_button.dart';
import 'widgets/shutter_button.dart';
import 'widgets/zoom_indicator.dart';

/// Colour of the front-camera screen flash. It lights the user's face, so
/// it is white regardless of the theme.
const Color kScreenFlashColor = Color(0xFFFFFFFF);

/// Camera with gallery access. Reports imported media or closing.
class CameraScreen extends StatefulWidget {
  /// Creates the camera screen.
  const CameraScreen({
    required this.onMediaReady,
    required this.onClose,
    super.key,
  });

  /// Called with validated, imported media (inside the session directory).
  final ValueChanged<StoryMedia> onMediaReady;

  /// Called when the user closes the creator from the camera.
  final VoidCallback onClose;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  StoryCameraController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) {
      return;
    }
    final scope = StoryScope.of(context);
    final services = scope.services;
    final controller = StoryCameraController(
      capture: services.createCapture(),
      permissions: services.permissions,
      gallery: services.gallery,
      importer: MediaImporter(
        inspector: services.inspector,
        session: scope.session,
        constraints: scope.config.constraints,
      ),
      options: scope.config.capture,
      constraints: scope.config.constraints,
      onMediaReady: (media) => widget.onMediaReady(media),
      onError: scope.reportError,
    );
    _controller = controller;
    unawaited(controller.start());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _openGallery() async {
    final controller = _controller;
    if (controller == null || controller.isBusy || controller.isRecording) {
      return;
    }
    final gallery = StoryScope.read(context).services.gallery;
    if (!gallery.supportsGrid) {
      await controller.pickWithSystemPicker();
      return;
    }
    final picked = await GallerySheet.open(context);
    if (picked != null && mounted) {
      await controller.importPicked(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    final galleryEnabled =
        StoryScope.of(context).config.capture.galleryMode !=
        GalleryMode.disabled;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _CameraLayout(
        controller: controller,
        onClose: widget.onClose,
        onOpenGallery: galleryEnabled ? _openGallery : null,
      ),
    );
  }
}

class _CameraLayout extends StatelessWidget {
  const _CameraLayout({
    required this.controller,
    required this.onClose,
    required this.onOpenGallery,
  });

  final StoryCameraController controller;
  final VoidCallback onClose;
  final VoidCallback? onOpenGallery;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: theme.background),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Center(
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(theme.cornerRadius * 1.5),
                  child: ColoredBox(
                    color: theme.surface,
                    child: _CameraCard(
                      controller: controller,
                      onClose: onClose,
                      onOpenGallery: onOpenGallery,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (controller.screenFlashVisible)
          const Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                key: CameraKeys.screenFlash,
                color: kScreenFlashColor,
              ),
            ),
          ),
      ],
    );
  }
}

class _CameraCard extends StatelessWidget {
  const _CameraCard({
    required this.controller,
    required this.onClose,
    required this.onOpenGallery,
  });

  final StoryCameraController controller;
  final VoidCallback onClose;
  final VoidCallback? onOpenGallery;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final strings = scope.strings;
    final c = controller;
    final recording = c.isRecording;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: _CameraBody(controller: c)),
        Positioned(
          top: 8,
          left: 8,
          right: 8,
          child: Row(
            children: [
              if (recording)
                const SizedBox.square(dimension: 48)
              else
                RoundIconButton(
                  key: CameraKeys.close,
                  icon: Icons.close_rounded,
                  label: strings.common.close,
                  onPressed: onClose,
                ),
              Expanded(
                child: Center(
                  child: recording
                      ? RecordingIndicator(elapsed: c.elapsed)
                      : const SizedBox.shrink(),
                ),
              ),
              if (c.flashAvailable)
                FlashToggle(
                  mode: c.flashMode,
                  onPressed: c.isReady || recording ? c.toggleFlash : null,
                )
              else
                const SizedBox.square(dimension: 48),
            ],
          ),
        ),
        Positioned(
          top: 68,
          left: 16,
          right: 16,
          child: Center(
            child: ValueListenableBuilder<CameraNotice?>(
              valueListenable: c.notice,
              builder: (context, notice, _) => notice == null
                  ? const SizedBox.shrink()
                  : NoticeToast(
                      key: CameraKeys.notice,
                      message: _noticeText(strings, notice),
                    ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 12,
          child: _BottomControls(controller: c, onOpenGallery: onOpenGallery),
        ),
        if (c.isBusy)
          Positioned.fill(
            child: ColoredBox(
              key: CameraKeys.busy,
              color: theme.scrim,
              child: Center(
                child: Semantics(
                  label: strings.camera.importing,
                  liveRegion: true,
                  excludeSemantics: true,
                  child: SizedBox.square(
                    dimension: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: theme.accent,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _noticeText(StoryCreatorStrings strings, CameraNotice notice) {
    final camera = strings.camera;
    return switch (notice) {
      CameraNotice.microphoneDenied => camera.microphonePermissionMessage,
      CameraNotice.recordingTooShort => camera.recordingTooShort,
      CameraNotice.recordingDiscarded => camera.recordingDiscarded,
      CameraNotice.interrupted => camera.cameraInterrupted,
      CameraNotice.videoTooShort => camera.videoTooShort,
      CameraNotice.mediaTooLarge => camera.mediaTooLarge,
      CameraNotice.mediaUnsupported => camera.mediaUnsupported,
      CameraNotice.mediaUnavailable => camera.mediaUnavailable,
      CameraNotice.captureFailed => strings.common.genericError,
    };
  }
}

class _CameraBody extends StatelessWidget {
  const _CameraBody({required this.controller});

  final StoryCameraController controller;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final strings = scope.strings;
    final c = controller;
    // Leaves room for the top bar and the shutter row.
    const padding = EdgeInsets.fromLTRB(16, 64, 16, 150);
    switch (c.status) {
      case CameraStatus.permissionRequired:
        return Padding(
          padding: padding,
          child: PermissionPrompt(
            key: CameraKeys.permissionPrompt,
            icon: Icons.photo_camera_outlined,
            title: strings.camera.cameraPermissionTitle,
            message: strings.camera.cameraPermissionMessage,
            actionLabel: strings.camera.allowAccess,
            onAction: c.requestPermission,
          ),
        );
      case CameraStatus.permissionBlocked:
        return Padding(
          padding: padding,
          child: PermissionPrompt(
            key: CameraKeys.permissionPrompt,
            icon: Icons.photo_camera_outlined,
            title: strings.camera.cameraPermissionTitle,
            message: strings.camera.cameraBlockedMessage,
            actionLabel: strings.common.openSettings,
            onAction: c.openSettings,
          ),
        );
      case CameraStatus.unavailable:
        return Padding(
          padding: padding,
          child: CameraUnavailableView(onRetry: c.retry),
        );
      case CameraStatus.ready:
        if (c.capture.isInitialized) {
          return _LivePreview(controller: c);
        }
        return const CameraStartingView();
      case CameraStatus.checkingPermission:
      case CameraStatus.starting:
      case CameraStatus.paused:
        return const CameraStartingView();
    }
  }
}

class _LivePreview extends StatefulWidget {
  const _LivePreview({required this.controller});

  final StoryCameraController controller;

  @override
  State<_LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends State<_LivePreview> {
  double _baseZoom = 1;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final label = StoryScope.of(context).strings.camera.cameraPreview;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final focus = c.focusPoint;
        return GestureDetector(
          key: CameraKeys.preview,
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => c.focusAt(
            Offset(
              details.localPosition.dx / size.width,
              details.localPosition.dy / size.height,
            ),
            viewAspectRatio: size.width / size.height,
          ),
          onScaleStart: (_) => _baseZoom = c.zoom,
          onScaleUpdate: (details) {
            if (details.pointerCount >= 2) {
              c.setZoom(_baseZoom * details.scale);
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Semantics(
                label: label,
                image: true,
                excludeSemantics: true,
                child: c.capture.buildPreview(),
              ),
              if (focus != null)
                Positioned(
                  left: focus.dx * size.width - FocusMarker.size / 2,
                  top: focus.dy * size.height - FocusMarker.size / 2,
                  child: FocusMarker(key: ValueKey(c.focusId)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.controller,
    required this.onOpenGallery,
  });

  final StoryCameraController controller;
  final VoidCallback? onOpenGallery;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final strings = scope.strings.camera;
    final c = controller;
    final recording = c.isRecording;
    final caps = c.capabilities;
    final showShutter =
        (c.photoEnabled || c.videoEnabled) &&
        switch (c.status) {
          CameraStatus.ready ||
          CameraStatus.starting ||
          CameraStatus.paused ||
          CameraStatus.checkingPermission => true,
          CameraStatus.permissionRequired ||
          CameraStatus.permissionBlocked ||
          CameraStatus.unavailable => false,
        };
    final String? hint;
    if (c.isLocked) {
      hint = strings.recordingLockedHint;
    } else if (!recording &&
        c.status == CameraStatus.ready &&
        c.photoEnabled &&
        c.videoEnabled) {
      hint = strings.shutterHint;
    } else {
      hint = null;
    }
    final Widget left;
    if (recording && !c.isLocked) {
      left = RecordingLockTarget(onLock: c.lockRecording);
    } else if (!recording && onOpenGallery != null) {
      left = GalleryShortcut(onPressed: c.isBusy ? null : onOpenGallery);
    } else {
      left = const SizedBox.square(dimension: 48);
    }
    final right = !recording && c.lensSwitchAvailable
        ? CameraSwitchButton(onPressed: c.isReady ? c.switchLens : null)
        : const SizedBox.square(dimension: 48);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (caps != null &&
            c.status == CameraStatus.ready &&
            c.zoom > caps.minZoom + 0.05)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ZoomIndicator(zoom: c.zoom),
          ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              hint,
              textAlign: TextAlign.center,
              style: theme.captionStyle.copyWith(color: theme.onSurface),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            SizedBox(width: 64, child: Center(child: left)),
            if (showShutter)
              ShutterButton(controller: c)
            else
              const SizedBox.square(dimension: 100),
            SizedBox(width: 64, child: Center(child: right)),
          ],
        ),
      ],
    );
  }
}
