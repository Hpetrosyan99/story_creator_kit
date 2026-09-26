import 'dart:async';

import 'package:flutter/material.dart';

import '../api/config/capture_options.dart';
import '../api/strings/story_creator_strings.dart';
import '../core/media_import.dart';
import '../core/story_scope.dart';
import '../gallery/gallery_sheet.dart';
import '../model/story_media.dart';
import '../ui/story_icon.dart';
import '../ui/story_nav_button.dart';
import '../ui/story_pill_toggle.dart';
import '../ui/story_stage.dart';
import 'camera_controller.dart';
import 'camera_keys.dart';
import 'text_story_background.dart';
import 'widgets/camera_cta_column.dart';
import 'widgets/camera_switch_button.dart';
import 'widgets/camera_unavailable_view.dart';
import 'widgets/flash_toggle.dart';
import 'widgets/focus_marker.dart';
import 'widgets/gallery_shortcut.dart';
import 'widgets/notice_toast.dart';
import 'widgets/permission_prompt.dart';
import 'widgets/recording_indicator.dart';
import 'widgets/shutter_button.dart';
import 'widgets/zoom_indicator.dart';

/// Colour of the front-camera screen flash. It lights the user's face, so
/// it is white regardless of the theme.
const Color kScreenFlashColor = Color(0xFFFFFFFF);

/// Camera with gallery access, laid out on the shared [StoryStage]: the
/// live preview in the rounded card, close and "Video | Photo" on top, the
/// flash and text buttons on the left, gallery, shutter and lens switch at
/// the bottom. Reports imported media or closing.
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

  Future<void> _createTextStory() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final scope = StoryScope.read(context);
    final (top, bottom) = textStoryColors(scope.config.editor, scope.theme);
    await controller.createTextStory(top: top, bottom: bottom);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    final config = StoryScope.of(context).config;
    final galleryEnabled = config.capture.galleryMode != GalleryMode.disabled;
    final textEnabled =
        config.editor.enableText && config.constraints.allowPhotos;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          StoryStage(
            card: _CameraCard(
              controller: controller,
              onClose: widget.onClose,
              onOpenGallery: galleryEnabled ? _openGallery : null,
              onTextStory: textEnabled ? _createTextStory : null,
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
      ),
    );
  }
}

/// Everything inside the rounded camera card: preview (or a state view),
/// the nav row, the CTA column and the bottom row.
class _CameraCard extends StatelessWidget {
  const _CameraCard({
    required this.controller,
    required this.onClose,
    required this.onOpenGallery,
    required this.onTextStory,
  });

  final StoryCameraController controller;
  final VoidCallback onClose;
  final VoidCallback? onOpenGallery;
  final VoidCallback? onTextStory;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final strings = scope.strings;
    final c = controller;
    final recording = c.isRecording;
    final cameraShown = switch (c.status) {
      CameraStatus.ready ||
      CameraStatus.starting ||
      CameraStatus.paused ||
      CameraStatus.checkingPermission => true,
      CameraStatus.permissionRequired ||
      CameraStatus.permissionBlocked ||
      CameraStatus.unavailable => false,
    };
    final textStory = onTextStory;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: ColoredBox(
            color: theme.surface,
            child: _CameraBody(controller: c),
          ),
        ),
        // Nav row: 16 / 12 padding around the 44 px button (48 px target).
        if (!recording)
          Positioned(
            key: const ValueKey('close'),
            top: 10,
            left: 14,
            child: StoryNavButton(
              key: CameraKeys.close,
              icon: StoryIcons.close,
              label: strings.common.close,
              onPressed: onClose,
            ),
          ),
        if (cameraShown && c.captureModeSelectable && !recording)
          Positioned(
            key: const ValueKey('mode'),
            top: 10,
            right: 16,
            child: _CaptureModeToggle(controller: c),
          ),
        if (recording)
          Positioned(
            key: const ValueKey('timer'),
            top: 17,
            left: 64,
            right: 64,
            child: Center(child: RecordingIndicator(elapsed: c.elapsed)),
          ),
        Positioned(
          key: const ValueKey('notice'),
          top: 72,
          left: 56,
          right: 56,
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
        // CTA column: icons at x = 16, vertically centred.
        Positioned(
          key: const ValueKey('cta'),
          left: 2,
          top: 0,
          bottom: 0,
          child: Center(
            child: CameraCtaColumn(
              children: [
                if (cameraShown && c.flashAvailable)
                  FlashToggle(
                    mode: c.flashMode,
                    onPressed: c.isReady || recording ? c.toggleFlash : null,
                  ),
                if (textStory != null && !recording)
                  CameraCtaButton(
                    key: CameraKeys.textStory,
                    icon: StoryIcons.text,
                    label: strings.camera.textStory,
                    onPressed: c.isBusy ? null : textStory,
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          key: const ValueKey('feedback'),
          left: 0,
          right: 0,
          bottom: 16 + _BottomRow.rowHeight + 12,
          child: _CaptureFeedback(controller: c),
        ),
        Positioned(
          key: const ValueKey('bottom'),
          left: 14,
          right: 14,
          bottom: 16 - (_BottomRow.height - _BottomRow.rowHeight) / 2,
          height: _BottomRow.height,
          child: _BottomRow(
            controller: c,
            showShutter: cameraShown && (c.photoEnabled || c.videoEnabled),
            onOpenGallery: onOpenGallery,
          ),
        ),
        if (c.isBusy)
          Positioned.fill(
            child: AbsorbPointer(
              child: Semantics(
                key: CameraKeys.busy,
                label: strings.camera.importing,
                liveRegion: true,
                container: true,
                child: const SizedBox.expand(),
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

/// The "Video | Photo" toggle. The pill's own options are small, so the
/// whole 48 px high area is one control: tapping an option selects it,
/// tapping elsewhere (or activating it with a screen reader) switches to
/// the other mode.
class _CaptureModeToggle extends StatelessWidget {
  const _CaptureModeToggle({required this.controller});

  final StoryCameraController controller;

  @override
  Widget build(BuildContext context) {
    final strings = StoryScope.of(context).strings.camera;
    final c = controller;
    final mode = c.captureMode;
    final other = mode == CameraCaptureMode.photo
        ? CameraCaptureMode.video
        : CameraCaptureMode.photo;
    void toggle() => c.setCaptureMode(other);
    return Semantics(
      key: CameraKeys.captureMode,
      button: true,
      label: strings.captureMode,
      value: mode == CameraCaptureMode.photo
          ? strings.photoMode
          : strings.videoMode,
      excludeSemantics: true,
      onTap: toggle,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: toggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Center(
            widthFactor: 1,
            child: StoryPillToggle<CameraCaptureMode>(
              options: [
                (CameraCaptureMode.video, strings.videoMode),
                (CameraCaptureMode.photo, strings.photoMode),
              ],
              selected: mode,
              onChanged: c.setCaptureMode,
            ),
          ),
        ),
      ),
    );
  }
}

/// Zoom factor and the hands-free recording hint, above the shutter.
class _CaptureFeedback extends StatelessWidget {
  const _CaptureFeedback({required this.controller});

  final StoryCameraController controller;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final c = controller;
    final caps = c.capabilities;
    final showZoom =
        caps != null &&
        c.status == CameraStatus.ready &&
        c.zoom > caps.minZoom + 0.05;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showZoom)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ZoomIndicator(zoom: c.zoom),
          ),
        if (c.isLocked)
          Text(
            scope.strings.camera.recordingLockedHint,
            textAlign: TextAlign.center,
            style: theme.bodyStyle.copyWith(
              shadows: [
                Shadow(
                  color: theme.scrim,
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Gallery thumbnail (or the lock target while holding), shutter and lens
/// switch. [height] leaves room for the shutter's larger tap target; the
/// visual row is [rowHeight] high.
class _BottomRow extends StatelessWidget {
  const _BottomRow({
    required this.controller,
    required this.showShutter,
    required this.onOpenGallery,
  });

  final StoryCameraController controller;
  final bool showShutter;
  final VoidCallback? onOpenGallery;

  static const double rowHeight = 60;
  static const double height = ShutterButton.hitSize;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final recording = c.isRecording;
    final Widget? left;
    if (recording && !c.isLocked) {
      left = RecordingLockTarget(onLock: c.lockRecording);
    } else if (!recording && onOpenGallery != null) {
      left = GalleryShortcut(onPressed: c.isBusy ? null : onOpenGallery);
    } else {
      left = null;
    }
    final showSwitch = !recording && c.lensSwitchAvailable;
    return Stack(
      children: [
        if (left != null)
          Positioned(left: 2, top: 0, bottom: 0, child: Center(child: left)),
        if (showShutter) Center(child: ShutterButton(controller: c)),
        if (showSwitch)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: CameraSwitchButton(
                onPressed: c.isReady ? c.switchLens : null,
              ),
            ),
          ),
      ],
    );
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
    // Leaves room for the nav row, the CTA column and the bottom row.
    const padding = EdgeInsets.fromLTRB(48, 64, 48, 96);
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
    final scope = StoryScope.of(context);
    final scrim = scope.theme.scrim;
    final label = scope.strings.camera.cameraPreview;
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
              // Design scrim: transparent on the left to 40 % black on the
              // right.
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [scrim.withValues(alpha: 0), scrim],
                    ),
                  ),
                ),
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
