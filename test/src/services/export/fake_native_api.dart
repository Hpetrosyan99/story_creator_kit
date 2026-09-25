import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:story_creator_kit/src/native/story_native_api.g.dart';

/// Records native calls; each export completes when [release] is called (or
/// immediately when [autoComplete]) and writes a small output file.
class FakeNativeApi extends StoryNativeApi {
  FakeNativeApi({this.autoComplete = true});

  bool autoComplete;
  PlatformException? error;
  final List<Object> requests = [];
  final List<String> cancelled = [];
  Completer<void> _gate = Completer();

  NativeMediaProbe probeResult = NativeMediaProbe(
    width: 1080,
    height: 1920,
    fileSizeBytes: 10,
    rotationDegrees: 0,
    hasVideo: true,
    hasAudio: true,
    durationMs: 5000,
  );

  /// Lets a waiting export finish.
  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  Future<NativeExportResult> _finish(String path, {int? durationMs}) async {
    if (!autoComplete) {
      await _gate.future;
      _gate = Completer();
    }
    if (error != null) {
      throw error!;
    }
    await File(path).writeAsBytes(const [1, 2, 3, 4]);
    return NativeExportResult(
      path: path,
      width: 1080,
      height: 1920,
      fileSizeBytes: 4,
      durationMs: durationMs,
    );
  }

  @override
  Future<NativeExportResult> exportVideo(VideoExportRequest request) {
    requests.add(request);
    return _finish(
      request.output.path,
      durationMs: request.trimEndMs - request.trimStartMs,
    );
  }

  @override
  Future<NativeExportResult> exportStillVideo(StillVideoExportRequest request) {
    requests.add(request);
    return _finish(request.output.path, durationMs: request.durationMs);
  }

  @override
  Future<NativeExportResult> encodeJpeg(JpegEncodeRequest request) {
    requests.add(request);
    return _finish(request.outputPath);
  }

  @override
  Future<void> cancelExport(String jobId) async {
    cancelled.add(jobId);
    if (!_gate.isCompleted) {
      _gate.completeError(
        PlatformException(code: 'cancelled', message: 'cancelled'),
      );
    }
  }

  @override
  Future<NativeMediaProbe> probe(String path) async {
    if (error != null) {
      throw error!;
    }
    return probeResult;
  }

  @override
  Future<List<double>> waveform(String path, int buckets) async =>
      List.filled(buckets, 0.5);

  @override
  Future<List<String>> thumbnails(
    String path,
    List<int> timesMs,
    int maxWidth,
    String outputDirectory,
  ) async {
    await Directory(outputDirectory).create(recursive: true);
    return [
      for (var i = 0; i < timesMs.length; i++)
        (File('$outputDirectory/t$i.jpg')..writeAsBytesSync(const [0])).path,
    ];
  }
}
