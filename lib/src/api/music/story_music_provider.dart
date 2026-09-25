import 'music_models.dart';

/// Supplies the music catalog shown in the story creator.
///
/// Implement this against your own catalog or licensing backend. The library
/// never talks to a music service itself.
abstract class StoryMusicProvider {
  /// Allows subclasses to be const.
  const StoryMusicProvider();

  /// Categories shown as chips; the first one is selected initially. Must not
  /// be empty.
  List<MusicCategory> get categories;

  /// Returns one page of tracks for [query].
  ///
  /// Throw any error to show the picker's error state with a retry button.
  Future<MusicPage> fetchTracks(MusicQuery query);

  /// Resolves where the audio of [track] can be read from.
  Future<MusicSource> resolve(MusicTrack track);

  /// Whether the picker shows bookmark buttons.
  bool get supportsBookmarks => false;

  /// Stores the bookmark state of [track]. Called only when
  /// [supportsBookmarks] is true.
  Future<void> setBookmarked(MusicTrack track, {required bool bookmarked}) =>
      Future.error(UnsupportedError('Bookmarks are not supported.'));
}
