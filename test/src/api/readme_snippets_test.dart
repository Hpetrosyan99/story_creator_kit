// Compile check for the code samples in README.md.
//
// Each block below mirrors a README snippet, so an API change that breaks
// the documentation breaks this file too. Keep them in sync when you edit
// either. Only the pure-Dart samples run; the rest just have to compile.
//
// The samples spell out default values on purpose, to show what can be set.
// ignore_for_file: avoid_redundant_argument_values, prefer_const_constructors
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/services.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

// --- Stand-ins for host-app code the README refers to -----------------------

void upload(String path) {}

void handleOutcome(StoryOutcome outcome) {}

const config = StoryCreatorConfig();

bool get isIosSimulator => false;

class MyMusicProvider extends BundledMusicProvider {
  MyMusicProvider() : super(const []);
}

final crashReporter = _CrashReporter();
final analytics = _Analytics();

class _CrashReporter {
  void recordError(Object error, StackTrace? stackTrace) {}
}

class _Analytics {
  void log(String name, Map<String, Object> properties) {}
}

/// Minimal capture service so the "Replacing services" sample compiles; the
/// full version lives in example/lib/simulated_capture_service.dart.
class SimulatedCaptureService implements CaptureService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// --- README: intro -----------------------------------------------------------

Future<void> intro(BuildContext context) async {
  final outcome = await StoryCreator.open(context);
  if (outcome case StoryCompleted(:final result)) {
    upload(result.path); // 1080×1920 JPEG or H.264/AAC MP4
  }
}

// --- README: Quick start -----------------------------------------------------

class NewStoryButton extends StatelessWidget {
  const NewStoryButton({super.key});

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: () => _create(context),
    child: const Text('New story'),
  );

  Future<void> _create(BuildContext context) async {
    final outcome = await StoryCreator.open(context);
    switch (outcome) {
      case StoryCompleted(:final result):
        debugPrint('Story at ${result.path} (${result.mimeType})');
      case StoryCancelled(:final reason):
        debugPrint('No story: ${reason.name}');
      case StoryFailed(:final error):
        debugPrint('Story creator failed: $error');
    }
  }
}

void ownRoute(BuildContext context) {
  unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => StoryCreatorPage(
          config: config,
          onFinished: (outcome) {
            Navigator.of(context).pop();
            handleOutcome(outcome);
          },
        ),
      ),
    ),
  );
}

// --- README: Configuration reference -----------------------------------------

StoryCreatorConfig fullConfig() {
  final config = StoryCreatorConfig(
    theme: const StoryCreatorTheme(accent: Color(0xFFE4572E)),
    strings: const StoryCreatorStrings(),
    capture: const CaptureOptions(
      initialLens: StoryCameraLens.back,
      galleryMode: GalleryMode.inApp,
      resolution: CaptureResolution.high,
    ),
    constraints: const MediaConstraints(
      maxVideoDuration: Duration(seconds: 60),
      minVideoDuration: Duration(seconds: 1),
      photoWithMusicDuration: Duration(seconds: 15),
    ),
    editor: EditorOptions(
      fonts: const [
        StoryFont(id: 'inter', label: 'Classic', family: 'Inter'),
        StoryFont(
          id: 'pacifico',
          label: 'Script',
          family: 'Pacifico',
          height: 1.4,
        ),
      ],
      stickers: const [
        StorySticker(
          id: 'star',
          label: 'Star',
          image: AssetImage('assets/stickers/star.png'),
        ),
      ],
      filters: StoryFilter.defaults,
    ),
    output: const OutputOptions(
      saveToGallery: SaveToGalleryMode.button,
      jpegQuality: 90,
    ),
    musicProvider: MyMusicProvider(),
    onEvent: (event) => debugPrint('$event'),
  );
  return config;
}

StoryCreatorTheme brandTheme(Color brandColor) =>
    const StoryCreatorTheme().copyWith(accent: brandColor);

StoryCreatorStrings germanStrings() => const StoryCreatorStrings(
  common: CommonStrings(
    close: 'Schließen',
    done: 'Fertig',
    retry: 'Erneut versuchen',
  ),
  camera: CameraStrings(takePhoto: 'Foto aufnehmen', recent: 'Neueste'),
  editor: EditorStrings(text: 'Text', draw: 'Zeichnen', export: 'Story teilen'),
  export: ExportStrings(useStory: 'Story verwenden'),
);

StoryCreatorConfig systemPickerConfig() => const StoryCreatorConfig(
  capture: CaptureOptions(galleryMode: GalleryMode.systemPicker),
);

List<StoryFont> fonts() {
  final fonts = [
    const StoryFont(id: 'inter', label: 'Classic', family: 'Inter'),
    const StoryFont(
      id: 'mono',
      label: 'Typewriter',
      family: 'SpaceMono',
      uppercase: true,
      letterSpacing: 2,
    ),
    StoryFont(
      id: 'brand',
      label: 'Brand',
      family: 'BrandSans',
      loader: () async {
        final loader = FontLoader('BrandSans')
          ..addFont(rootBundle.load('assets/fonts/BrandSans.ttf'));
        await loader.load();
      },
    ),
  ];
  return fonts;
}

EditorOptions customFilters() {
  const brand = StoryFilter(
    id: 'brand_warm',
    label: 'Brand',
    matrix: [
      1.08, 0, 0, 0, 12, //
      0, 1.0, 0, 0, 4,
      0, 0, 0.9, 0, -8,
      0, 0, 0, 1, 0,
    ],
  );
  final options = EditorOptions(
    filters: [StoryFilter.original, brand, ...StoryFilter.defaults.skip(1)],
  );
  return options;
}

// --- README: Music -------------------------------------------------------------

class BundledMusicProvider extends StoryMusicProvider {
  BundledMusicProvider(this._tracks);

  final List<MusicTrack> _tracks;
  final Set<String> _bookmarks = {};

  @override
  List<MusicCategory> get categories => const [
    MusicCategory(id: 'all', label: 'All'),
    MusicCategory(id: 'bookmarked', label: 'Bookmarked'),
  ];

  @override
  bool get supportsBookmarks => true;

  @override
  Future<MusicPage> fetchTracks(MusicQuery query) async {
    final search = query.search.trim().toLowerCase();
    final matches = [
      for (final track in _tracks)
        if ((query.categoryId != 'bookmarked' ||
                _bookmarks.contains(track.id)) &&
            (search.isEmpty ||
                track.title.toLowerCase().contains(search) ||
                track.artist.toLowerCase().contains(search)))
          track.copyWith(bookmarked: _bookmarks.contains(track.id)),
    ];
    final start = int.tryParse(query.cursor ?? '') ?? 0;
    final end = (start + query.pageSize).clamp(0, matches.length);
    return MusicPage(
      tracks: matches.sublist(start, end),
      nextCursor: end < matches.length ? '$end' : null,
    );
  }

  @override
  Future<MusicSource> resolve(MusicTrack track) async =>
      MusicAssetSource('assets/music/${track.id}.m4a');

  @override
  Future<void> setBookmarked(
    MusicTrack track, {
    required bool bookmarked,
  }) async {
    if (bookmarked) {
      _bookmarks.add(track.id);
    } else {
      _bookmarks.remove(track.id);
    }
  }
}

final provider = BundledMusicProvider(const [
  MusicTrack(
    id: 'sunrise_drive',
    title: 'Sunrise Drive',
    artist: 'Example',
    duration: Duration(seconds: 66),
    extra: {'licence': 'CC0'},
  ),
]);

// --- README: Result and metadata ----------------------------------------------

void describe(StoryResult result) {
  final m = result.metadata;
  debugPrint(
    '${result.type.name} ${result.width}×${result.height}, '
    '${result.fileSizeBytes} bytes, from ${m.source.name}',
  );
  if (m.music case final music?) {
    debugPrint(
      'music ${music.trackId} from ${music.start} for ${music.duration}',
    );
  }
  for (final text in m.texts) {
    debugPrint('text "${text.text}" in ${text.fontId}');
  }
}

// --- README: Replacing services -----------------------------------------------

StoryServices storyServices(StoryCreatorConfig config) {
  final services = StoryServices.platform(config);
  return isIosSimulator
      ? services.copyWith(createCapture: SimulatedCaptureService.new)
      : services;
}

Future<void> openWithServices(BuildContext context) async {
  await StoryCreator.open(
    context,
    config: config,
    services: storyServices(config),
  );
}

// --- README: Errors and events -------------------------------------------------

void onStoryEvent(StoryEvent event) {
  if (event.type == StoryEventType.error) {
    crashReporter.recordError(event.error!, event.stackTrace);
    return;
  }
  analytics.log('story_${event.type.name}', event.properties);
}

void main() {
  test('README config samples build valid configurations', () {
    expect(fullConfig().musicEnabled, isTrue);
    expect(systemPickerConfig().capture.galleryMode, GalleryMode.systemPicker);
    expect(germanStrings().camera.takePhoto, 'Foto aufnehmen');
    expect(germanStrings().camera.switchCamera, 'Switch camera');
    expect(brandTheme(const Color(0xFF123456)).accent, const Color(0xFF123456));
    expect(fonts().map((f) => f.id), ['inter', 'mono', 'brand']);
    final filters = customFilters().filters;
    expect(filters.first, StoryFilter.original);
    expect(filters.map((f) => f.id).toSet(), hasLength(filters.length));
    expect(filters.every((f) => f.matrix.length == 20), isTrue);
  });

  test('README music provider pages, searches and bookmarks', () async {
    final music = BundledMusicProvider([
      for (var i = 0; i < 5; i++)
        MusicTrack(
          id: 't$i',
          title: i.isEven ? 'Sunrise $i' : 'Night $i',
          artist: 'Example',
          duration: const Duration(seconds: 60),
        ),
    ]);

    final first = await music.fetchTracks(
      const MusicQuery(categoryId: 'all', pageSize: 2),
    );
    expect(first.tracks.map((t) => t.id), ['t0', 't1']);
    expect(first.nextCursor, '2');

    final last = await music.fetchTracks(
      MusicQuery(categoryId: 'all', pageSize: 2, cursor: first.nextCursor),
    );
    expect(last.tracks.map((t) => t.id), ['t2', 't3']);

    final search = await music.fetchTracks(
      const MusicQuery(categoryId: 'all', search: 'night'),
    );
    expect(search.tracks.map((t) => t.id), ['t1', 't3']);
    expect(search.nextCursor, isNull);

    await music.setBookmarked(first.tracks.first, bookmarked: true);
    final bookmarked = await music.fetchTracks(
      const MusicQuery(categoryId: 'bookmarked'),
    );
    expect(bookmarked.tracks.single.id, 't0');
    expect(bookmarked.tracks.single.bookmarked, isTrue);

    final source = await music.resolve(first.tracks.first);
    expect((source as MusicAssetSource).assetKey, 'assets/music/t0.m4a');
  });

  test('README event handler routes errors and analytics', () {
    onStoryEvent(const StoryEvent(StoryEventType.opened));
    onStoryEvent(
      const StoryEvent(
        StoryEventType.error,
        error: StoryException(StoryErrorCode.exportFailed),
      ),
    );
  });
}
