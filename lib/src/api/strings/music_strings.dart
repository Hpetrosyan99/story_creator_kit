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
    this.clearCategory = 'Clear search and filter',
    this.moreActions = 'More options',
    this.loading = 'Loading music…',
    this.trackLabel = _defaultTrackLabel,
  });

  static String _defaultTrackLabel(String title, String artist) =>
      '$title by $artist';

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

  /// Label of the row action (long press) that previews a track.
  final String preview;

  /// Label of the row action (long press) that stops the preview.
  final String stopPreview;

  /// Screen-reader label of the segment selector's waveform slider (the
  /// selector shows no visible title).
  final String chooseSegment;

  /// Remove selected music label.
  final String removeMusic;

  /// Shown while a track is resolved/downloaded.
  final String downloading;

  /// Error when a track cannot be resolved.
  final String trackUnavailable;

  /// Screen-reader hint of a track row: tapping the row picks the track and
  /// opens the segment selector.
  final String useTrack;

  /// Label of the button that empties the search field.
  final String clearSearch;

  /// Hint of the selected category chip; tapping its ✕ empties the search
  /// and goes back to the first category.
  final String clearCategory;

  /// Label of the ⋮ button on a ranked row (see `MusicCategory.showRanks`),
  /// which opens the bookmark menu.
  final String moreActions;

  /// Screen-reader label of the track list while its first page loads.
  final String loading;

  /// Screen-reader description of the track in the segment selector, e.g.
  /// "Daisies by Justin Bieber".
  final String Function(String title, String artist) trackLabel;
}
