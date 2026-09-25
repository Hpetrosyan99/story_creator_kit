import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:story_creator_kit/services.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

/// Camera that "captures" files created on demand.
class FakeCaptureService implements CaptureService {
  FakeCaptureService({
    this.lenses = const {StoryCameraLens.back, StoryCameraLens.front},
    this.hasFlash = true,
    this.initializeError,
    required this.makeFile,
  });

  final Set<StoryCameraLens> lenses;
  final bool hasFlash;
  StoryException? initializeError;

  /// `enableAudio` of the last [initialize] call.
  bool? lastEnableAudio;

  /// Thrown by [startRecording] / [stopRecording] / [takePhoto] when set.
  StoryException? startError;
  StoryException? stopError;
  StoryException? photoError;

  /// `mirrored` of produced files.
  bool mirrorOutput = false;

  /// Creates a file for a capture of [type].
  final Future<String> Function(StoryMediaType type) makeFile;

  final StreamController<CaptureEvent> _events = StreamController.broadcast();
  CaptureCapabilities? _caps;
  bool _recording = false;
  late DateTime _recordStart;
  StoryFlashMode flashMode = StoryFlashMode.off;
  double zoom = 1;
  final List<String> calls = [];

  void emit(CaptureEvent event) => _events.add(event);

  @override
  CaptureCapabilities? get capabilities => _caps;

  @override
  bool get isInitialized => _caps != null;

  @override
  bool get isRecording => _recording;

  @override
  Stream<CaptureEvent> get events => _events.stream;

  @override
  Future<CaptureCapabilities> initialize(
    StoryCameraLens lens, {
    required CaptureResolution resolution,
    required bool enableAudio,
  }) async {
    calls.add('initialize:${lens.name}');
    lastEnableAudio = enableAudio;
    if (initializeError != null) {
      throw initializeError!;
    }
    return _caps = CaptureCapabilities(
      lens: lens,
      availableLenses: lenses,
      hasFlash: hasFlash && lens == StoryCameraLens.back,
      minZoom: 1,
      maxZoom: 8,
      previewAspectRatio: 9 / 16,
    );
  }

  @override
  Widget buildPreview() => const ColoredBox(color: Color(0xFF334455));

  @override
  Future<CaptureCapabilities> switchLens() async {
    final current = _caps!.lens;
    final next = current == StoryCameraLens.back
        ? StoryCameraLens.front
        : StoryCameraLens.back;
    calls.add('switch:${next.name}');
    return initialize(
      next,
      resolution: CaptureResolution.high,
      enableAudio: true,
    );
  }

  @override
  Future<void> setFlashMode(StoryFlashMode mode) async => flashMode = mode;

  @override
  Future<void> setZoom(double value) async => zoom = value;

  @override
  Future<void> focusAt(Offset point) async => calls.add('focus');

  @override
  Future<CapturedFile> takePhoto() async {
    calls.add('photo');
    if (photoError != null) {
      throw photoError!;
    }
    return CapturedFile(
      path: await makeFile(StoryMediaType.photo),
      type: StoryMediaType.photo,
      lens: _caps!.lens,
      mirrored: mirrorOutput,
    );
  }

  @override
  Future<void> startRecording() async {
    calls.add('startRecording');
    if (startError != null) {
      throw startError!;
    }
    _recording = true;
    _recordStart = DateTime.now();
  }

  @override
  Future<CapturedFile> stopRecording() async {
    calls.add('stopRecording');
    _recording = false;
    if (stopError != null) {
      throw stopError!;
    }
    return CapturedFile(
      path: await makeFile(StoryMediaType.video),
      type: StoryMediaType.video,
      lens: _caps!.lens,
      duration: DateTime.now().difference(_recordStart),
    );
  }

  @override
  Future<void> release() async {
    calls.add('release');
    _caps = null;
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await _events.close();
  }
}

class FakePermissionService implements PermissionService {
  FakePermissionService({
    this.camera = PermissionState.granted,
    this.microphone = PermissionState.granted,
    this.cameraAfterRequest,
    this.microphoneAfterRequest,
  });

  PermissionState camera;
  PermissionState microphone;
  PermissionState? cameraAfterRequest;
  PermissionState? microphoneAfterRequest;
  int settingsOpened = 0;

  /// Number of [requestCamera] / [requestMicrophone] calls.
  int cameraRequests = 0;
  int microphoneRequests = 0;

  @override
  Future<PermissionState> checkCamera() async => camera;

  @override
  Future<PermissionState> requestCamera() async {
    cameraRequests++;
    return camera = cameraAfterRequest ?? camera;
  }

  @override
  Future<PermissionState> checkMicrophone() async => microphone;

  @override
  Future<PermissionState> requestMicrophone() async {
    microphoneRequests++;
    return microphone = microphoneAfterRequest ?? microphone;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}

class FakeGallerySource implements GallerySource {
  FakeGallerySource({
    this.access = GalleryAccess.granted,
    this.items = const [],
    this.grid = true,
    required this.resolvePath,
  });

  GalleryAccess access;
  List<GalleryAsset> items;
  final bool grid;
  final Future<String> Function(GalleryAsset asset) resolvePath;
  PickedMedia? systemPick;
  int manageCalls = 0;
  final StreamController<void> _changes = StreamController.broadcast();

  /// Access after [requestAccess]; unchanged when `null`.
  GalleryAccess? accessAfterRequest;

  /// Number of [requestAccess] / [pickWithSystemPicker] calls.
  int requestCalls = 0;
  int systemPickCalls = 0;

  /// (album id, page) of every [assets] call.
  final List<(String, int)> assetCalls = [];

  /// Extra albums after "Recent", with their items.
  Map<GalleryAlbum, List<GalleryAsset>> extraAlbums = {};

  /// Thrown by [resolve] when set.
  StoryException? resolveError;

  /// Awaited by [resolve] after reporting 0.5 progress (iCloud downloads).
  Future<void>? resolveGate;

  /// Simulates a library change.
  void emitChange() => _changes.add(null);

  @override
  bool get supportsGrid => grid;

  @override
  Future<GalleryAccess> checkAccess() async => access;

  @override
  Future<GalleryAccess> requestAccess() async {
    requestCalls++;
    return access = accessAfterRequest ?? access;
  }

  @override
  Future<void> manageLimitedSelection() async => manageCalls++;

  @override
  Future<List<GalleryAlbum>> albums({
    required bool photos,
    required bool videos,
  }) async => [
    GalleryAlbum(id: 'all', name: 'Recent', count: items.length, isAll: true),
    ...extraAlbums.keys,
  ];

  @override
  Future<List<GalleryAsset>> assets(
    GalleryAlbum album, {
    required int page,
    int pageSize = 60,
  }) async {
    assetCalls.add((album.id, page));
    final source = album.isAll
        ? items
        : extraAlbums.entries
                  .where((e) => e.key.id == album.id)
                  .firstOrNull
                  ?.value ??
              const <GalleryAsset>[];
    return source.skip(page * pageSize).take(pageSize).toList();
  }

  @override
  ImageProvider thumbnail(GalleryAsset asset, {int size = 256}) =>
      MemoryImage(kTransparentPng);

  @override
  Future<PickedMedia> resolve(
    GalleryAsset asset, {
    void Function(double progress)? onProgress,
  }) async {
    final gate = resolveGate;
    if (gate != null) {
      onProgress?.call(0.5);
      await gate;
    }
    if (resolveError != null) {
      throw resolveError!;
    }
    onProgress?.call(1);
    return PickedMedia(path: await resolvePath(asset), type: asset.type);
  }

  @override
  Future<PickedMedia?> pickWithSystemPicker({
    required bool photos,
    required bool videos,
  }) async {
    systemPickCalls++;
    return systemPick;
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> dispose() => _changes.close();
}

/// Inspector returning configurable probes.
class FakeMediaInspector implements MediaInspector {
  FakeMediaInspector({this.probes = const {}, this.defaultProbe});

  Map<String, MediaProbe> probes;
  MediaProbe? defaultProbe;
  Exception? probeError;

  @override
  Future<MediaProbe> probe(String path) async {
    if (probeError != null) {
      throw probeError!;
    }
    return probes[path] ??
        defaultProbe ??
        const MediaProbe(width: 1080, height: 1920, fileSizeBytes: 1000);
  }

  @override
  Future<List<double>> waveform(String path, {int buckets = 120}) async => [
    for (var i = 0; i < buckets; i++) (i % 10) / 10,
  ];

  @override
  Future<List<String>> thumbnails(
    String path,
    List<Duration> times, {
    required String outputDirectory,
    int maxWidth = 160,
  }) async => [for (final _ in times) path];
}

class FakeMusicSession implements MusicSession {
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  final ValueNotifier<bool> _playing = ValueNotifier(false);
  Duration? trackDuration = const Duration(minutes: 3);
  double volume = 1;
  MusicSource? loaded;
  (Duration, Duration)? segment;
  Exception? loadError;

  /// Every loaded source, in order.
  final List<MusicSource> loads = [];

  /// `loop` of the last [playSegment] call.
  bool? lastLoop;

  /// Number of [playSegment] calls.
  int playCount = 0;

  /// Number of [stop] calls.
  int stopCount = 0;

  /// Whether [dispose] was called.
  bool disposed = false;

  @override
  ValueListenable<Duration> get position => _position;

  @override
  ValueListenable<bool> get playing => _playing;

  @override
  Future<Duration?> load(MusicSource source) async {
    if (loadError != null) {
      throw loadError!;
    }
    loaded = source;
    loads.add(source);
    return trackDuration;
  }

  @override
  Future<void> playSegment(
    Duration start,
    Duration length, {
    bool loop = true,
  }) async {
    segment = (start, length);
    lastLoop = loop;
    playCount++;
    _position.value = start;
    _playing.value = true;
  }

  @override
  Future<void> seek(Duration position) async => _position.value = position;

  @override
  Future<void> setVolume(double value) async => volume = value;

  @override
  Future<void> pause() async => _playing.value = false;

  @override
  Future<void> resume() async => _playing.value = true;

  @override
  Future<void> stop() async {
    stopCount++;
    _playing.value = false;
    loaded = null;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    _position.dispose();
    _playing.dispose();
  }
}

class FakeVideoSession implements VideoSession {
  FakeVideoSession({this.duration = const Duration(seconds: 10)});

  final Duration duration;
  final ValueNotifier<VideoPlaybackState> _state = ValueNotifier(
    const VideoPlaybackState(),
  );
  double volume = 1;
  TrimRange? range;
  String? openedPath;

  @override
  ValueListenable<VideoPlaybackState> get state => _state;

  @override
  Future<void> open(String path) async {
    openedPath = path;
    _state.value = VideoPlaybackState(
      initialized: true,
      duration: duration,
      size: const Size(1080, 1920),
    );
  }

  @override
  Widget buildView() => const ColoredBox(color: Color(0xFF223344));

  @override
  Future<void> play() async =>
      _state.value = _state.value.copyWith(playing: true);

  @override
  Future<void> pause() async =>
      _state.value = _state.value.copyWith(playing: false);

  @override
  Future<void> seekTo(Duration position) async =>
      _state.value = _state.value.copyWith(position: position);

  @override
  Future<void> setVolume(double value) async => volume = value;

  @override
  Future<void> setPlaybackRange(TrimRange? value) async => range = value;

  @override
  Future<void> dispose() async => _state.dispose();
}

/// Exporter that writes a small file and completes on demand.
class FakeStoryExporter implements StoryExporter {
  FakeStoryExporter({this.autoComplete = true, this.failWith});

  bool autoComplete;
  StoryException? failWith;
  final List<StoryDocument> documents = [];
  FakeExportJob? lastJob;

  @override
  ExportJob start(StoryDocument document, ExportContext context) {
    documents.add(document);
    final job = FakeExportJob(document, context, failWith: failWith);
    lastJob = job;
    if (autoComplete) {
      scheduleMicrotask(job.finish);
    }
    return job;
  }
}

class FakeExportJob implements ExportJob {
  FakeExportJob(this.document, this.context, {this.failWith});

  final StoryDocument document;
  final ExportContext context;
  final StoryException? failWith;
  final StreamController<double> _progress = StreamController.broadcast();
  final Completer<ExportedStory> _result = Completer();
  bool cancelled = false;

  void emitProgress(double value) => _progress.add(value);

  Future<void> finish() async {
    if (_result.isCompleted) {
      return;
    }
    if (failWith != null) {
      _result.completeError(failWith!);
      await _progress.close();
      return;
    }
    final video = document.exportsVideo;
    final path =
        '${context.outputDirectory}/story_${DateTime.now().microsecondsSinceEpoch}'
        '.${video ? 'mp4' : 'jpg'}';
    await File(path).writeAsBytes(const [1, 2, 3]);
    _progress.add(1);
    _result.complete(
      ExportedStory(
        path: path,
        type: video ? StoryMediaType.video : StoryMediaType.photo,
        width: 1080,
        height: 1920,
        fileSizeBytes: 3,
        duration: document.outputDuration,
      ),
    );
    await _progress.close();
  }

  @override
  Stream<double> get progress => _progress.stream;

  @override
  Future<ExportedStory> get result => _result.future;

  @override
  Future<void> cancel() async {
    cancelled = true;
    if (!_result.isCompleted) {
      _result.completeError(const ExportCancelledException());
      await _progress.close();
    }
  }
}

class FakeGallerySaver implements GallerySaver {
  final List<String> saved = [];
  StoryException? error;

  @override
  Future<void> save(String path, StoryMediaType type, {String? album}) async {
    if (error != null) {
      throw error!;
    }
    saved.add(path);
  }
}

class FakeMusicProvider extends StoryMusicProvider {
  FakeMusicProvider({
    List<MusicTrack>? tracks,
    this.error,
    this.bookmarksSupported = true,
    this.resolver,
    this.beforeFetch,
    this.bookmarkError,
  }) : tracks = tracks ?? sampleTracks;

  final List<MusicTrack> tracks;
  Exception? error;
  final List<MusicQuery> queries = [];
  final Map<String, bool> bookmarks = {};

  /// Value of [supportsBookmarks].
  bool bookmarksSupported;

  /// Replaces the default [resolve] result.
  Future<MusicSource> Function(MusicTrack track)? resolver;

  /// Awaited by [fetchTracks] after recording the query (gates, delays).
  Future<void> Function(MusicQuery query)? beforeFetch;

  /// Thrown by [setBookmarked] when set.
  Exception? bookmarkError;

  /// Tracks passed to [resolve], in order.
  final List<String> resolved = [];

  /// Calls of [setBookmarked] as (track id, bookmarked).
  final List<(String, bool)> bookmarkCalls = [];

  static final List<MusicTrack> sampleTracks = [
    for (var i = 0; i < 45; i++)
      MusicTrack(
        id: 't$i',
        title: 'Track $i',
        artist: 'Artist ${i % 5}',
        duration: Duration(seconds: 120 + i),
        bookmarked: i.isEven,
      ),
  ];

  @override
  List<MusicCategory> get categories => const [
    MusicCategory(id: 'all', label: 'All'),
    MusicCategory(id: 'bookmarked', label: 'Bookmarked'),
  ];

  @override
  bool get supportsBookmarks => bookmarksSupported;

  @override
  Future<MusicPage> fetchTracks(MusicQuery query) async {
    queries.add(query);
    await beforeFetch?.call(query);
    if (error != null) {
      throw error!;
    }
    var list = tracks.where(
      (t) => t.title.toLowerCase().contains(query.search.toLowerCase()),
    );
    if (query.categoryId == 'bookmarked') {
      list = list.where((t) => bookmarks[t.id] ?? t.bookmarked);
    }
    final all = list.toList();
    final start = int.tryParse(query.cursor ?? '0') ?? 0;
    final end = (start + query.pageSize).clamp(0, all.length);
    return MusicPage(
      tracks: all.sublist(start, end),
      nextCursor: end < all.length ? '$end' : null,
    );
  }

  @override
  Future<MusicSource> resolve(MusicTrack track) async {
    resolved.add(track.id);
    return resolver?.call(track) ?? MusicFileSource('/tmp/${track.id}.m4a');
  }

  @override
  Future<void> setBookmarked(
    MusicTrack track, {
    required bool bookmarked,
  }) async {
    bookmarkCalls.add((track.id, bookmarked));
    if (bookmarkError != null) {
      throw bookmarkError!;
    }
    bookmarks[track.id] = bookmarked;
  }
}

/// A fake service set; override pieces as needed.
StoryServices fakeServices({
  FakeCaptureService? capture,
  FakeGallerySource? gallery,
  FakePermissionService? permissions,
  FakeMediaInspector? inspector,
  FakeStoryExporter? exporter,
  FakeGallerySaver? saver,
  MusicSession Function()? music,
  VideoSession Function()? video,
  required Directory tempDir,
}) {
  Future<String> makeFile(String ext) async {
    final f = File(
      '${tempDir.path}/f_${DateTime.now().microsecondsSinceEpoch}.$ext',
    );
    await f.writeAsBytes(const [0]);
    return f.path;
  }

  return StoryServices(
    createCapture: () =>
        capture ??
        FakeCaptureService(
          makeFile: (t) => makeFile(t == StoryMediaType.photo ? 'jpg' : 'mp4'),
        ),
    gallery:
        gallery ??
        FakeGallerySource(
          resolvePath: (a) =>
              makeFile(a.type == StoryMediaType.photo ? 'jpg' : 'mp4'),
        ),
    permissions: permissions ?? FakePermissionService(),
    inspector: inspector ?? FakeMediaInspector(),
    createMusicSession: music ?? FakeMusicSession.new,
    createVideoSession: video ?? FakeVideoSession.new,
    exporter: exporter ?? FakeStoryExporter(),
    gallerySaver: saver ?? FakeGallerySaver(),
  );
}

/// A 1×1 transparent PNG.
final Uint8List kTransparentPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
