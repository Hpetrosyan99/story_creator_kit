import '../../native/story_native_api.g.dart';
import 'media_inspector.dart';
import 'native_error_mapping.dart';

/// [MediaInspector] backed by the plugin's native code (AVFoundation on iOS,
/// MediaMetadataRetriever / MediaCodec on Android).
class NativeMediaInspector implements MediaInspector {
  /// Creates the inspector. [api] replaces the Pigeon channel (tests).
  NativeMediaInspector({StoryNativeApi? api}) : _api = api ?? StoryNativeApi();

  final StoryNativeApi _api;

  @override
  Future<MediaProbe> probe(String path) async {
    try {
      final p = await _api.probe(path);
      return MediaProbe(
        width: p.width,
        height: p.height,
        fileSizeBytes: p.fileSizeBytes,
        duration: p.durationMs == null
            ? null
            : Duration(milliseconds: p.durationMs!),
        rotationDegrees: p.rotationDegrees,
        hasVideo: p.hasVideo,
        hasAudio: p.hasAudio,
        videoCodec: p.videoCodec,
        audioCodec: p.audioCodec,
        frameRate: p.frameRate,
      );
    } on Object catch (e, s) {
      throw inspectionError(e, s, 'Probing $path');
    }
  }

  @override
  Future<List<double>> waveform(String path, {int buckets = 120}) async {
    try {
      return await _api.waveform(path, buckets);
    } on Object catch (e, s) {
      throw inspectionError(e, s, 'Waveform of $path');
    }
  }

  @override
  Future<List<String>> thumbnails(
    String path,
    List<Duration> times, {
    required String outputDirectory,
    int maxWidth = 160,
  }) async {
    try {
      return await _api.thumbnails(
        path,
        [for (final t in times) t.inMilliseconds],
        maxWidth,
        outputDirectory,
      );
    } on Object catch (e, s) {
      throw inspectionError(e, s, 'Thumbnails of $path');
    }
  }
}
