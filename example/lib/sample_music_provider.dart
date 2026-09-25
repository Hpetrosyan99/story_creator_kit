import 'package:flutter/painting.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

/// An in-memory catalog of the example's bundled, self-generated tracks.
///
/// A real app would query its own licensed catalog here.
class SampleMusicProvider extends StoryMusicProvider {
  SampleMusicProvider();

  static const _all = MusicCategory(id: 'all', label: 'All');
  static const _bookmarked = MusicCategory(
    id: 'bookmarked',
    label: 'Bookmarked',
  );
  static const _leaderboard = MusicCategory(
    id: 'leaderboard',
    label: 'Leaderboard',
  );

  static const _tracks = <_SampleTrack>[
    _SampleTrack(
      'sunrise',
      'Sunrise Drive',
      'Story Kit Band',
      'sunrise_drive',
      Duration(milliseconds: 66786),
    ),
    _SampleTrack(
      'midnight',
      'Midnight Pulse',
      'Story Kit Band',
      'midnight_pulse',
      Duration(milliseconds: 62500),
    ),
    _SampleTrack(
      'paper',
      'Paper Planes',
      'Loop Collective',
      'paper_planes',
      Duration(milliseconds: 87500),
    ),
    _SampleTrack(
      'lofi',
      'Slow Coffee',
      'Loop Collective',
      'slow_coffee',
      Duration(milliseconds: 76786),
    ),
  ];

  final Set<String> _bookmarks = {'paper'};

  @override
  List<MusicCategory> get categories => const [_all, _bookmarked, _leaderboard];

  @override
  bool get supportsBookmarks => true;

  @override
  Future<MusicPage> fetchTracks(MusicQuery query) async {
    // Simulated network latency, so loading states are visible.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final search = query.search.trim().toLowerCase();
    var tracks = _tracks
        .map(_toTrack)
        .where(
          (t) =>
              search.isEmpty ||
              t.title.toLowerCase().contains(search) ||
              t.artist.toLowerCase().contains(search),
        );
    switch (query.categoryId) {
      case 'bookmarked':
        tracks = tracks.where((t) => t.bookmarked);
      case 'leaderboard':
        tracks = tracks.toList().reversed;
    }
    return MusicPage(tracks: tracks.toList());
  }

  @override
  Future<MusicSource> resolve(MusicTrack track) async {
    final sample = _tracks.firstWhere((t) => t.id == track.id);
    return MusicAssetSource('assets/music/${sample.file}.m4a');
  }

  @override
  Future<void> setBookmarked(
    MusicTrack track, {
    required bool bookmarked,
  }) async {
    if (bookmarked) {
      _bookmarks.add(track.id);
    } else {
      _bookmarks.remove(track.id);
    }
  }

  MusicTrack _toTrack(_SampleTrack t) => MusicTrack(
    id: t.id,
    title: t.title,
    artist: t.artist,
    duration: t.duration,
    bookmarked: _bookmarks.contains(t.id),
    artwork: _Artwork.forId(t.id),
  );
}

class _SampleTrack {
  const _SampleTrack(
    this.id,
    this.title,
    this.artist,
    this.file,
    this.duration,
  );

  final String id;
  final Duration duration;
  final String title;
  final String artist;
  final String file;
}

abstract final class _Artwork {
  static ImageProvider forId(String id) =>
      AssetImage('assets/music/artwork_$id.png');
}
