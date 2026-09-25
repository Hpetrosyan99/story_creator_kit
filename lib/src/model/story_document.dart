import 'package:flutter/foundation.dart';

import '../api/result/story_result.dart';
import 'drawing_stroke.dart';
import 'media_placement.dart';
import 'music_selection.dart';
import 'story_media.dart';
import 'story_overlay.dart';
import 'trim_range.dart';

/// Every edit of one story. Immutable; the editor replaces it on each change
/// and keeps snapshots for undo/redo.
///
/// All geometry is in 1080×1920 canvas units (see `StoryCanvas`).
@immutable
class StoryDocument {
  /// Creates a document.
  const StoryDocument({
    required this.media,
    this.placement = const MediaPlacement(),
    this.background = const StoryBackground(),
    this.filterId,
    this.overlays = const [],
    this.strokes = const [],
    this.trim,
    this.originalVolume = 1,
    this.music,
  });

  /// Source photo or video.
  final StoryMedia media;

  /// Media placement on the canvas.
  final MediaPlacement placement;

  /// Background around the media.
  final StoryBackground background;

  /// Selected `StoryFilter.id`; `null` for none.
  final String? filterId;

  /// Text, sticker and emoji overlays, bottom to top.
  final List<StoryOverlay> overlays;

  /// Freehand strokes in drawing order. Drawn above the media and below the
  /// overlays.
  final List<DrawingStroke> strokes;

  /// Kept part of a video; `null` keeps all of it (only valid when it fits
  /// the maximum duration).
  final TrimRange? trim;

  /// Volume of the video's own audio, 0–1.
  final double originalVolume;

  /// Music, if any.
  final MusicSelection? music;

  /// Whether the export is a video (source video, or photo with music).
  bool get exportsVideo => media.isVideo || music != null;

  /// Length of the exported video, or `null` for a photo story.
  Duration? get outputDuration {
    if (media.isVideo) {
      return trim?.duration ?? media.duration;
    }
    return music?.duration;
  }

  /// Output media type.
  StoryMediaType get outputType =>
      exportsVideo ? StoryMediaType.video : StoryMediaType.photo;

  /// Returns a copy with the given values replaced. Use [clearFilter],
  /// [clearTrim] and [clearMusic] to set those to `null`.
  StoryDocument copyWith({
    StoryMedia? media,
    MediaPlacement? placement,
    StoryBackground? background,
    String? filterId,
    List<StoryOverlay>? overlays,
    List<DrawingStroke>? strokes,
    TrimRange? trim,
    double? originalVolume,
    MusicSelection? music,
    bool clearFilter = false,
    bool clearTrim = false,
    bool clearMusic = false,
  }) => StoryDocument(
    media: media ?? this.media,
    placement: placement ?? this.placement,
    background: background ?? this.background,
    filterId: clearFilter ? null : (filterId ?? this.filterId),
    overlays: overlays ?? this.overlays,
    strokes: strokes ?? this.strokes,
    trim: clearTrim ? null : (trim ?? this.trim),
    originalVolume: originalVolume ?? this.originalVolume,
    music: clearMusic ? null : (music ?? this.music),
  );

  @override
  bool operator ==(Object other) =>
      other is StoryDocument &&
      other.media == media &&
      other.placement == placement &&
      other.background == background &&
      other.filterId == filterId &&
      listEquals(other.overlays, overlays) &&
      listEquals(other.strokes, strokes) &&
      other.trim == trim &&
      other.originalVolume == originalVolume &&
      other.music == music;

  @override
  int get hashCode => Object.hash(
    media,
    placement,
    background,
    filterId,
    Object.hashAll(overlays),
    Object.hashAll(strokes),
    trim,
    originalVolume,
    music,
  );
}
