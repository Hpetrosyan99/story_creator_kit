import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/services.dart';
import 'package:story_creator_kit/src/camera/camera_controller.dart';
import 'package:story_creator_kit/src/core/media_import.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

import '../../fakes/fake_services.dart';
import 'camera_test_harness.dart';

void main() {
  group('coverToFrame', () {
    Offset map(Offset p, double view, double frame) =>
        StoryCameraController.coverToFrame(
          p,
          viewAspectRatio: view,
          frameAspectRatio: frame,
        );

    test('centre maps to centre', () {
      expect(
        map(const Offset(0.5, 0.5), 9 / 16, 3 / 4),
        const Offset(0.5, 0.5),
      );
    });

    test('a wider frame crops its sides', () {
      // A 3:4 frame in a 9:16 view shows the middle 75 % of its width.
      final p = map(const Offset(0, 0.25), 9 / 16, 3 / 4);
      expect(p.dx, closeTo(0.125, 1e-9));
      expect(p.dy, closeTo(0.25, 1e-9));
    });

    test('a taller frame crops top and bottom', () {
      final p = map(const Offset(0.3, 1), 3 / 4, 9 / 16);
      expect(p.dx, closeTo(0.3, 1e-9));
      expect(p.dy, closeTo(0.875, 1e-9));
    });
  });

  testWidgets('a microphone error at start retries without audio', (
    tester,
  ) async {
    final h = CameraHarness();
    addTearDown(h.dispose);
    final capture = _AudioRefusingCapture(makeFile: h.makeCaptureFile);
    final errors = <StoryException>[];
    final controller = StoryCameraController(
      capture: capture,
      permissions: FakePermissionService(),
      gallery: h.gallery,
      importer: MediaImporter(
        inspector: h.inspector,
        session: h.session,
        constraints: const MediaConstraints(),
      ),
      options: const CaptureOptions(),
      constraints: const MediaConstraints(),
      onMediaReady: (_) {},
      onError: errors.add,
    );
    addTearDown(controller.dispose);

    await controller.start();
    await tester.pump();

    expect(controller.status, CameraStatus.ready);
    expect(controller.audioEnabled, isFalse);
    expect(capture.lastEnableAudio, isFalse);
    expect(errors, isEmpty);
  });
}

/// Refuses to start with audio, like iOS when the microphone is denied
/// after the permission check.
class _AudioRefusingCapture extends FakeCaptureService {
  _AudioRefusingCapture({required super.makeFile});

  @override
  Future<CaptureCapabilities> initialize(
    StoryCameraLens lens, {
    required CaptureResolution resolution,
    required bool enableAudio,
  }) {
    if (enableAudio) {
      lastEnableAudio = true;
      throw const StoryException(StoryErrorCode.microphonePermissionDenied);
    }
    return super.initialize(
      lens,
      resolution: resolution,
      enableAudio: enableAudio,
    );
  }
}
