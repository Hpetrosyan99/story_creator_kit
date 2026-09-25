import 'dart:async';

import 'package:flutter/material.dart';

import '../api/errors/story_exception.dart';
import '../core/story_scope.dart';
import '../model/music_selection.dart';
import '../services/audio/music_session.dart';
import 'music_track_preparer.dart';
import 'segment_math.dart';
import 'waveform_painter.dart';

/// Bottom panel that picks which part of a prepared track plays.
///
/// Shown in a non-opaque route so the story canvas stays visible above it.
/// The accent window over the waveform covers `segmentLength / duration` of
/// the strip and is dragged horizontally to move the start; the chosen segment
/// loops and restarts when a drag ends. Done pops with a [MusicSelection];
/// back pops with `null`.
class MusicSegmentSelector extends StatefulWidget {
  /// Creates the selector. [session] must have [prepared]'s file loaded.
  const MusicSegmentSelector({
    required this.prepared,
    required this.segmentLength,
    required this.session,
    this.initialStart = Duration.zero,
    this.volume = 1,
    super.key,
  });

  /// The picked track.
  final PreparedMusicTrack prepared;

  /// Length the music must cover.
  final Duration segmentLength;

  /// The player, loaded with the track's local file.
  final MusicSession session;

  /// Start of the window when the selector opens.
  final Duration initialStart;

  /// Volume carried into the selection.
  final double volume;

  @override
  State<MusicSegmentSelector> createState() => _MusicSegmentSelectorState();
}

class _MusicSegmentSelectorState extends State<MusicSegmentSelector> {
  late MusicSegment _segment = _clamp(widget.initialStart);

  Duration get _trackDuration => widget.prepared.duration;

  MusicSegment _clamp(Duration start) => clampMusicSegment(
    start: start,
    segmentLength: widget.segmentLength,
    trackDuration: _trackDuration,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_play());
  }

  Future<void> _play() async {
    try {
      await widget.session.playSegment(_segment.start, _segment.duration);
    } on StoryException catch (e) {
      if (!mounted) {
        return;
      }
      final scope = StoryScope.read(context)..reportError(e);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: scope.theme.surfaceVariant,
            content: Text(
              scope.strings.music.trackUnavailable,
              style: scope.theme.bodyStyle,
            ),
          ),
        );
    }
  }

  void _moveTo(Duration start) {
    final next = _clamp(start);
    if (next != _segment) {
      setState(() => _segment = next);
    }
  }

  void _commit() => unawaited(_play());

  void _done() => Navigator.of(context).pop(
    MusicSelection(
      track: widget.prepared.track,
      start: _segment.start,
      duration: _segment.duration,
      localPath: widget.prepared.localPath,
      volume: widget.volume,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final strings = scope.strings;
    final track = widget.prepared.track;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.35, 1],
                    colors: [theme.scrim.withValues(alpha: 0), theme.scrim],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(theme.cornerRadius),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: strings.common.back,
                            onPressed: () => Navigator.of(context).pop(),
                            icon: Icon(
                              Icons.arrow_back,
                              color: theme.onSurface,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              strings.music.chooseSegment,
                              textAlign: TextAlign.center,
                              style: theme.titleStyle,
                            ),
                          ),
                          IconButton(
                            tooltip: strings.common.done,
                            onPressed: _done,
                            style: IconButton.styleFrom(
                              backgroundColor: theme.accent,
                              foregroundColor: theme.onAccent,
                            ),
                            icon: Icon(Icons.check, color: theme.onAccent),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodyStyle,
                      ),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.captionStyle,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        formatMusicTime(_segment.start),
                        style: theme.labelStyle,
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: MusicWaveformStrip(
                          peaks: widget.prepared.peaks,
                          segment: _segment,
                          trackDuration: _trackDuration,
                          onChanged: _moveTo,
                          onMoveBy: (delta) => _moveTo(_segment.start + delta),
                          onChangeEnd: _commit,
                          clamp: _clamp,
                        ),
                      ),
                    ],
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

/// The waveform with the draggable accent window.
///
/// Accessible as a slider: increase / decrease move the start by [step].
class MusicWaveformStrip extends StatelessWidget {
  /// Creates the strip.
  const MusicWaveformStrip({
    required this.peaks,
    required this.segment,
    required this.trackDuration,
    required this.onChanged,
    required this.onMoveBy,
    required this.onChangeEnd,
    required this.clamp,
    this.step = const Duration(seconds: 1),
    this.height = 64,
    super.key,
  });

  /// Waveform peaks.
  final List<double> peaks;

  /// The selected segment.
  final MusicSegment segment;

  /// Track length.
  final Duration trackDuration;

  /// Called with a requested start (tap, semantic action).
  final ValueChanged<Duration> onChanged;

  /// Called with the time the window was dragged by.
  final ValueChanged<Duration> onMoveBy;

  /// Called when a drag, tap or semantic action ends.
  final VoidCallback onChangeEnd;

  /// Clamps a requested start into a valid segment.
  final MusicSegment Function(Duration start) clamp;

  /// Semantic increase / decrease step.
  final Duration step;

  /// Strip height.
  final double height;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final startFraction = musicFractionOf(segment.start, trackDuration);
    final endFraction = trackDuration <= Duration.zero
        ? 1.0
        : musicFractionOf(segment.end, trackDuration);
    final increased = clamp(segment.start + step);
    final decreased = clamp(segment.start - step);
    return Semantics(
      slider: true,
      label: scope.strings.music.chooseSegment,
      value: formatMusicTime(segment.start),
      increasedValue: formatMusicTime(increased.start),
      decreasedValue: formatMusicTime(decreased.start),
      onIncrease: () {
        onChanged(increased.start);
        onChangeEnd();
      },
      onDecrease: () {
        onChanged(decreased.start);
        onChangeEnd();
      },
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final windowLeft = width * startFraction;
            final windowWidth = width * (endFraction - startFraction);
            Duration deltaOf(double dx) => width <= 0
                ? Duration.zero
                : musicPositionAt(dx.abs() / width, trackDuration) * dx.sign;
            return GestureDetector(
              key: const ValueKey('music-waveform-strip'),
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) =>
                  onMoveBy(deltaOf(details.delta.dx)),
              onHorizontalDragEnd: (_) => onChangeEnd(),
              onTapUp: (details) {
                final centre = details.localPosition.dx - windowWidth / 2;
                onChanged(
                  musicPositionAt(
                    width <= 0 ? 0 : centre / width,
                    trackDuration,
                  ),
                );
                onChangeEnd();
              },
              child: SizedBox(
                height: height,
                width: width,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: MusicWaveformPainter(
                          peaks: peaks,
                          windowStart: startFraction,
                          windowEnd: endFraction,
                          activeColor: theme.accent,
                          inactiveColor: theme.onSurfaceMuted,
                        ),
                      ),
                    ),
                    Positioned(
                      key: const ValueKey('music-segment-window'),
                      left: windowLeft,
                      width: windowWidth,
                      top: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(theme.chipRadius),
                          border: Border.all(color: theme.accent, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
