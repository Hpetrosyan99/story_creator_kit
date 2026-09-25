import 'package:flutter/foundation.dart';

import '../errors/story_exception.dart';

/// Photo or video.
enum StoryMediaType {
  /// A still image.
  photo,

  /// A video.
  video,
}

/// Where the source media came from.
enum StorySourceKind {
  /// Captured in the story creator's camera.
  camera,

  /// Picked from the device gallery.
  gallery,
}

/// Why the flow ended without a story.
enum StoryCancelReason {
  /// The user closed the creator.
  userCancelled,

  /// The host route was popped (system back, programmatic pop).
  dismissed,
}

/// How the flow ended.
@immutable
sealed class StoryOutcome {
  const StoryOutcome();
}

/// The user confirmed an exported story.
final class StoryCompleted extends StoryOutcome {
  /// Creates a completed outcome.
  const StoryCompleted(this.result);

  /// The exported story.
  final StoryResult result;
}

/// The user left without a story.
final class StoryCancelled extends StoryOutcome {
  /// Creates a cancelled outcome.
  const StoryCancelled(this.reason);

  /// Why the flow ended.
  final StoryCancelReason reason;
}

/// The flow could not continue, e.g. no camera and no gallery available.
///
/// Recoverable errors (a failed export the user can retry) are shown in the
/// UI and reported through `onEvent`; they end the flow only if the user
/// leaves.
final class StoryFailed extends StoryOutcome {
  /// Creates a failed outcome.
  const StoryFailed(this.error);

  /// What went wrong.
  final StoryException error;
}

/// The exported story file and what went into it.
@immutable
class StoryResult {
  /// Creates a result.
  const StoryResult({
    required this.path,
    required this.type,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.fileSizeBytes,
    required this.metadata,
    this.duration,
    this.thumbnailPath,
    this.savedToGallery = false,
  });

  /// Absolute path of the exported file. It is outside the session's temp
  /// folder and is not deleted by the library.
  final String path;

  /// Photo (JPEG) or video (MP4).
  final StoryMediaType type;

  /// `image/jpeg` or `video/mp4`.
  final String mimeType;

  /// Pixel width (1080).
  final int width;

  /// Pixel height (1920).
  final int height;

  /// File size.
  final int fileSizeBytes;

  /// Video length; `null` for photos.
  final Duration? duration;

  /// JPEG poster frame for videos; `null` for photos.
  final String? thumbnailPath;

  /// Whether the story was saved to the device gallery.
  final bool savedToGallery;

  /// What the story contains.
  final StoryMetadata metadata;
}

/// Music used in the story.
@immutable
class StoryMusicMetadata {
  /// Creates music metadata.
  const StoryMusicMetadata({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.start,
    required this.duration,
    required this.volume,
    this.extra = const {},
  });

  /// `MusicTrack.id`.
  final String trackId;

  /// Track title.
  final String title;

  /// Track artist.
  final String artist;

  /// Offset into the track where the segment starts.
  final Duration start;

  /// Segment length.
  final Duration duration;

  /// Music volume, 0–1.
  final double volume;

  /// `MusicTrack.extra`, passed through.
  final Map<String, Object?> extra;
}

/// A text overlay in the story.
@immutable
class StoryTextMetadata {
  /// Creates text metadata.
  const StoryTextMetadata({
    required this.text,
    required this.fontId,
    required this.colorValue,
  });

  /// The text.
  final String text;

  /// `StoryFont.id`.
  final String fontId;

  /// ARGB colour value.
  final int colorValue;
}

/// What went into a story.
@immutable
class StoryMetadata {
  /// Creates metadata.
  const StoryMetadata({
    required this.source,
    required this.sourceType,
    required this.createdAt,
    this.trimStart,
    this.trimEnd,
    this.originalAudioVolume = 1,
    this.music,
    this.filterId,
    this.texts = const [],
    this.stickerIds = const [],
    this.emojis = const [],
    this.hasDrawing = false,
  });

  /// Camera or gallery.
  final StorySourceKind source;

  /// Type of the source media (a photo with music exports as video).
  final StoryMediaType sourceType;

  /// When the story was exported.
  final DateTime createdAt;

  /// Trim start in the source video.
  final Duration? trimStart;

  /// Trim end in the source video.
  final Duration? trimEnd;

  /// Volume of the source video's own audio, 0–1 (0 = muted).
  final double originalAudioVolume;

  /// Music, if any.
  final StoryMusicMetadata? music;

  /// `StoryFilter.id`, or `null` for none.
  final String? filterId;

  /// Text overlays, bottom to top.
  final List<StoryTextMetadata> texts;

  /// `StorySticker.id`s used, bottom to top.
  final List<String> stickerIds;

  /// Emoji used, bottom to top.
  final List<String> emojis;

  /// Whether the story has freehand drawing.
  final bool hasDrawing;
}

/// Convenience accessors.
extension StoryOutcomeX on StoryOutcome {
  /// The result if completed, otherwise `null`.
  StoryResult? get resultOrNull => switch (this) {
    StoryCompleted(:final result) => result,
    _ => null,
  };
}
