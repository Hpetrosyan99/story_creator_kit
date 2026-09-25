import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// A tab/chip in the music picker, e.g. "All", "Bookmarked", "Leaderboard".
@immutable
class MusicCategory {
  /// Creates a category.
  const MusicCategory({required this.id, required this.label});

  /// Identifier passed back in [MusicQuery.categoryId].
  final String id;

  /// Chip label.
  final String label;

  @override
  bool operator ==(Object other) => other is MusicCategory && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A track offered by a `StoryMusicProvider`.
@immutable
class MusicTrack {
  /// Creates a track.
  const MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    this.artwork,
    this.bookmarked = false,
    this.waveform,
    this.extra = const {},
  });

  /// Stable identifier, reported in `StoryMetadata`.
  final String id;

  /// Track title.
  final String title;

  /// Artist or subtitle line.
  final String artist;

  /// Full track length.
  final Duration duration;

  /// Cover art, if any.
  final ImageProvider? artwork;

  /// Whether the user bookmarked this track.
  final bool bookmarked;

  /// Optional precomputed waveform peaks, each in 0–1, evenly spaced over the
  /// track. When absent, the library extracts peaks from the audio file.
  final List<double>? waveform;

  /// Host data carried through untouched (licence ids, analytics tags…).
  final Map<String, Object?> extra;

  /// Returns a copy with the given values replaced.
  MusicTrack copyWith({bool? bookmarked, List<double>? waveform}) => MusicTrack(
    id: id,
    title: title,
    artist: artist,
    duration: duration,
    artwork: artwork,
    bookmarked: bookmarked ?? this.bookmarked,
    waveform: waveform ?? this.waveform,
    extra: extra,
  );

  @override
  bool operator ==(Object other) =>
      other is MusicTrack && other.id == id && other.bookmarked == bookmarked;

  @override
  int get hashCode => Object.hash(id, bookmarked);
}

/// A request for one page of tracks.
@immutable
class MusicQuery {
  /// Creates a query.
  const MusicQuery({
    required this.categoryId,
    this.search = '',
    this.cursor,
    this.pageSize = 30,
  });

  /// Selected category id.
  final String categoryId;

  /// Search text; empty for none.
  final String search;

  /// Cursor from the previous page's [MusicPage.nextCursor]; `null` for the
  /// first page.
  final String? cursor;

  /// Suggested number of tracks per page.
  final int pageSize;
}

/// One page of tracks.
@immutable
class MusicPage {
  /// Creates a page. A `null` [nextCursor] means there are no more pages.
  const MusicPage({required this.tracks, this.nextCursor});

  /// Tracks in display order.
  final List<MusicTrack> tracks;

  /// Cursor for the next page, or `null` at the end.
  final String? nextCursor;
}

/// Where the audio of a track can be read from.
@immutable
sealed class MusicSource {
  const MusicSource();
}

/// A local audio file.
final class MusicFileSource extends MusicSource {
  /// Creates a file source.
  const MusicFileSource(this.path);

  /// Absolute file path.
  final String path;
}

/// A Flutter asset, e.g. a track bundled with the host app.
final class MusicAssetSource extends MusicSource {
  /// Creates an asset source.
  const MusicAssetSource(this.assetKey, {this.package});

  /// Asset key as declared in `pubspec.yaml`.
  final String assetKey;

  /// Package that bundles the asset, if any.
  final String? package;
}

/// A remote file. It is streamed for preview and downloaded before export.
final class MusicUrlSource extends MusicSource {
  /// Creates a URL source.
  const MusicUrlSource(this.uri, {this.headers = const {}});

  /// HTTP(S) location of an audio file (AAC/M4A, MP3 or WAV).
  final Uri uri;

  /// Request headers, e.g. authorisation.
  final Map<String, String> headers;
}
