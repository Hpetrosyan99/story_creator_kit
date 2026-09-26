import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/errors/story_exception.dart';
import '../api/music/music_models.dart';
import '../core/story_scope.dart';
import '../model/music_selection.dart';
import '../ui/story_icon.dart';
import 'music_file_cache.dart';
import 'music_picker_controller.dart';
import 'music_preview_controller.dart';
import 'music_track_preparer.dart';
import 'widgets/category_chips.dart';
import 'widgets/music_list_message.dart';
import 'widgets/music_list_skeleton.dart';
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

/// Full-screen music list: back chevron, search, category chips and the
/// paged track list.
///
/// Tapping a row prepares the track (download, waveform) and pops with it so
/// the segment selector opens; a long press previews it.
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

  void _resetFilters() {
    _search.clear();
    widget.controller.resetFilters();
  }

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
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
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NavBar(
                onBack: _back,
                onRemove: widget.current != null ? _remove : null,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: MusicSearchField(
                  controller: _search,
                  onChanged: controller.setSearch,
                  onSubmitted: controller.searchNow,
                  onCleared: () => controller.searchNow(''),
                ),
              ),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => CategoryChips(
                  categories: controller.categories,
                  selected: controller.category,
                  onSelected: controller.selectCategory,
                  onCleared: _resetFilters,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListenableBuilder(
                  listenable: Listenable.merge([controller, widget.preview]),
                  builder: (context, _) => _TrackListBody(
                    controller: controller,
                    preview: widget.preview,
                    scroll: _scroll,
                    preparingId: preparing?.id,
                    selectedId: widget.current?.track.id,
                    progress: _progress,
                    onScroll: _maybeLoadMore,
                    onPreview: _togglePreview,
                    onUse: _use,
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

/// Back chevron at the left; "Remove music" at the right when the story has
/// music. 48 px high, no title.
class _NavBar extends StatelessWidget {
  const _NavBar({required this.onBack, required this.onRemove});

  final VoidCallback onBack;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final strings = scope.strings;
    final onRemove = this.onRemove;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 4),
          Semantics(
            button: true,
            label: strings.common.back,
            excludeSemantics: true,
            onTap: onBack,
            child: GestureDetector(
              key: const ValueKey('music-back'),
              behavior: HitTestBehavior.opaque,
              onTap: onBack,
              child: SizedBox.square(
                dimension: 48,
                child: Center(
                  child: StoryIcon(
                    StoryIcons.chevronLeft,
                    color: theme.onSurface,
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          if (onRemove != null)
            Semantics(
              button: true,
              label: strings.music.removeMusic,
              excludeSemantics: true,
              onTap: onRemove,
              child: GestureDetector(
                key: const ValueKey('music-remove'),
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        strings.music.removeMusic,
                        style: theme.labelStyle.copyWith(
                          color: theme.onSurfaceSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
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
    required this.selectedId,
    required this.progress,
    required this.onScroll,
    required this.onPreview,
    required this.onUse,
  });

  final MusicPickerController controller;
  final MusicPreviewController preview;
  final ScrollController scroll;
  final String? preparingId;
  final String? selectedId;
  final ValueListenable<double?> progress;
  final VoidCallback onScroll;
  final ValueChanged<MusicTrack> onPreview;
  final ValueChanged<MusicTrack> onUse;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final strings = scope.strings.music;
    switch (controller.status) {
      case MusicListStatus.loading:
        return const MusicListSkeleton();
      case MusicListStatus.empty:
        return MusicListMessage(message: strings.noResults);
      case MusicListStatus.error:
        return MusicListMessage(
          message: strings.loadFailed,
          onRetry: controller.retry,
        );
      case MusicListStatus.offline:
        return MusicListMessage(
          message: strings.offline,
          onRetry: controller.retry,
        );
      case MusicListStatus.ready:
        break;
    }
    final tracks = controller.tracks;
    final showFooter = controller.hasMore || controller.loadMoreFailed;
    final showBookmark = controller.provider.supportsBookmarks;
    final ranked = controller.category.showRanks;
    final busy = preparingId != null;
    // One highlighted row: the one previewing, else the one being prepared,
    // else the story's current track.
    final highlightedId = preview.playingId ?? preparingId ?? selectedId;
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        onScroll();
        return false;
      },
      child: ListView.builder(
        key: const ValueKey('music-track-list'),
        controller: scroll,
        padding: EdgeInsets.only(
          bottom: 16 + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: tracks.length + (showFooter ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == tracks.length) {
            return _ListFooter(controller: controller);
          }
          final track = tracks[index];
          return TrackTile(
            key: ValueKey('music-track-${track.id}'),
            track: track,
            rank: ranked ? index + 1 : null,
            bookmarked: controller.isBookmarked(track),
            showBookmark: showBookmark,
            highlighted: track.id == highlightedId,
            playing: preview.isPlaying(track),
            previewing: preview.isPlaying(track),
            progress: preparingId == track.id ? progress : null,
            onSelect: busy ? null : () => onUse(track),
            onPreview: busy ? null : () => onPreview(track),
            onBookmark: () => unawaited(controller.toggleBookmark(track)),
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
    final theme = StoryScope.of(context).theme;
    if (controller.loadMoreFailed) {
      return Center(child: MusicRetryPill(onPressed: controller.retryLoadMore));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox.square(
          key: const ValueKey('music-load-more'),
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: theme.accent),
        ),
      ),
    );
  }
}
