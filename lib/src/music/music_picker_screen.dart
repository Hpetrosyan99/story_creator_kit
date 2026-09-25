import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/errors/story_exception.dart';
import '../api/music/music_models.dart';
import '../core/story_scope.dart';
import '../model/music_selection.dart';
import 'music_file_cache.dart';
import 'music_picker_controller.dart';
import 'music_preview_controller.dart';
import 'music_track_preparer.dart';
import 'widgets/category_chips.dart';
import 'widgets/music_list_message.dart';
import 'widgets/music_search_field.dart';
import 'widgets/track_tile.dart';

/// How the music list screen was left, when not by going back (`null`).
sealed class MusicPickerOutcome {
  const MusicPickerOutcome();
}

/// The user removed the story's music.
final class MusicPickerRemoved extends MusicPickerOutcome {
  /// Creates the outcome.
  const MusicPickerRemoved();
}

/// The user picked a track, now prepared for the segment selector.
final class MusicPickerChose extends MusicPickerOutcome {
  /// Creates the outcome.
  const MusicPickerChose(this.prepared);

  /// The prepared track.
  final PreparedMusicTrack prepared;
}

/// Full-screen music list: search, category chips and the paged track list.
///
/// Pops with `null` on back, [MusicPickerRemoved] or [MusicPickerChose].
/// Leaving while a track is being prepared cancels its download.
class MusicPickerScreen extends StatefulWidget {
  /// Creates the screen. The controllers are owned by the caller.
  const MusicPickerScreen({
    required this.controller,
    required this.preview,
    required this.preparer,
    this.current,
    super.key,
  });

  /// Catalog state.
  final MusicPickerController controller;

  /// Row previews.
  final MusicPreviewController preview;

  /// Prepares the picked track.
  final MusicTrackPreparer preparer;

  /// The story's current music; enables "Remove music".
  final MusicSelection? current;

  @override
  State<MusicPickerScreen> createState() => _MusicPickerScreenState();
}

class _MusicPickerScreenState extends State<MusicPickerScreen> {
  static const double _loadMoreExtent = 480;

  final ScrollController _scroll = ScrollController();
  late final TextEditingController _search = TextEditingController(
    text: widget.controller.search,
  );
  final ValueNotifier<double?> _progress = ValueNotifier(null);
  double? _restoreOffset;
  MusicTrack? _preparing;
  MusicCancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    final saved = widget.controller.scrollOffset;
    _restoreOffset = saved > 0 ? saved : null;
    widget.controller.addListener(_onCatalogChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFrame());
  }

  @override
  void dispose() {
    _cancel?.cancel();
    widget.controller.removeListener(_onCatalogChanged);
    if (_scroll.hasClients) {
      widget.controller.scrollOffset = _scroll.offset;
    }
    _scroll.dispose();
    _search.dispose();
    _progress.dispose();
    super.dispose();
  }

  void _onCatalogChanged() {
    if (widget.controller.status != MusicListStatus.ready) {
      _restoreOffset = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFrame());
  }

  void _afterFrame() {
    if (!mounted || !_scroll.hasClients) {
      return;
    }
    final restore = _restoreOffset;
    if (restore != null) {
      _restoreOffset = null;
      _scroll.jumpTo(restore);
    }
    _maybeLoadMore();
  }

  void _maybeLoadMore() {
    final controller = widget.controller;
    if (!mounted ||
        !_scroll.hasClients ||
        !controller.hasMore ||
        controller.loadingMore ||
        controller.loadMoreFailed ||
        controller.status != MusicListStatus.ready) {
      return;
    }
    if (_scroll.position.extentAfter < _loadMoreExtent) {
      unawaited(controller.loadMore());
    }
  }

  void _back() {
    _cancel?.cancel();
    Navigator.of(context).pop();
  }

  void _remove() {
    _cancel?.cancel();
    Navigator.of(context).pop(const MusicPickerRemoved());
  }

  Future<void> _togglePreview(MusicTrack track) async {
    if (_preparing != null) {
      return;
    }
    try {
      await widget.preview.toggle(track);
    } on StoryException catch (e) {
      _showUnavailable(e);
    }
  }

  Future<void> _use(MusicTrack track) async {
    if (_preparing != null) {
      return;
    }
    final cancel = MusicCancelToken();
    _progress.value = null;
    setState(() {
      _preparing = track;
      _cancel = cancel;
    });
    try {
      await widget.preview.stop();
      final prepared = await widget.preparer.prepare(
        track,
        cancel: cancel,
        onProgress: (value) {
          if (mounted && !cancel.isCancelled) {
            _progress.value = value;
          }
        },
      );
      if (mounted && !cancel.isCancelled) {
        Navigator.of(context).pop(MusicPickerChose(prepared));
      }
    } on MusicCancelledException {
      // The user left; nothing to show.
      return;
    } on StoryException catch (e) {
      if (!cancel.isCancelled) {
        _showUnavailable(e);
      }
    } finally {
      if (mounted && identical(_cancel, cancel)) {
        setState(() {
          _preparing = null;
          _cancel = null;
        });
      }
    }
  }

  void _showUnavailable(StoryException error) {
    if (!mounted) {
      return;
    }
    final scope = StoryScope.read(context);
    final theme = scope.theme;
    scope.reportError(error);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: theme.surfaceVariant,
          content: Text(
            scope.strings.music.trackUnavailable,
            style: theme.bodyStyle,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final strings = scope.strings;
    final controller = widget.controller;
    final preparing = _preparing;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _cancel?.cancel();
        }
      },
      child: Scaffold(
        backgroundColor: theme.background,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: strings.common.back,
                      onPressed: _back,
                      icon: Icon(Icons.arrow_back, color: theme.onSurface),
                    ),
                    Expanded(
                      child: MusicSearchField(
                        controller: _search,
                        onChanged: controller.setSearch,
                        onSubmitted: controller.searchNow,
                        onCleared: () => controller.searchNow(''),
                      ),
                    ),
                    if (widget.current != null)
                      IconButton(
                        tooltip: strings.music.removeMusic,
                        onPressed: _remove,
                        icon: Icon(Icons.music_off, color: theme.onSurface),
                      )
                    else
                      const SizedBox(width: 12),
                  ],
                ),
              ),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => CategoryChips(
                  categories: controller.categories,
                  selected: controller.category,
                  onSelected: controller.selectCategory,
                  onCleared: controller.clearCategory,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: ListenableBuilder(
                  listenable: Listenable.merge([controller, widget.preview]),
                  builder: (context, _) => _TrackListBody(
                    controller: controller,
                    preview: widget.preview,
                    scroll: _scroll,
                    preparingId: preparing?.id,
                    progress: _progress,
                    onScroll: _maybeLoadMore,
                    onPreview: _togglePreview,
                    onUse: _use,
                  ),
                ),
              ),
              if (preparing != null) _PreparingBanner(progress: _progress),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackListBody extends StatelessWidget {
  const _TrackListBody({
    required this.controller,
    required this.preview,
    required this.scroll,
    required this.preparingId,
    required this.progress,
    required this.onScroll,
    required this.onPreview,
    required this.onUse,
  });

  final MusicPickerController controller;
  final MusicPreviewController preview;
  final ScrollController scroll;
  final String? preparingId;
  final ValueListenable<double?> progress;
  final VoidCallback onScroll;
  final ValueChanged<MusicTrack> onPreview;
  final ValueChanged<MusicTrack> onUse;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final strings = scope.strings.music;
    switch (controller.status) {
      case MusicListStatus.loading:
        return Center(child: CircularProgressIndicator(color: theme.accent));
      case MusicListStatus.empty:
        return MusicListMessage(
          message: strings.noResults,
          icon: Icons.search_off,
        );
      case MusicListStatus.error:
        return MusicListMessage(
          message: strings.loadFailed,
          icon: Icons.error_outline,
          onRetry: controller.retry,
        );
      case MusicListStatus.offline:
        return MusicListMessage(
          message: strings.offline,
          icon: Icons.wifi_off,
          onRetry: controller.retry,
        );
      case MusicListStatus.ready:
        break;
    }
    final tracks = controller.tracks;
    final showFooter = controller.hasMore || controller.loadMoreFailed;
    final showBookmark = controller.provider.supportsBookmarks;
    final busy = preparingId != null;
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        onScroll();
        return false;
      },
      child: ListView.builder(
        key: const ValueKey('music-track-list'),
        controller: scroll,
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: tracks.length + (showFooter ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == tracks.length) {
            return _ListFooter(controller: controller);
          }
          final track = tracks[index];
          return TrackTile(
            key: ValueKey('music-track-${track.id}'),
            track: track,
            bookmarked: controller.isBookmarked(track),
            showBookmark: showBookmark,
            previewing: preview.isPlaying(track),
            progress: preparingId == track.id ? progress : null,
            onPreview: () => onPreview(track),
            onBookmark: () => unawaited(controller.toggleBookmark(track)),
            onUse: busy ? null : () => onUse(track),
          );
        },
      ),
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({required this.controller});

  final MusicPickerController controller;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    if (controller.loadMoreFailed) {
      return Center(
        child: TextButton(
          onPressed: controller.retryLoadMore,
          style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
          child: Text(
            scope.strings.common.retry,
            style: theme.labelStyle.copyWith(color: theme.accent),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: theme.accent,
          ),
        ),
      ),
    );
  }
}

class _PreparingBanner extends StatelessWidget {
  const _PreparingBanner({required this.progress});

  final ValueListenable<double?> progress;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    return ColoredBox(
      color: theme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(scope.strings.music.downloading, style: theme.captionStyle),
              const SizedBox(height: 8),
              ValueListenableBuilder<double?>(
                valueListenable: progress,
                builder: (context, value, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 4,
                    color: theme.accent,
                    backgroundColor: theme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
