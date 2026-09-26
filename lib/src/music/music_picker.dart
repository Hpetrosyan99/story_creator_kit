import 'dart:async';

import 'package:flutter/material.dart';

import '../api/errors/story_exception.dart';
import '../core/story_scope.dart';
import '../model/music_selection.dart';
import 'music_file_cache.dart';
import 'music_picker_controller.dart';
import 'music_picker_screen.dart';
import 'music_preview_controller.dart';
import 'music_track_preparer.dart';
import 'segment_selector.dart';

/// Opens the music picker and segment selector.
///
/// [segmentLength] is the length the music must cover (trimmed video length,
/// or the photo-with-music duration). Completes with the new selection
/// (with `localPath` resolved, ready for export), the unchanged [current]
/// when the user backs out, or `null` when the user removes the music.
///
/// The picker is a full-screen list; tapping a row picks the track (a long
/// press previews it). The segment selector then opens on a stage like the
/// editor's, showing [canvas] (the story, dimmed) in its card; without
/// [canvas] the card is plain. Returns [current] at once when the
/// configuration has no music provider.

Future<MusicSelection?> showMusicPicker(
  BuildContext context, {
  required Duration segmentLength,
  MusicSelection? current,
  WidgetBuilder? canvas,
}) => openMusicPicker(
  context,
  segmentLength: segmentLength,
  current: current,
  canvas: canvas,
);

/// [showMusicPicker] with replaceable internals, for tests.
///
/// [cache] defaults to the story session's shared [MusicFileCache];
/// [searchDebounce] is the delay before a search request.
Future<MusicSelection?> openMusicPicker(
  BuildContext context, {
  required Duration segmentLength,
  MusicSelection? current,
  WidgetBuilder? canvas,
  MusicFileCache? cache,
  Duration searchDebounce = kMusicSearchDebounce,
}) async {
  final scope = StoryScope.read(context);
  final provider = scope.config.musicProvider;
  if (provider == null) {
    return current;
  }
  final navigator = Navigator.of(context);
  final materialTheme = Theme.of(context);
  final session = scope.services.createMusicSession();
  final controller = MusicPickerController(
    provider: provider,
    searchDebounce: searchDebounce,
    onError: (error, stackTrace) => scope.reportError(
      error is StoryException
          ? error
          : StoryException(
              StoryErrorCode.musicUnavailable,
              'A music catalog request failed.',
              error,
              stackTrace,
            ),
    ),
  );
  final preview = MusicPreviewController(provider: provider, session: session);
  final preparer = MusicTrackPreparer(
    provider: provider,
    cache: cache ?? MusicFileCache.forSession(scope.session),
    session: session,
    inspector: scope.services.inspector,
    onNonFatalError: scope.reportError,
  );
  unawaited(controller.start());
  try {
    while (true) {
      final outcome = await navigator.push(
        _pickerRoute(
          scope: scope,
          materialTheme: materialTheme,
          child: MusicPickerScreen(
            controller: controller,
            preview: preview,
            preparer: preparer,
            current: current,
          ),
        ),
      );
      switch (outcome) {
        case null:
          return current;
        case MusicPickerRemoved():
          return null;
        case MusicPickerChose(:final prepared):
          final selection = await navigator.push(
            _segmentRoute(
              scope: scope,
              materialTheme: materialTheme,
              child: MusicSegmentSelector(
                prepared: prepared,
                segmentLength: segmentLength,
                session: session,
                initialStart:
                    current != null && current.track.id == prepared.track.id
                    ? current.start
                    : Duration.zero,
                volume: current?.volume ?? 1,
                canvas: canvas,
              ),
            ),
          );
          if (selection != null) {
            return selection;
          }
          await session.stop();
      }
    }
  } finally {
    preview.dispose();
    controller.dispose();
    await session.dispose();
  }
}

Route<MusicPickerOutcome> _pickerRoute({
  required StoryScope scope,
  required ThemeData materialTheme,
  required Widget child,
}) => PageRouteBuilder<MusicPickerOutcome>(
  pageBuilder: (context, _, _) =>
      MusicRouteShell(scope: scope, materialTheme: materialTheme, child: child),
  transitionsBuilder: (context, animation, _, child) => SlideTransition(
    position: Tween(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation),
    child: child,
  ),
);

Route<MusicSelection> _segmentRoute({
  required StoryScope scope,
  required ThemeData materialTheme,
  required Widget child,
}) => PageRouteBuilder<MusicSelection>(
  pageBuilder: (context, _, _) =>
      MusicRouteShell(scope: scope, materialTheme: materialTheme, child: child),
  transitionsBuilder: (context, animation, _, child) => FadeTransition(
    opacity: CurveTween(curve: Curves.easeOut).animate(animation),
    child: child,
  ),
);

/// Re-creates, inside a route pushed from the story creator, what the story
/// creator page provides: the [StoryScope], the Material theme, default text
/// and icon styles and a [ScaffoldMessenger] for snack bars.
class MusicRouteShell extends StatelessWidget {
  /// Creates the shell.
  const MusicRouteShell({
    required this.scope,
    required this.materialTheme,
    required this.child,
    super.key,
  });

  /// The story creator's scope, captured before pushing.
  final StoryScope scope;

  /// The story creator's Material theme, captured before pushing.
  final ThemeData materialTheme;

  /// Route content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = scope.theme;
    return StoryScope(
      config: scope.config,
      services: scope.services,
      session: scope.session,
      resources: scope.resources,
      child: Theme(
        data: materialTheme,
        child: DefaultTextStyle(
          style: theme.bodyStyle,
          child: IconTheme(
            data: IconThemeData(color: theme.onSurface, size: 26),
            child: ScaffoldMessenger(child: child),
          ),
        ),
      ),
    );
  }
}
