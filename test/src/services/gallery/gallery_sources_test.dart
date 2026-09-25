import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/services.dart';
import 'package:story_creator_kit/src/services/gallery/photo_manager_gallery_source.dart';
import 'package:story_creator_kit/src/services/gallery/system_picker_gallery_source.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

// photo_manager encodes PermissionState by index:
// notDetermined, restricted, denied, authorized, limited.
const _pmChannel = MethodChannel('com.fluttercandies/photo_manager');
const _notDetermined = 0;
const _restricted = 1;
const _denied = 2;
const _authorized = 3;
const _limited = 4;

const _asset = GalleryAsset(
  id: 'x',
  type: StoryMediaType.photo,
  width: 1,
  height: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SystemPickerGallerySource', () {
    final source = SystemPickerGallerySource();

    test('needs no permission and has no grid', () async {
      expect(source.supportsGrid, isFalse);
      expect(await source.checkAccess(), GalleryAccess.granted);
      expect(await source.requestAccess(), GalleryAccess.granted);
      expect(await source.albums(photos: true, videos: true), isEmpty);
      expect(() => source.thumbnail(_asset), throwsA(isA<StoryException>()));
      await expectLater(source.resolve(_asset), throwsA(isA<StoryException>()));
    });

    test('detects the type from the MIME type, then the extension', () {
      expect(
        SystemPickerGallerySource.typeOf('/a/b', 'video/mp4'),
        StoryMediaType.video,
      );
      expect(
        SystemPickerGallerySource.typeOf('/a/b.mov', 'image/heic'),
        StoryMediaType.photo,
      );
      expect(
        SystemPickerGallerySource.typeOf('/a/IMG_1.MOV', null),
        StoryMediaType.video,
      );
      expect(
        SystemPickerGallerySource.typeOf('/a/IMG_1.HEIC', null),
        StoryMediaType.photo,
      );
      expect(
        SystemPickerGallerySource.typeOf('/a/noext', null),
        StoryMediaType.photo,
      );
    });
  });

  group('PhotoManagerGallerySource access', () {
    late int state;
    late List<String> calls;

    setUp(() {
      state = _notDetermined;
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pmChannel, (call) async {
            calls.add(call.method);
            switch (call.method) {
              case 'requestPermissionExtend':
              case 'getPermissionState':
                return state;
            }
            return null;
          });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pmChannel, null);
    });

    test('maps authorized, limited, notDetermined and restricted', () async {
      final source = PhotoManagerGallerySource();
      expect(source.supportsGrid, isTrue);
      expect(await source.checkAccess(), GalleryAccess.denied);
      state = _authorized;
      expect(await source.checkAccess(), GalleryAccess.granted);
      state = _limited;
      expect(await source.requestAccess(), GalleryAccess.limited);
      state = _restricted;
      expect(await source.checkAccess(), GalleryAccess.permanentlyDenied);
      expect(calls, contains('getPermissionState'));
    });

    test('iOS: denied means only the settings app helps', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      state = _denied;
      expect(
        await PhotoManagerGallerySource().checkAccess(),
        GalleryAccess.permanentlyDenied,
      );
    });

    test('Android: denied can be asked again until two refusals', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final source = PhotoManagerGallerySource();
      state = _denied;
      expect(await source.checkAccess(), GalleryAccess.denied);
      expect(await source.requestAccess(), GalleryAccess.denied);
      expect(await source.requestAccess(), GalleryAccess.permanentlyDenied);
      expect(await source.checkAccess(), GalleryAccess.permanentlyDenied);
      state = _authorized;
      expect(await source.requestAccess(), GalleryAccess.granted);
      state = _denied;
      expect(await source.checkAccess(), GalleryAccess.denied);
    });

    test('platform errors become photosPermissionDenied', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            _pmChannel,
            (call) async => throw PlatformException(code: 'boom'),
          );
      await expectLater(
        PhotoManagerGallerySource().checkAccess(),
        throwsA(
          isA<StoryException>().having(
            (e) => e.code,
            'code',
            StoryErrorCode.photosPermissionDenied,
          ),
        ),
      );
    });

    test('assets of an unknown album are a typed error', () async {
      await expectLater(
        PhotoManagerGallerySource().assets(
          const GalleryAlbum(id: 'nope', name: 'x', count: 0),
          page: 0,
        ),
        throwsA(
          isA<StoryException>().having(
            (e) => e.code,
            'code',
            StoryErrorCode.mediaUnavailable,
          ),
        ),
      );
    });

    test('dispose clears the file cache and can be used again', () async {
      final source = PhotoManagerGallerySource();
      final sub = source.changes.listen((_) {});
      await pumpEventQueue();
      await sub.cancel();
      await source.dispose();
      expect(calls, contains('clearFileCache'));
      // A new listener after dispose works.
      final again = source.changes.listen((_) {});
      await again.cancel();
    });
  });

  group('PhotoManagerGallerySource change notifications', () {
    late int state;
    late List<String> calls;

    setUp(() {
      state = _notDetermined;
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pmChannel, (call) async {
            calls.add(call.method);
            switch (call.method) {
              case 'getPermissionState':
                return state;
              case 'requestPermissionExtend':
                state = _authorized;
                return state;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pmChannel, null);
    });

    test('does not register the native observer before access is decided '
        '(it would show the iOS permission prompt)', () async {
      final source = PhotoManagerGallerySource();
      final sub = source.changes.listen((_) {});
      await pumpEventQueue();
      expect(await source.checkAccess(), GalleryAccess.denied);
      expect(calls, isNot(contains('notify')));

      expect(await source.requestAccess(), GalleryAccess.granted);
      expect(calls, contains('notify'));
      await sub.cancel();
      await source.dispose();
    });

    test('registers right away when access is already granted', () async {
      state = _authorized;
      final source = PhotoManagerGallerySource();
      final sub = source.changes.listen((_) {});
      await pumpEventQueue();
      expect(calls, contains('notify'));
      await sub.cancel();
      await source.dispose();
    });
  });
}
