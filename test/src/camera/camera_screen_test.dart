import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/services.dart';
import 'package:story_creator_kit/src/camera/camera_keys.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

import '../../fakes/fake_services.dart';
import 'camera_test_harness.dart';

void main() {
  const strings = CameraStrings();
  final shutter = find.byKey(CameraKeys.shutter);

  late CameraHarness h;

  tearDown(() => h.dispose());

  group('capture', () {
    testWidgets('tap takes a photo and reports the probed media', (
      tester,
    ) async {
      h = CameraHarness(
        inspector: FakeMediaInspector(
          defaultProbe: const MediaProbe(
            width: 1200,
            height: 1600,
            fileSizeBytes: 4,
          ),
        ),
      );
      await h.pump(tester);
      expect(find.byKey(CameraKeys.preview), findsOneWidget);

      await tester.tap(shutter);
      await settle(tester);

      final media = h.media.single;
      expect(media.type, StoryMediaType.photo);
      expect(media.source, StorySourceKind.camera);
      expect(media.width, 1200);
      expect(media.height, 1600);
      expect(media.path, startsWith(h.session.directory.path));
      expect(File(media.path).existsSync(), isTrue);
      expect(h.capture.calls, contains('photo'));
    });

    testWidgets('hold records; release stops and reports the probed clip', (
      tester,
    ) async {
      h = CameraHarness(
        inspector: FakeMediaInspector(
          defaultProbe: videoProbe(const Duration(milliseconds: 4200)),
        ),
      );
      await h.pump(tester);

      final gesture = await holdShutter(tester, shutter);
      expect(h.capture.isRecording, isTrue);
      expect(find.byKey(CameraKeys.recordingIndicator), findsOneWidget);
      expect(find.byKey(CameraKeys.lock), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('00:02'), findsOneWidget);

      await gesture.up();
      await settle(tester);

      expect(
        h.capture.calls,
        containsAllInOrder(['startRecording', 'stopRecording']),
      );
      final media = h.media.single;
      expect(media.type, StoryMediaType.video);
      // The probed duration wins over the service's own measurement.
      expect(media.duration, const Duration(milliseconds: 4200));
      expect(media.hasAudio, isTrue);
      expect(h.capture.lastEnableAudio, isTrue);
    });

    testWidgets('recording stops by itself at maxVideoDuration', (
      tester,
    ) async {
      h = CameraHarness(
        config: const StoryCreatorConfig(
          constraints: MediaConstraints(maxVideoDuration: Duration(seconds: 3)),
        ),
        inspector: FakeMediaInspector(
          defaultProbe: videoProbe(const Duration(seconds: 3)),
        ),
      );
      await h.pump(tester);

      final gesture = await holdShutter(tester, shutter);
      await tester.pump(const Duration(milliseconds: 2900));
      expect(h.capture.calls, isNot(contains('stopRecording')));

      await tester.pump(const Duration(milliseconds: 200));
      expect(h.capture.calls, contains('stopRecording'));
      await settle(tester);
      expect(h.media.single.duration, const Duration(seconds: 3));

      // Releasing afterwards does nothing.
      await gesture.up();
      await settle(tester);
      expect(h.capture.calls.where((c) => c == 'stopRecording'), hasLength(1));
      expect(h.media, hasLength(1));
    });

    testWidgets('a recording shorter than the minimum is discarded', (
      tester,
    ) async {
      h = CameraHarness(
        inspector: FakeMediaInspector(
          defaultProbe: videoProbe(const Duration(milliseconds: 400)),
        ),
      );
      await h.pump(tester);

      final gesture = await holdShutter(tester, shutter);
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await settle(tester);

      expect(h.media, isEmpty);
      expect(find.text(strings.recordingTooShort), findsOneWidget);
      expect(h.session.directory.listSync(), isEmpty);

      await tester.pump(const Duration(seconds: 3));
      expect(find.text(strings.recordingTooShort), findsNothing);
    });

    testWidgets('dragging onto the lock keeps recording; tap stops', (
      tester,
    ) async {
      h = CameraHarness(
        inspector: FakeMediaInspector(
          defaultProbe: videoProbe(const Duration(seconds: 2)),
        ),
      );
      await h.pump(tester);

      final gesture = await holdShutter(tester, shutter);
      await gesture.moveBy(const Offset(-80, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(h.capture.isRecording, isTrue);
      expect(find.text(strings.recordingLockedHint), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.tap(shutter);
      await settle(tester);
      expect(h.capture.isRecording, isFalse);
      expect(h.media.single.type, StoryMediaType.video);
    });

    testWidgets('dragging up while holding zooms', (tester) async {
      h = CameraHarness(
        inspector: FakeMediaInspector(
          defaultProbe: videoProbe(const Duration(seconds: 2)),
        ),
      );
      await h.pump(tester);

      final gesture = await holdShutter(tester, shutter);
      await gesture.moveBy(const Offset(0, -160));
      await tester.pump();
      await tester.pump();
      expect(h.capture.zoom, greaterThan(1));
      expect(find.byKey(CameraKeys.zoom), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await settle(tester);
    });

    testWidgets('video-only mode: tap starts and tap stops', (tester) async {
      h = CameraHarness(
        config: const StoryCreatorConfig(
          capture: CaptureOptions(enablePhoto: false),
        ),
        inspector: FakeMediaInspector(
          defaultProbe: videoProbe(const Duration(seconds: 2)),
        ),
      );
      await h.pump(tester);

      await tester.tap(shutter);
      await tester.pump();
      expect(h.capture.isRecording, isTrue);
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(shutter);
      await settle(tester);
      expect(h.media.single.type, StoryMediaType.video);
      expect(h.capture.calls, isNot(contains('photo')));
    });

    testWidgets('photo-only mode ignores holding', (tester) async {
      h = CameraHarness(
        config: const StoryCreatorConfig(
          capture: CaptureOptions(enableVideo: false),
        ),
      );
      await h.pump(tester);

      final gesture = await holdShutter(tester, shutter);
      await gesture.up();
      await settle(tester);
      expect(h.capture.calls, isNot(contains('startRecording')));
      expect(h.capture.lastEnableAudio, isFalse);
    });

    testWidgets('a failed capture shows a notice and reports the error', (
      tester,
    ) async {
      h = CameraHarness();
      h.capture.photoError = const StoryException(StoryErrorCode.captureFailed);
      await h.pump(tester);

      await tester.tap(shutter);
      await settle(tester);

      expect(h.media, isEmpty);
      expect(find.text(const CommonStrings().genericError), findsOneWidget);
      expect(h.events.single.error?.code, StoryErrorCode.captureFailed);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('controls', () {
    testWidgets('flash cycles off → auto → on → off', (tester) async {
      h = CameraHarness();
      await h.pump(tester);

      expect(find.bySemanticsLabel(strings.flashOff), findsOneWidget);
      await tester.tap(find.byKey(CameraKeys.flash));
      await tester.pump();
      expect(h.capture.flashMode, StoryFlashMode.auto);
      await tester.tap(find.byKey(CameraKeys.flash));
      await tester.pump();
      expect(h.capture.flashMode, StoryFlashMode.on);
      expect(find.bySemanticsLabel(strings.flashOn), findsOneWidget);
      await tester.tap(find.byKey(CameraKeys.flash));
      await tester.pump();
      expect(h.capture.flashMode, StoryFlashMode.off);
    });

    testWidgets('front lens: screen flash covers the screen for the photo', (
      tester,
    ) async {
      h = CameraHarness(
        config: const StoryCreatorConfig(
          capture: CaptureOptions(initialLens: StoryCameraLens.front),
        ),
      );
      await h.pump(tester);
      expect(h.capture.capabilities!.hasFlash, isFalse);
      expect(find.byKey(CameraKeys.flash), findsOneWidget);

      await tester.tap(find.byKey(CameraKeys.flash));
      await tester.pump();
      expect(find.bySemanticsLabel(strings.flashOn), findsOneWidget);

      await tester.tap(shutter);
      await tester.pump();
      expect(find.byKey(CameraKeys.screenFlash), findsOneWidget);
      expect(h.capture.calls, isNot(contains('photo')));

      await tester.pump(const Duration(milliseconds: 200));
      await settle(tester);
      expect(h.capture.calls, contains('photo'));
      expect(find.byKey(CameraKeys.screenFlash), findsNothing);
      expect(h.media, hasLength(1));
    });

    testWidgets('hides lens switch and flash when the hardware lacks them', (
      tester,
    ) async {
      h = CameraHarness(
        capture: FakeCaptureService(
          lenses: const {StoryCameraLens.back},
          hasFlash: false,
          makeFile: (_) async => '',
        ),
      );
      await h.pump(tester);

      expect(find.byKey(CameraKeys.preview), findsOneWidget);
      expect(find.byKey(CameraKeys.switchLens), findsNothing);
      expect(find.byKey(CameraKeys.flash), findsNothing);
    });

    testWidgets('lens switch toggles lenses and is hidden while recording', (
      tester,
    ) async {
      h = CameraHarness(
        inspector: FakeMediaInspector(
          defaultProbe: videoProbe(const Duration(seconds: 2)),
        ),
      );
      await h.pump(tester);

      await tester.tap(find.byKey(CameraKeys.switchLens));
      await settle(tester);
      expect(h.capture.calls, contains('switch:front'));
      expect(h.capture.capabilities!.lens, StoryCameraLens.front);

      final gesture = await holdShutter(tester, shutter);
      expect(find.byKey(CameraKeys.switchLens), findsNothing);
      expect(find.byKey(CameraKeys.gallery), findsNothing);
      expect(find.byKey(CameraKeys.close), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await gesture.up();
      await settle(tester);
    });

    testWidgets('tap on the preview focuses and shows a marker', (
      tester,
    ) async {
      h = CameraHarness();
      await h.pump(tester);

      await tester.tap(find.byKey(CameraKeys.preview));
      await tester.pump();
      expect(h.capture.calls, contains('focus'));
      expect(find.byKey(CameraKeys.focusMarker), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(CameraKeys.focusMarker), findsNothing);
    });

    testWidgets('close calls onClose', (tester) async {
      h = CameraHarness();
      await h.pump(tester);

      await tester.tap(find.byKey(CameraKeys.close));
      expect(h.closed, 1);
    });

    testWidgets('gallery disabled hides the gallery shortcut', (tester) async {
      h = CameraHarness(
        config: const StoryCreatorConfig(
          capture: CaptureOptions(galleryMode: GalleryMode.disabled),
        ),
      );
      await h.pump(tester);
      expect(find.byKey(CameraKeys.gallery), findsNothing);
    });

    testWidgets('system picker mode opens the picker directly', (tester) async {
      h = CameraHarness(
        config: const StoryCreatorConfig(
          capture: CaptureOptions(galleryMode: GalleryMode.systemPicker),
        ),
        gallery: FakeGallerySource(grid: false, resolvePath: (_) async => ''),
      );
      final picked = await h.makeCaptureFile(StoryMediaType.photo);
      h.gallery.systemPick = PickedMedia(
        path: picked,
        type: StoryMediaType.photo,
      );
      await h.pump(tester);

      await tester.tap(find.byKey(CameraKeys.gallery));
      await settle(tester);

      expect(h.gallery.systemPickCalls, 1);
      expect(h.media.single.source, StorySourceKind.gallery);
      // The picked original is copied, never moved.
      expect(File(picked).existsSync(), isTrue);
    });

    testWidgets('controls meet tap target and label guidelines', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      h = CameraHarness();
      await h.pump(tester);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  });

  group('permissions', () {
    testWidgets('denied camera shows the prompt; allow starts the camera', (
      tester,
    ) async {
      h = CameraHarness(
        permissions: FakePermissionService(
          camera: PermissionState.denied,
          cameraAfterRequest: PermissionState.granted,
        ),
      );
      await h.pump(tester);

      expect(find.byKey(CameraKeys.permissionPrompt), findsOneWidget);
      expect(find.text(strings.cameraPermissionMessage), findsOneWidget);
      expect(find.byKey(CameraKeys.gallery), findsOneWidget);
      expect(h.capture.calls, isEmpty);

      await tester.tap(find.text(strings.allowAccess));
      await settle(tester);

      expect(h.permissions.cameraRequests, 1);
      expect(find.byKey(CameraKeys.preview), findsOneWidget);
      expect(h.capture.calls, contains('initialize:back'));
    });

    testWidgets('permanently denied: open settings, re-check on resume', (
      tester,
    ) async {
      h = CameraHarness(
        permissions: FakePermissionService(
          camera: PermissionState.permanentlyDenied,
        ),
      );
      await h.pump(tester);

      expect(find.text(strings.cameraBlockedMessage), findsOneWidget);
      await tester.tap(find.text(const CommonStrings().openSettings));
      await tester.pump();
      expect(h.permissions.settingsOpened, 1);

      // The user enables the camera in the settings app and comes back.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await settle(tester);
      h.permissions.camera = PermissionState.granted;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);

      expect(find.byKey(CameraKeys.preview), findsOneWidget);
    });

    testWidgets('denied microphone: records without audio, notice once', (
      tester,
    ) async {
      h = CameraHarness(
        permissions: FakePermissionService(microphone: PermissionState.denied),
        inspector: FakeMediaInspector(
          defaultProbe: videoProbe(const Duration(seconds: 2), hasAudio: false),
        ),
      );
      await h.pump(tester);

      expect(h.permissions.microphoneRequests, 1);
      expect(h.capture.lastEnableAudio, isFalse);

      final gesture = await holdShutter(tester, shutter);
      expect(find.text(strings.microphonePermissionMessage), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await gesture.up();
      await settle(tester);
      expect(h.media.single.hasAudio, isFalse);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('camera unavailable shows retry; gallery stays usable', (
      tester,
    ) async {
      h = CameraHarness();
      h.capture.initializeError = const StoryException(
        StoryErrorCode.cameraUnavailable,
        'no camera',
      );
      await h.pump(tester);

      expect(find.byKey(CameraKeys.unavailable), findsOneWidget);
      expect(find.text(strings.cameraUnavailable), findsOneWidget);
      expect(find.byKey(CameraKeys.gallery), findsOneWidget);
      expect(find.byKey(CameraKeys.shutter), findsNothing);
      expect(h.events.single.error?.code, StoryErrorCode.cameraUnavailable);

      h.capture.initializeError = null;
      await tester.tap(find.text(const CommonStrings().retry));
      await settle(tester);
      expect(find.byKey(CameraKeys.preview), findsOneWidget);
    });

    testWidgets('a camera permission error from initialize shows the prompt', (
      tester,
    ) async {
      h = CameraHarness();
      h.capture.initializeError = const StoryException(
        StoryErrorCode.cameraPermissionDenied,
      );
      h.permissions.camera = PermissionState.granted;
      await h.pump(tester);
      // The permission service still says granted, so it is treated as
      // blocked (restricted by MDM / Screen Time).
      expect(find.text(strings.cameraBlockedMessage), findsOneWidget);
    });
  });

  group('lifecycle', () {
    testWidgets('backgrounding while recording keeps the partial clip', (
      tester,
    ) async {
      h = CameraHarness(
        inspector: FakeMediaInspector(
          defaultProbe: videoProbe(const Duration(milliseconds: 1500)),
        ),
      );
      await h.pump(tester);

      final gesture = await holdShutter(tester, shutter);
      await tester.pump(const Duration(milliseconds: 1500));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await settle(tester);
      expect(h.capture.calls, containsAllInOrder(['stopRecording', 'release']));
      // No frozen frame: the reconnecting view replaces the preview.
      expect(find.byKey(CameraKeys.starting), findsOneWidget);
      expect(find.byKey(CameraKeys.preview), findsNothing);

      // Frames stop while paused.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await settle(tester);
      expect(h.media, isEmpty);
      await gesture.up();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);

      final media = h.media.single;
      expect(media.type, StoryMediaType.video);
      expect(media.duration, const Duration(milliseconds: 1500));
    });

    testWidgets('a too-short partial clip is discarded with a notice', (
      tester,
    ) async {
      h = CameraHarness(
        inspector: FakeMediaInspector(
          defaultProbe: videoProbe(const Duration(milliseconds: 300)),
        ),
      );
      await h.pump(tester);

      final gesture = await holdShutter(tester, shutter);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await settle(tester);
      await gesture.up();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);

      expect(h.media, isEmpty);
      expect(find.text(strings.recordingDiscarded), findsOneWidget);
      // The camera is started again.
      expect(find.byKey(CameraKeys.preview), findsOneWidget);
      expect(
        h.capture.calls.where((c) => c == 'initialize:back'),
        hasLength(2),
      );
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('pause without recording releases; resume re-initialises', (
      tester,
    ) async {
      h = CameraHarness();
      await h.pump(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await settle(tester);
      expect(h.capture.calls.last, 'release');
      expect(find.byKey(CameraKeys.preview), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(h.capture.calls.last, 'initialize:back');
      expect(find.byKey(CameraKeys.preview), findsOneWidget);
    });

    testWidgets('an interruption event with a clip opens it; without one '
        'the camera reconnects', (tester) async {
      h = CameraHarness(
        inspector: FakeMediaInspector(
          defaultProbe: videoProbe(const Duration(seconds: 2)),
        ),
      );
      await h.pump(tester);

      h.capture.emit(const CaptureInterrupted('camera in use'));
      await settle(tester);
      expect(find.text(strings.cameraInterrupted), findsOneWidget);
      expect(find.byKey(CameraKeys.preview), findsOneWidget);
      expect(
        h.capture.calls.where((c) => c == 'initialize:back'),
        hasLength(2),
      );

      final clip = await h.makeCaptureFile(StoryMediaType.video);
      h.capture.emit(
        CaptureInterrupted(
          'call',
          partialRecording: CapturedFile(
            path: clip,
            type: StoryMediaType.video,
            lens: StoryCameraLens.back,
          ),
        ),
      );
      await settle(tester);
      expect(h.media.single.type, StoryMediaType.video);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a failure event shows the unavailable view', (tester) async {
      h = CameraHarness();
      await h.pump(tester);

      h.capture.emit(
        const CaptureFailed(StoryException(StoryErrorCode.cameraUnavailable)),
      );
      await settle(tester);
      expect(find.byKey(CameraKeys.unavailable), findsOneWidget);
      expect(h.events.single.error?.code, StoryErrorCode.cameraUnavailable);
    });

    testWidgets('closing while recording discards the unfinished clip', (
      tester,
    ) async {
      h = CameraHarness();
      await h.pump(tester);

      final gesture = await holdShutter(tester, shutter);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      await gesture.up();

      expect(h.capture.calls, containsAllInOrder(['stopRecording', 'dispose']));
      expect(
        h.captures.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.mp4'),
        ),
        isEmpty,
      );
    });
  });
}
