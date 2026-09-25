import '../../model/story_media.dart';
import '../../services/media/media_inspector.dart';

/// Frames of the editor's video, extracted natively into the session
/// directory once and reused (trim strip, filter previews, background).
class VideoThumbnails {
  /// Creates the cache.
  VideoThumbnails({
    required this.inspector,
    required this.media,
    required this.directory,
  });

  /// Native frame extraction.
  final MediaInspector inspector;

  /// The video.
  final StoryMedia media;

  /// Session directory the frames are written into.
  final String directory;

  /// Frames in the trim strip.
  static const int stripCount = 10;

  Future<List<String>>? _strip;
  Future<String>? _first;

  /// [stripCount] frames spread evenly over [duration].
  Future<List<String>> strip(Duration duration) =>
      _strip ??= inspector.thumbnails(media.path, [
        for (var i = 0; i < stripCount; i++)
          Duration(
            microseconds: (duration.inMicroseconds * (i + 0.5) / stripCount)
                .round(),
          ),
      ], outputDirectory: directory);

  /// The first frame, small.
  Future<String> firstFrame() => _first ??= inspector
      .thumbnails(
        media.path,
        const [Duration.zero],
        outputDirectory: directory,
        maxWidth: 120,
      )
      .then((paths) => paths.first);
}
