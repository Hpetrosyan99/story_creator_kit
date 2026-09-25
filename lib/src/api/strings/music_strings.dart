import 'package:flutter/foundation.dart';

/// Music picker and segment selector strings.
///
/// Owned by the music area; add fields here as that area needs them.
@immutable
class MusicStrings {
  /// Creates the music strings. Defaults are English.
  const MusicStrings({
    this.title = 'Add music',
    this.searchHint = 'Search music',
    this.noResults = 'No tracks found.',
    this.loadFailed = 'Music could not be loaded.',
    this.offline = 'You appear to be offline.',
    this.bookmark = 'Bookmark',
    this.removeBookmark = 'Remove bookmark',
    this.preview = 'Preview',
    this.stopPreview = 'Stop preview',
    this.chooseSegment = 'Choose the part to use',
    this.removeMusic = 'Remove music',
    this.downloading = 'Preparing track…',
    this.trackUnavailable = 'This track is unavailable.',
    this.useTrack = 'Use this track',
    this.clearSearch = 'Clear search',
    this.clearCategory = 'Clear filter',
  });

  /// Picker title.
  final String title;

  /// Search field hint.
  final String searchHint;

  /// Empty results message.
  final String noResults;

  /// Load error message.
  final String loadFailed;

  /// Offline error message.
  final String offline;

  /// Bookmark action label.
  final String bookmark;

  /// Remove bookmark action label.
  final String removeBookmark;

  /// Start preview label.
  final String preview;

  /// Stop preview label.
  final String stopPreview;

  /// Segment selector title.
  final String chooseSegment;

  /// Remove selected music label.
  final String removeMusic;

  /// Shown while a track is resolved/downloaded.
  final String downloading;

  /// Error when a track cannot be resolved.
  final String trackUnavailable;

  /// Label of the button on a track row that picks the track and opens the
  /// segment selector (tapping the row itself only previews it).
  final String useTrack;

  /// Label of the button that empties the search field.
  final String clearSearch;

  /// Hint of the selected category chip; tapping it goes back to the first
  /// category.
  final String clearCategory;
}
