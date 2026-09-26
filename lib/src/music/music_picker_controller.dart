import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../api/errors/story_exception.dart';
import '../api/music/music_models.dart';
import '../api/music/story_music_provider.dart';

/// Default delay between the last keystroke and the search request.
const Duration kMusicSearchDebounce = Duration(milliseconds: 350);

/// What the track list shows.
enum MusicListStatus {
  /// The first page is loading.
  loading,

  /// Tracks are shown.
  ready,

  /// The query returned no tracks.
  empty,

  /// The first page failed to load.
  error,

  /// The first page failed because the device appears to be offline.
  offline,
}

/// Whether [error] looks like a network failure (no connection, a broken
/// HTTP exchange, a TLS failure or a timeout), also when wrapped in a
/// [StoryException].
bool isMusicNetworkError(Object error) {
  if (error is SocketException ||
      error is HttpException ||
      error is TlsException ||
      error is TimeoutException) {
    return true;
  }
  if (error is StoryException) {
    final cause = error.cause;
    return cause != null && isMusicNetworkError(cause);
  }
  return false;
}

/// State of the music picker's catalog: category, debounced search, paged
/// track list and optimistic bookmarks.
///
/// Responses that arrive after the query or category changed are dropped.
class MusicPickerController extends ChangeNotifier {
  /// Creates a controller for [provider]. Call [start] to load the first page.
  MusicPickerController({
    required this.provider,
    this.searchDebounce = kMusicSearchDebounce,
    this.pageSize = 30,
    this.onError,
  }) : _category = provider.categories.first;

  /// The catalog.
  final StoryMusicProvider provider;

  /// Delay between the last [setSearch] call and the request.
  final Duration searchDebounce;

  /// Tracks requested per page.
  final int pageSize;

  /// Receives failures of catalog requests and bookmark updates.
  final void Function(Object error, StackTrace stackTrace)? onError;

  MusicCategory _category;
  String _search = '';
  final List<MusicTrack> _tracks = [];
  MusicListStatus _status = MusicListStatus.loading;
  String? _cursor;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  bool _started = false;
  bool _disposed = false;
  int _generation = 0;
  Timer? _debounce;
  final Map<String, bool> _bookmarks = {};
  final Set<String> _bookmarkPending = {};

  /// Scroll offset of the list, kept while the picker is hidden behind the
  /// segment selector.
  double scrollOffset = 0;

  /// Categories of the provider.
  List<MusicCategory> get categories => provider.categories;

  /// The selected category.
  MusicCategory get category => _category;

  /// Whether the first category is selected.
  bool get isFirstCategory => _category == categories.first;

  /// The search text in effect (after the debounce).
  String get search => _search;

  /// Loaded tracks in display order.
  List<MusicTrack> get tracks => UnmodifiableListView(_tracks);

  /// What the list shows.
  MusicListStatus get status => _status;

  /// Whether another page exists.
  bool get hasMore => _cursor != null;

  /// Whether the next page is loading.
  bool get loadingMore => _loadingMore;

  /// Whether the last next-page request failed; [retryLoadMore] tries again.
  bool get loadMoreFailed => _loadMoreFailed;

  /// Loads the first page once.
  Future<void> start() {
    if (_started) {
      return Future.value();
    }
    _started = true;
    return _reload();
  }

  /// Schedules a search for [text] after [searchDebounce].
  void setSearch(String text) {
    _debounce?.cancel();
    final next = text.trim();
    _debounce = Timer(searchDebounce, () => _applySearch(next));
  }

  /// Searches for [text] right away (keyboard submit, clear button).
  void searchNow(String text) {
    _debounce?.cancel();
    _applySearch(text.trim());
  }

  void _applySearch(String text) {
    if (text == _search || _disposed) {
      return;
    }
    _search = text;
    unawaited(_reload());
  }

  /// Selects [value] and reloads.
  void selectCategory(MusicCategory value) {
    if (value == _category) {
      return;
    }
    _category = value;
    unawaited(_reload());
  }

  /// Goes back to the first category.
  void clearCategory() => selectCategory(categories.first);

  /// Empties the search and goes back to the first category, with a single
  /// reload (none when nothing changes). Cancels a pending debounced search.
  void resetFilters() {
    _debounce?.cancel();
    final first = categories.first;
    if (_search.isEmpty && _category == first) {
      return;
    }
    _search = '';
    _category = first;
    unawaited(_reload());
  }

  /// Reloads the first page after an error.
  Future<void> retry() => _reload();

  /// Loads the next page unless one is loading, none exists or the last one
  /// failed.
  Future<void> loadMore() async {
    final cursor = _cursor;
    if (cursor == null ||
        _loadingMore ||
        _loadMoreFailed ||
        _status != MusicListStatus.ready ||
        _disposed) {
      return;
    }
    final generation = _generation;
    _loadingMore = true;
    _notify();
    try {
      final page = await provider.fetchTracks(_query(cursor));
      if (generation != _generation || _disposed) {
        return;
      }
      final seen = {for (final t in _tracks) t.id};
      _tracks.addAll(page.tracks.where((t) => seen.add(t.id)));
      _cursor = page.nextCursor;
    } on Object catch (e, s) {
      if (generation != _generation || _disposed) {
        return;
      }
      _loadMoreFailed = true;
      onError?.call(e, s);
    }
    _loadingMore = false;
    _notify();
  }

  /// Retries a failed next-page request.
  Future<void> retryLoadMore() {
    _loadMoreFailed = false;
    return loadMore();
  }

  /// Whether [track] is bookmarked, including pending changes.
  bool isBookmarked(MusicTrack track) =>
      _bookmarks[track.id] ?? track.bookmarked;

  /// Flips the bookmark of [track] at once and stores it with the provider;
  /// reverts when that fails.
  Future<void> toggleBookmark(MusicTrack track) async {
    if (!provider.supportsBookmarks || _bookmarkPending.contains(track.id)) {
      return;
    }
    final previous = isBookmarked(track);
    _bookmarks[track.id] = !previous;
    _bookmarkPending.add(track.id);
    _notify();
    try {
      await provider.setBookmarked(track, bookmarked: !previous);
    } on Object catch (e, s) {
      _bookmarks[track.id] = previous;
      onError?.call(e, s);
    } finally {
      _bookmarkPending.remove(track.id);
      _notify();
    }
  }

  MusicQuery _query(String? cursor) => MusicQuery(
    categoryId: _category.id,
    search: _search,
    cursor: cursor,
    pageSize: pageSize,
  );

  Future<void> _reload() async {
    final generation = ++_generation;
    _tracks.clear();
    _cursor = null;
    _loadingMore = false;
    _loadMoreFailed = false;
    _status = MusicListStatus.loading;
    _notify();
    try {
      final page = await provider.fetchTracks(_query(null));
      if (generation != _generation || _disposed) {
        return;
      }
      _tracks.addAll(page.tracks);
      _cursor = page.nextCursor;
      _status = _tracks.isEmpty ? MusicListStatus.empty : MusicListStatus.ready;
    } on Object catch (e, s) {
      if (generation != _generation || _disposed) {
        return;
      }
      _status = isMusicNetworkError(e)
          ? MusicListStatus.offline
          : MusicListStatus.error;
      onError?.call(e, s);
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
