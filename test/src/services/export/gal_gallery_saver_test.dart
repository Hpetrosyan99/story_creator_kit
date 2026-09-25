import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/src/api/errors/story_exception.dart';
import 'package:story_creator_kit/src/api/result/story_result.dart';
import 'package:story_creator_kit/src/services/export/gal_gallery_saver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('gal');
  final calls = <MethodCall>[];
  var hasAccess = true;
  var grant = true;
  PlatformException? putError;

  setUp(() {
    calls.clear();
    hasAccess = true;
    grant = true;
    putError = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'hasAccess':
              return hasAccess;
            case 'requestAccess':
              return grant;
            default:
              if (putError != null) {
                throw putError!;
              }
              return null;
          }
        });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('photos use putImage, videos putVideo, with the album', () async {
    final saver = GalGallerySaver();
    await saver.save('/a.jpg', StoryMediaType.photo);
    await saver.save('/b.mp4', StoryMediaType.video, album: 'Stories');
    final puts = calls.where((c) => c.method.startsWith('put')).toList();
    expect(puts[0].method, 'putImage');
    expect(puts[0].arguments, {'path': '/a.jpg', 'album': null});
    expect(puts[1].method, 'putVideo');
    expect(puts[1].arguments, {'path': '/b.mp4', 'album': 'Stories'});
  });

  test(
    'access is requested when missing; denial is photosPermissionDenied',
    () async {
      hasAccess = false;
      grant = false;
      await expectLater(
        GalGallerySaver().save('/a.jpg', StoryMediaType.photo),
        throwsA(
          isA<StoryException>().having(
            (e) => e.code,
            'code',
            StoryErrorCode.photosPermissionDenied,
          ),
        ),
      );
      expect(calls.map((c) => c.method), ['hasAccess', 'requestAccess']);
    },
  );

  test('platform failures are saveToGalleryFailed', () async {
    putError = PlatformException(code: 'NOT_ENOUGH_SPACE');
    await expectLater(
      GalGallerySaver().save('/a.jpg', StoryMediaType.photo),
      throwsA(
        isA<StoryException>().having(
          (e) => e.code,
          'code',
          StoryErrorCode.saveToGalleryFailed,
        ),
      ),
    );
  });

  test('ACCESS_DENIED while saving is photosPermissionDenied', () async {
    putError = PlatformException(code: 'ACCESS_DENIED');
    await expectLater(
      GalGallerySaver().save('/a.mp4', StoryMediaType.video),
      throwsA(
        isA<StoryException>().having(
          (e) => e.code,
          'code',
          StoryErrorCode.photosPermissionDenied,
        ),
      ),
    );
  });
}
