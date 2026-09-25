import 'package:flutter/foundation.dart';

/// Facts about a local media file, read natively.
@immutable
class MediaProbe {
  /// Creates a probe result.
  const MediaProbe({
    required this.width,
    required this.height,
    required this.fileSizeBytes,
    this.duration,
    this.rotationDegrees = 0,
    this.hasVideo = false,
    this.hasAudio = false,
    this.videoCodec,
    this.audioCodec,
    this.frameRate,
  });

  /// Display width (after rotation metadata / EXIF orientation).
  final int width;

  /// Display height (after rotation metadata / EXIF orientation).
  final int height;

  /// File size.
  final int fileSizeBytes;

  /// Media length; `null` for images.
  final Duration? duration;

  /// Clockwise rotation stored in a video's metadata.
  final int rotationDegrees;

  /// Whether a video track exists.
  final bool hasVideo;

  /// Whether an audio track exists.
  final bool hasAudio;

  /// Video codec, e.g. `avc1`, `hvc1` / `video/avc`.
  final String? videoCodec;

  /// Audio codec, e.g. `mp4a` / `audio/mp4a-latm`.
  final String? audioCodec;

  /// Nominal frame rate.
  final double? frameRate;
}

/// Native media inspection helpers.
///
/// All methods throw `StoryException` (`mediaUnsupported`,
/// `mediaUnavailable`) on failure.
abstract class MediaInspector {
  /// Reads dimensions, duration, rotation and tracks of an image or video.
  Future<MediaProbe> probe(String path);

  /// Peak levels (0–1) of an audio or video file, in [buckets] even slices.
  Future<List<double>> waveform(String path, {int buckets = 120});

  /// JPEG frames of a video at [times], each at most [maxWidth] wide, written
  /// into [outputDirectory]. Returns the paths in the same order.
  Future<List<String>> thumbnails(
    String path,
    List<Duration> times, {
    required String outputDirectory,
    int maxWidth = 160,
  });
}
