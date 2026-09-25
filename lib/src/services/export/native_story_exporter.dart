import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../api/config/output_options.dart';
import '../../api/errors/story_exception.dart';
import '../../api/result/story_result.dart';
import '../../core/story_canvas.dart';
import '../../model/story_document.dart';
import '../../native/story_native_api.g.dart';
import '../../render/frame_composer.dart';
import '../../render/overlay_rasterizer.dart';
import '../../render/painters/story_paint_resources.dart';
import '../media/media_inspector.dart';
import '../media/native_error_mapping.dart';
import 'story_exporter.dart';

/// [StoryExporter] that renders overlays in Dart and encodes natively.
///
/// * Photo: the full frame is composed in Dart and encoded to JPEG natively.
/// * Photo with music: the composed frame becomes a still video with the
///   music segment.
/// * Video: an overlay PNG (background with a hole + edits) is composed in
///   Dart; native code decodes, trims, filters and places the video under it
///   and mixes the audio.
///
/// Files go to `ExportContext.outputDirectory`; intermediates go to the
/// session directory and are deleted when the job ends. The context's paint
/// resources must already be loaded for the document.
class NativeStoryExporter implements StoryExporter {
  /// Creates the exporter. [api] and [composer] can be replaced in tests.
  NativeStoryExporter({
    required this.inspector,
    StoryNativeApi? api,
    FrameComposer composer = const FrameComposer(),
    BinaryMessenger? eventMessenger,
  }) : _api = api ?? StoryNativeApi(),
       _composer = composer, // ignore: prefer_initializing_formals
       _eventMessenger = eventMessenger; // ignore: prefer_initializing_formals

  /// Used to probe the result.
  final MediaInspector inspector;

  final StoryNativeApi _api;
  final FrameComposer _composer;
  final BinaryMessenger? _eventMessenger;

  static int _counter = 0;

  @override
  ExportJob start(StoryDocument document, ExportContext context) {
    _counter++;
    final job = _NativeExportJob(
      id: 'story_${DateTime.now().microsecondsSinceEpoch}_$_counter',
      document: document,
      context: context,
      api: _api,
      composer: _composer,
      inspector: inspector,
      hub: ExportProgressHub.instance(_eventMessenger),
    );
    unawaited(job.run());
    return job;
  }

  /// The native request for a video story. [overlayPath] is the composed
  /// overlay PNG; [outputPath] the destination.
  @visibleForTesting
  static VideoExportRequest buildVideoRequest({
    required String jobId,
    required StoryDocument document,
    required StoryPaintResources resources,
    required OutputOptions output,
    required String outputPath,
    String? overlayPath,
  }) {
    final media = document.media;
    final duration = media.duration;
    final trim = document.trim;
    final startMs = trim?.start.inMilliseconds ?? 0;
    final endMs = trim?.end.inMilliseconds ?? duration?.inMilliseconds;
    if (endMs == null || endMs <= startMs) {
      throw StoryException(
        StoryErrorCode.exportFailed,
        'The video has no usable duration (trim $startMs–$endMs ms).',
      );
    }
    final rect = outputRect(FrameComposer.videoRect(document));
    final filter = resources.filter(document.filterId);
    return VideoExportRequest(
      jobId: jobId,
      sourcePath: media.path,
      trimStartMs: startMs,
      trimEndMs: endMs,
      videoRect: NativeRect(
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
      ),
      mirror: media.mirrored,
      colorMatrix: filter == null || filter.isIdentity
          ? null
          : List<double>.of(filter.matrix),
      overlayPngPath: overlayPath,
      originalVolume: media.hasAudio
          ? document.originalVolume.clamp(0, 1).toDouble()
          : 0,
      music: musicTrack(document),
      output: nativeOutput(output, outputPath),
    );
  }

  /// The music segment of [document] for the native mixer, or `null`.
  @visibleForTesting
  static NativeAudioTrack? musicTrack(StoryDocument document) {
    final music = document.music;
    if (music == null) {
      return null;
    }
    final path = music.localPath;
    if (path == null) {
      throw const StoryException(
        StoryErrorCode.musicUnavailable,
        'The music track was not downloaded before export.',
      );
    }
    return NativeAudioTrack(
      path: path,
      startMs: music.start.inMilliseconds,
      volume: music.volume.clamp(0, 1).toDouble(),
    );
  }

  /// Output settings.
  @visibleForTesting
  static NativeOutput nativeOutput(OutputOptions output, String path) =>
      NativeOutput(
        path: path,
        width: StoryCanvas.outputWidth,
        height: StoryCanvas.outputHeight,
        frameRate: output.frameRate,
        videoBitrate: output.videoBitrate,
      );

  /// Converts a rect in canvas units to output pixels.
  @visibleForTesting
  static ui.Rect outputRect(ui.Rect canvasRect) {
    const sx = StoryCanvas.outputWidth / StoryCanvas.width;
    const sy = StoryCanvas.outputHeight / StoryCanvas.height;
    return ui.Rect.fromLTRB(
      canvasRect.left * sx,
      canvasRect.top * sy,
      canvasRect.right * sx,
      canvasRect.bottom * sy,
    );
  }
}

/// Routes native progress events to the running jobs.
@visibleForTesting
class ExportProgressHub implements StoryNativeEvents {
  ExportProgressHub._(BinaryMessenger? messenger) {
    StoryNativeEvents.setUp(this, binaryMessenger: messenger);
  }

  static final Map<BinaryMessenger?, ExportProgressHub> _hubs = {};

  /// The hub for [messenger] (default messenger when `null`).
  // One hub per messenger: the channel accepts a single handler.
  // ignore: prefer_constructors_over_static_methods
  static ExportProgressHub instance([BinaryMessenger? messenger]) =>
      _hubs.putIfAbsent(messenger, () => ExportProgressHub._(messenger));

  final Map<String, void Function(double)> _listeners = {};

  /// Registers [onProgress] for [jobId].
  void listen(String jobId, void Function(double progress) onProgress) =>
      _listeners[jobId] = onProgress;

  /// Stops forwarding events of [jobId].
  void remove(String jobId) => _listeners.remove(jobId);

  @override
  void onExportProgress(String jobId, double progress) =>
      _listeners[jobId]?.call(progress);
}

class _NativeExportJob implements ExportJob {
  _NativeExportJob({
    required this.id,
    required this.document,
    required this.context,
    required this.api,
    required this.composer,
    required this.inspector,
    required this.hub,
  }) {
    // Callers may attach to [result] only after cancelling; the error must
    // not count as unhandled meanwhile.
    _result.future.ignore();
  }

  final String id;
  final StoryDocument document;
  final ExportContext context;
  final StoryNativeApi api;
  final FrameComposer composer;
  final MediaInspector inspector;
  final ExportProgressHub hub;

  final StreamController<double> _progress = StreamController.broadcast();
  final Completer<ExportedStory> _result = Completer();
  final List<String> _temporary = [];
  final List<String> _outputs = [];
  bool _cancelled = false;
  bool _nativeRunning = false;
  double _lastProgress = 0;

  // Share of the progress bar per phase.
  static const double _renderShare = 0.05;
  static const double _finishShare = 0.05;

  @override
  Stream<double> get progress => _progress.stream;

  @override
  Future<ExportedStory> get result => _result.future;

  @override
  Future<void> cancel() async {
    if (_result.isCompleted || _cancelled) {
      return;
    }
    _cancelled = true;
    if (_nativeRunning) {
      try {
        await api.cancelExport(id);
      } on Object catch (e, s) {
        // The job ends anyway; the native side may already be done.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: e,
            stack: s,
            library: 'story_creator_kit',
            context: ErrorDescription('while cancelling export $id'),
          ),
        );
      }
    }
    await _fail(const ExportCancelledException(), StackTrace.current);
  }

  Future<void> run() async {
    try {
      final story = await _export();
      _checkCancelled();
      _emit(1);
      await _cleanTemporary();
      _result.complete(story);
      await _progress.close();
    } on Object catch (e, s) {
      final error = _cancelled || isNativeCancellation(e)
          ? const ExportCancelledException()
          : e;
      await _fail(error, s);
    }
  }

  Future<ExportedStory> _export() async {
    _emit(0);
    final outDir = context.outputDirectory;
    await Directory(outDir).create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    if (document.outputType == StoryMediaType.photo) {
      return _exportPhoto('$outDir/story_$stamp.jpg');
    }
    final output = '$outDir/story_$stamp.mp4';
    _outputs.add(output);
    final NativeExportResult result;
    if (document.media.isVideo) {
      result = await _exportVideo(output);
    } else {
      result = await _exportPhotoWithMusic(output);
    }
    return _finishVideo(result, '$outDir/story_${stamp}_poster');
  }

  Future<ExportedStory> _exportPhoto(String output) async {
    _outputs.add(output);
    final frame = await composer.composePhotoFrame(document, context.resources);
    final Uint8List rgba;
    final int width;
    final int height;
    try {
      width = frame.width;
      height = frame.height;
      rgba = await OverlayRasterizer.encodeRgba(frame);
    } finally {
      frame.dispose();
    }
    _checkCancelled();
    _emit(0.5);
    final result = await _native(
      () => api.encodeJpeg(
        JpegEncodeRequest(
          rgba: rgba,
          width: width,
          height: height,
          quality: context.output.jpegQuality,
          outputPath: output,
        ),
      ),
    );
    _checkCancelled();
    final probe = await inspector.probe(result.path);
    return ExportedStory(
      path: result.path,
      type: StoryMediaType.photo,
      width: probe.width,
      height: probe.height,
      fileSizeBytes: probe.fileSizeBytes,
    );
  }

  Future<NativeExportResult> _exportVideo(String output) async {
    final overlay = await _writePng(
      await composer.composeVideoOverlay(document, context.resources),
      'overlay',
    );
    _checkCancelled();
    _emit(_renderShare);
    final request = NativeStoryExporter.buildVideoRequest(
      jobId: id,
      document: document,
      resources: context.resources,
      output: context.output,
      outputPath: output,
      overlayPath: overlay,
    );
    return _native(() => api.exportVideo(request));
  }

  Future<NativeExportResult> _exportPhotoWithMusic(String output) async {
    final framePath = await _writePng(
      await composer.composePhotoFrame(document, context.resources),
      'frame',
    );
    _checkCancelled();
    _emit(_renderShare);
    final duration = document.outputDuration;
    if (duration == null || duration <= Duration.zero) {
      throw const StoryException(
        StoryErrorCode.exportFailed,
        'Photo with music needs a positive music duration.',
      );
    }
    final request = StillVideoExportRequest(
      jobId: id,
      framePath: framePath,
      durationMs: duration.inMilliseconds,
      music: NativeStoryExporter.musicTrack(document),
      output: NativeStoryExporter.nativeOutput(context.output, output),
    );
    return _native(() => api.exportStillVideo(request));
  }

  Future<ExportedStory> _finishVideo(
    NativeExportResult result,
    String posterStem,
  ) async {
    _checkCancelled();
    final probe = await inspector.probe(result.path);
    _checkCancelled();
    String? poster;
    final posterDir = '$posterStem.d';
    try {
      final frames = await inspector.thumbnails(
        result.path,
        const [Duration.zero],
        outputDirectory: posterDir,
        maxWidth: StoryCanvas.outputWidth,
      );
      if (frames.isNotEmpty) {
        poster = '$posterStem.jpg';
        await File(frames.first).rename(poster);
        _outputs.add(poster);
      }
    } on StoryException catch (e, s) {
      // A missing poster does not fail the story.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: s,
          library: 'story_creator_kit',
          context: ErrorDescription('while creating the poster frame'),
        ),
      );
    } finally {
      final dir = Directory(posterDir);
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    }
    return ExportedStory(
      path: result.path,
      type: StoryMediaType.video,
      width: probe.width,
      height: probe.height,
      fileSizeBytes: probe.fileSizeBytes,
      duration:
          probe.duration ??
          (result.durationMs == null
              ? null
              : Duration(milliseconds: result.durationMs!)),
      thumbnailPath: poster,
    );
  }

  Future<String> _writePng(ui.Image image, String prefix) async {
    final Uint8List png;
    try {
      png = await OverlayRasterizer.encodePng(image);
    } finally {
      image.dispose();
    }
    final path = context.session.newPath('png', prefix: prefix);
    _temporary.add(path);
    await File(path).writeAsBytes(png, flush: true);
    return path;
  }

  Future<T> _native<T>(Future<T> Function() call) async {
    _checkCancelled();
    hub.listen(id, (p) {
      _emit(_renderShare + p.clamp(0, 1) * (1 - _renderShare - _finishShare));
    });
    _nativeRunning = true;
    try {
      return await call();
    } finally {
      _nativeRunning = false;
      hub.remove(id);
    }
  }

  void _checkCancelled() {
    if (_cancelled) {
      throw const ExportCancelledException();
    }
  }

  void _emit(double value) {
    if (_progress.isClosed || value < _lastProgress) {
      return;
    }
    _lastProgress = value;
    _progress.add(value);
  }

  Future<void> _fail(Object error, StackTrace stackTrace) async {
    // Also runs after a cancel already completed the result: a native step
    // that finished in the meantime may have written files.
    await _deleteOutputs();
    await _cleanTemporary();
    if (_result.isCompleted) {
      return;
    }
    _result.completeError(
      error is ExportCancelledException
          ? error
          : exportError(error, stackTrace, 'Export'),
      stackTrace,
    );
    if (!_progress.isClosed) {
      await _progress.close();
    }
  }

  Future<void> _deleteOutputs() async {
    for (final path in List.of(_outputs)) {
      await _deleteQuietly(path);
    }
  }

  Future<void> _cleanTemporary() async {
    final paths = List.of(_temporary);
    _temporary.clear();
    for (final path in paths) {
      await _deleteQuietly(path);
    }
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) {
        await file.delete();
      }
    } on FileSystemException {
      // Best effort; the session directory is removed later anyway.
      return;
    }
  }
}
