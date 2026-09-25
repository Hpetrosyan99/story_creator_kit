import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/services.dart';
import 'package:story_creator_kit/src/camera/camera_keys.dart';
import 'package:story_creator_kit/src/gallery/gallery_keys.dart';
import 'package:story_creator_kit/src/gallery/gallery_sheet.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

import '../../fakes/fake_services.dart';
import '../camera/camera_test_harness.dart';

List<GalleryAsset> _items(int count) => [
  for (var i = 0; i < count; i++)
    GalleryAsset(
      id: 'a$i',
      type: i.isOdd ? StoryMediaType.video : StoryMediaType.photo,
      width: 1080,
      height: 1920,
      duration: i.isOdd ? Duration(seconds: 15 + i) : null,
    ),
];

void main() {
  const strings = CameraStrings();
  late CameraHarness h;

  tearDown(() => h.dispose());

  CameraHarness harness({
    GalleryAccess access = GalleryAccess.granted,
    List<GalleryAsset>? items,
    StoryCreatorConfig config = const StoryCreatorConfig(),
    MediaProbe? probe,
  }) {
    late final CameraHarness created;
    return created = CameraHarness(
      config: config,
      gallery: FakeGallerySource(
        access: access,
        items: items ?? _items(6),
        resolvePath: (a) => created.makeCaptureFile(a.type),
      ),
      inspector: FakeMediaInspector(defaultProbe: probe),
    );
  }

  Future<void> openSheet(WidgetTester tester) async {
    await h.pump(tester);
    await tester.tap(find.byKey(CameraKeys.gallery));
    await finishTransition(tester);
    expect(find.byKey(GalleryKeys.sheet), findsOneWidget);
  }

  testWidgets('grid lists the camera tile, photos and videos with badges', (
    tester,
  ) async {
    h = harness();
    await openSheet(tester);

    expect(find.byKey(GalleryKeys.cameraTile), findsOneWidget);
    for (var i = 0; i < 6; i++) {
      expect(find.byKey(GalleryKeys.tile('a$i')), findsOneWidget);
    }
    // Video a1 is 16 s, a3 is 18 s.
    expect(find.text('0:16'), findsOneWidget);
    expect(find.text('0:18'), findsOneWidget);
    expect(find.text(strings.recent), findsOneWidget);
    expect(find.bySemanticsLabel('${strings.videoItem}, 0:16'), findsOneWidget);
  });

  testWidgets('tapping a tile imports it and closes the sheet', (tester) async {
    h = harness();
    await openSheet(tester);

    await tester.tap(find.byKey(GalleryKeys.tile('a0')));
    await settle(tester);
    await finishTransition(tester);

    expect(find.byKey(GalleryKeys.sheet), findsNothing);
    final media = h.media.single;
    expect(media.source, StorySourceKind.gallery);
    expect(media.type, StoryMediaType.photo);
    expect(media.path, startsWith(h.session.directory.path));
  });

  testWidgets('a video longer than the maximum is accepted', (tester) async {
    h = harness(probe: videoProbe(const Duration(minutes: 3)));
    await openSheet(tester);

    await tester.tap(find.byKey(GalleryKeys.tile('a1')));
    await settle(tester);
    await finishTransition(tester);

    expect(h.media.single.duration, const Duration(minutes: 3));
  });

  testWidgets('a video shorter than the minimum shows a notice', (
    tester,
  ) async {
    h = harness(
      items: const [
        GalleryAsset(
          id: 'short',
          type: StoryMediaType.video,
          width: 1080,
          height: 1920,
          duration: Duration(milliseconds: 500),
        ),
      ],
    );
    await openSheet(tester);

    await tester.tap(find.byKey(GalleryKeys.tile('short')));
    await tester.pump();
    expect(find.text(strings.videoTooShort), findsOneWidget);
    expect(find.byKey(GalleryKeys.sheet), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the camera tile and back close the sheet without media', (
    tester,
  ) async {
    h = harness();
    await openSheet(tester);

    await tester.tap(find.byKey(GalleryKeys.cameraTile));
    await finishTransition(tester);
    expect(find.byKey(GalleryKeys.sheet), findsNothing);

    await tester.tap(find.byKey(CameraKeys.gallery));
    await finishTransition(tester);
    expect(find.byKey(GalleryKeys.sheet), findsOneWidget);
    await tester.tap(find.byKey(GalleryKeys.back));
    await finishTransition(tester);
    expect(find.byKey(GalleryKeys.sheet), findsNothing);
    expect(h.media, isEmpty);
  });

  testWidgets('limited access shows the banner; Manage opens the selection', (
    tester,
  ) async {
    h = harness(access: GalleryAccess.limited);
    await openSheet(tester);

    expect(find.byKey(GalleryKeys.limitedBanner), findsOneWidget);
    expect(find.text(strings.limitedAccessMessage), findsOneWidget);
    final callsBefore = h.gallery.assetCalls.length;

    await tester.tap(find.byKey(GalleryKeys.manage));
    await settle(tester);

    expect(h.gallery.manageCalls, 1);
    expect(h.gallery.assetCalls.length, greaterThan(callsBefore));
  });

  testWidgets('denied access asks once, then offers the system picker', (
    tester,
  ) async {
    h = harness(access: GalleryAccess.denied);
    final picked = await h.makeCaptureFile(StoryMediaType.photo);
    h.gallery.systemPick = PickedMedia(
      path: picked,
      type: StoryMediaType.photo,
    );
    await openSheet(tester);

    expect(h.gallery.requestCalls, 1);
    expect(find.byKey(GalleryKeys.permissionPrompt), findsOneWidget);
    expect(find.text(strings.photosPermissionMessage), findsOneWidget);

    await tester.tap(find.text(strings.useSystemPicker));
    await settle(tester);
    await finishTransition(tester);

    expect(h.gallery.systemPickCalls, 1);
    expect(h.media.single.source, StorySourceKind.gallery);
  });

  testWidgets('allow access after a denial shows the grid', (tester) async {
    h = harness(access: GalleryAccess.denied);
    await openSheet(tester);
    h.gallery.accessAfterRequest = GalleryAccess.granted;

    await tester.tap(find.text(strings.allowAccess));
    await settle(tester);

    expect(find.byKey(GalleryKeys.tile('a0')), findsOneWidget);
  });

  testWidgets('permanently denied offers the settings app', (tester) async {
    h = harness(access: GalleryAccess.permanentlyDenied);
    await openSheet(tester);

    expect(h.gallery.requestCalls, 0);
    expect(find.text(strings.photosPermissionBlockedMessage), findsOneWidget);
    await tester.tap(find.text(const CommonStrings().openSettings));
    await tester.pump();
    expect(h.permissions.settingsOpened, 1);
  });

  testWidgets('scrolling loads the next page', (tester) async {
    h = harness(items: _items(150));
    await openSheet(tester);

    // Page 0 was also read (size 1) by the camera's gallery shortcut.
    expect(h.gallery.assetCalls.where((c) => c.$2 > 0), isEmpty);
    await tester.drag(find.byKey(GalleryKeys.grid), const Offset(0, -3000));
    await settle(tester);
    expect(h.gallery.assetCalls, contains(('all', 1)));

    await tester.drag(find.byKey(GalleryKeys.grid), const Offset(0, -6000));
    await settle(tester);
    await tester.drag(find.byKey(GalleryKeys.grid), const Offset(0, -6000));
    await settle(tester);
    expect(h.gallery.assetCalls, contains(('all', 2)));
    expect(find.byKey(GalleryKeys.tile('a149')), findsOneWidget);
  });

  testWidgets('the album selector switches albums', (tester) async {
    h = harness();
    const favourites = GalleryAlbum(id: 'fav', name: 'Favourites', count: 1);
    h.gallery.extraAlbums = {
      favourites: const [
        GalleryAsset(
          id: 'fav1',
          type: StoryMediaType.photo,
          width: 10,
          height: 10,
        ),
      ],
    };
    await openSheet(tester);

    await tester.tap(find.byKey(GalleryKeys.albumSelector));
    await tester.pump();
    expect(find.byKey(GalleryKeys.albumList), findsOneWidget);

    await tester.tap(find.byKey(GalleryKeys.album('fav')));
    await settle(tester);

    expect(find.text('Favourites'), findsOneWidget);
    expect(find.byKey(GalleryKeys.tile('fav1')), findsOneWidget);
    expect(find.byKey(GalleryKeys.tile('a0')), findsNothing);
  });

  testWidgets('library changes refresh the grid', (tester) async {
    h = harness(items: _items(2));
    await openSheet(tester);
    expect(find.byKey(GalleryKeys.tile('a2')), findsNothing);

    h.gallery
      ..items = _items(3)
      ..emitChange();
    await settle(tester);
    expect(find.byKey(GalleryKeys.tile('a2')), findsOneWidget);
  });

  testWidgets('a cloud item shows progress; tapping again cancels', (
    tester,
  ) async {
    h = harness();
    final gate = Completer<void>();
    h.gallery.resolveGate = gate.future;
    await openSheet(tester);

    await tester.tap(find.byKey(GalleryKeys.tile('a0')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(GalleryKeys.tile('a0')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(GalleryKeys.tile('a0')));
    await tester.pump();
    gate.complete();
    await settle(tester);

    expect(
      find.descendant(
        of: find.byKey(GalleryKeys.tile('a0')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    expect(find.byKey(GalleryKeys.sheet), findsOneWidget);
    expect(h.media, isEmpty);
  });

  testWidgets('a resolve failure shows a notice and keeps the sheet', (
    tester,
  ) async {
    h = harness();
    h.gallery.resolveError = const StoryException(
      StoryErrorCode.mediaUnavailable,
    );
    await openSheet(tester);

    await tester.tap(find.byKey(GalleryKeys.tile('a0')));
    await settle(tester);

    expect(find.text(strings.mediaUnavailable), findsOneWidget);
    expect(find.byKey(GalleryKeys.sheet), findsOneWidget);
    expect(h.events.single.error?.code, StoryErrorCode.mediaUnavailable);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('photos-only constraints hide videos', (tester) async {
    h = harness(
      config: const StoryCreatorConfig(
        constraints: MediaConstraints(allowVideos: false),
      ),
    );
    await openSheet(tester);

    expect(find.byKey(GalleryKeys.tile('a0')), findsOneWidget);
    expect(find.byKey(GalleryKeys.tile('a1')), findsNothing);
  });

  testWidgets('an empty library shows the empty message', (tester) async {
    h = harness(items: const []);
    await openSheet(tester);
    expect(find.text(strings.galleryEmpty), findsOneWidget);
    expect(find.byKey(GalleryKeys.cameraTile), findsOneWidget);
  });

  testWidgets('sheet controls meet tap target and label guidelines', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    h = harness(access: GalleryAccess.limited);
    await openSheet(tester);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('open() completes with null when popped', (tester) async {
    h = harness();
    Future<PickedMedia?>? result;
    usePhoneView(tester);
    await tester.pumpWidget(
      h.wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => result = GallerySheet.open(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await finishTransition(tester);
    await tester.tap(find.byKey(GalleryKeys.back));
    await finishTransition(tester);
    expect(await result, isNull);
  });
}
