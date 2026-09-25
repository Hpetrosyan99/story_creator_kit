// Contract between the Dart side of story_creator_kit and its native code.
//
// Regenerate after editing:
//   dart run pigeon --input pigeons/story_native_api.dart
//
// Errors: native methods fail with a PlatformException whose `code` is one of
//   'cancelled'         the job was cancelled via cancelExport
//   'invalid_input'     a request field is wrong (missing file, bad rect…)
//   'unsupported_media' the file cannot be decoded
//   'no_space'          not enough storage
//   'encoder'           the platform encoder / export session failed
//   'io'                reading or writing a file failed
//   'unknown'           anything else
// `message` is developer-facing; `details` may carry a platform error string.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/native/story_native_api.g.dart',
    dartPackageName: 'story_creator_kit',
    kotlinOut: 'android/src/main/kotlin/com/mabrook/story_creator_kit/StoryNativeApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.mabrook.story_creator_kit'),
    swiftOut: 'ios/story_creator_kit/Sources/story_creator_kit/StoryNativeApi.g.swift',
  ),
)
/// A rectangle in output pixels (origin top-left).
class NativeRect {
  NativeRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  double left;
  double top;
  double width;
  double height;
}

/// An extra audio track mixed into the output.
class NativeAudioTrack {
  NativeAudioTrack({
    required this.path,
    required this.startMs,
    required this.volume,
  });

  /// Local audio file (M4A/AAC, MP3, WAV).
  String path;

  /// Offset into the audio file where playback starts.
  int startMs;

  /// 0–1.
  double volume;
}

/// Common output settings.
class NativeOutput {
  NativeOutput({
    required this.path,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.videoBitrate,
  });

  /// Destination .mp4 path; overwritten if it exists.
  String path;
  int width;
  int height;
  int frameRate;

  /// H.264 target bitrate, bits per second.
  int videoBitrate;
}

/// Export of a source video onto the story canvas.
///
/// Frame composition, bottom to top:
///   1. transparent/black canvas of output size
///   2. the source video frame, rotated per its metadata, mirrored when
///      [mirror], colour-transformed by [colorMatrix], drawn scaled into
///      [videoRect] (may extend past the canvas; clipped)
///   3. [overlayPngPath], a full-canvas RGBA PNG drawn at (0,0) at output
///      size. It already contains the background with a transparent hole
///      where the video shows, plus drawings and overlays.
/// Audio: the source audio in [trimStartMs, trimEndMs) at [originalVolume]
/// (omitted when 0 or absent), mixed with [music] trimmed to the output
/// length. Output is AAC 44.1 kHz stereo; no audio track when both are
/// absent.
class VideoExportRequest {
  VideoExportRequest({
    required this.jobId,
    required this.sourcePath,
    required this.trimStartMs,
    required this.trimEndMs,
    required this.videoRect,
    required this.mirror,
    required this.originalVolume,
    required this.output,
    this.colorMatrix,
    this.overlayPngPath,
    this.music,
  });

  String jobId;
  String sourcePath;
  int trimStartMs;
  int trimEndMs;
  NativeRect videoRect;
  bool mirror;

  /// 20 values, row-major 4×5, offsets in 0–255 (Flutter ColorFilter.matrix
  /// semantics). `null` = identity.
  List<double>? colorMatrix;
  String? overlayPngPath;
  double originalVolume;
  NativeAudioTrack? music;
  NativeOutput output;
}

/// A video made from one still frame (photo story with music).
class StillVideoExportRequest {
  StillVideoExportRequest({
    required this.jobId,
    required this.framePath,
    required this.durationMs,
    required this.output,
    this.music,
  });

  String jobId;

  /// Fully composed frame at output size (PNG or JPEG).
  String framePath;
  int durationMs;
  NativeAudioTrack? music;
  NativeOutput output;
}

/// JPEG encoding of raw pixels.
class JpegEncodeRequest {
  JpegEncodeRequest({
    required this.rgba,
    required this.width,
    required this.height,
    required this.quality,
    required this.outputPath,
  });

  /// Straight (non-premultiplied) RGBA8888, row-major, width*height*4 bytes.
  Uint8List rgba;
  int width;
  int height;

  /// 1–100.
  int quality;
  String outputPath;
}

class NativeExportResult {
  NativeExportResult({
    required this.path,
    required this.width,
    required this.height,
    required this.fileSizeBytes,
    this.durationMs,
  });

  String path;
  int width;
  int height;
  int fileSizeBytes;
  int? durationMs;
}

class NativeMediaProbe {
  NativeMediaProbe({
    required this.width,
    required this.height,
    required this.fileSizeBytes,
    required this.rotationDegrees,
    required this.hasVideo,
    required this.hasAudio,
    this.durationMs,
    this.videoCodec,
    this.audioCodec,
    this.frameRate,
  });

  /// Display size (rotation / EXIF orientation applied).
  int width;
  int height;
  int fileSizeBytes;
  int rotationDegrees;
  bool hasVideo;
  bool hasAudio;
  int? durationMs;
  String? videoCodec;
  String? audioCodec;
  double? frameRate;
}

@HostApi()
abstract class StoryNativeApi {
  @async
  NativeExportResult exportVideo(VideoExportRequest request);

  @async
  NativeExportResult exportStillVideo(StillVideoExportRequest request);

  @async
  NativeExportResult encodeJpeg(JpegEncodeRequest request);

  /// Cancels a running export; its call fails with code 'cancelled' and the
  /// partial output is deleted. No-op for unknown ids.
  void cancelExport(String jobId);

  /// Images (JPEG, PNG, HEIC, WebP) and videos.
  @async
  NativeMediaProbe probe(String path);

  /// Peak levels 0–1 in [buckets] even slices of the whole file's audio.
  @async
  List<double> waveform(String path, int buckets);

  /// JPEG frames at [timesMs], at most [maxWidth] wide, written into
  /// [outputDirectory]; returns paths in the same order.
  @async
  List<String> thumbnails(
    String path,
    List<int> timesMs,
    int maxWidth,
    String outputDirectory,
  );
}

@FlutterApi()
abstract class StoryNativeEvents {
  /// Progress 0–1 of a running export.
  void onExportProgress(String jobId, double progress);
}
