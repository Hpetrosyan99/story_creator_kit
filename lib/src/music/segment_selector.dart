import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/errors/story_exception.dart';
import '../core/story_scope.dart';
import '../model/music_selection.dart';
import '../services/audio/music_session.dart';
import '../ui/story_icon.dart';
import '../ui/story_nav_button.dart';
import '../ui/story_stage.dart';
import 'music_track_preparer.dart';
import 'segment_math.dart';
import 'waveform_painter.dart';

/// Picks which part of a prepared track plays.
///
/// Laid out like the editor: a [StoryStage] whose card shows the story
/// ([canvas]) dimmed by the theme's scrim, a close button (back to the list)
/// and a confirm button, and the waveform strip near the bottom of the card.
/// The fixed accent window in the middle of the strip is the segment; the
/// waveform is dragged under it to move the start, and the window fills with
/// accent as the looped segment plays. Confirm pops with a
/// [MusicSelection]; close pops with `null`.
class MusicSegmentSelector extends StatefulWidget {
  /// Creates the selector. [session] must have [prepared]'s file loaded.
  const MusicSegmentSelector({
    required this.prepared,
    required this.segmentLength,
    required this.session,
    this.initialStart = Duration.zero,
    this.volume = 1,
    this.canvas,
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

  /// Builds the story shown in the card; `null` shows the surface colour.
  final WidgetBuilder? canvas;

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
    final canvas = widget.canvas;
    return Scaffold(
      backgroundColor: theme.background,
      body: StoryStage(
        card: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              child: IgnorePointer(
                child: canvas == null
                    ? ColoredBox(color: theme.surface)
                    : canvas(context),
              ),
            ),
            IgnorePointer(child: ColoredBox(color: theme.scrim)),
            Positioned(
              // The 44 px buttons sit in 48 px tap targets: 12 / 16 insets.
              top: 10,
              left: 14,
              right: 14,
              child: Row(
                children: [
                  StoryNavButton(
                    key: const ValueKey('music-segment-close'),
                    icon: StoryIcons.close,
                    label: strings.common.close,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  StoryNavButton(
                    key: const ValueKey('music-segment-done'),
                    icon: StoryIcons.check,
                    label: strings.common.done,
                    style: StoryNavButtonStyle.subtle,
                    onPressed: _done,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              // Centre of the strip 30 px above the card bottom.
              bottom: 30 - MusicWaveformStrip.touchHeight / 2,
              child: Semantics(
                container: true,
                label: strings.music.trackLabel(track.title, track.artist),
                child: MusicWaveformStrip(
                  peaks: widget.prepared.peaks,
                  segment: _segment,
                  trackDuration: _trackDuration,
                  position: widget.session.position,
                  onChanged: _moveTo,
                  onMoveBy: (delta) => _moveTo(_segment.start + delta),
                  onChangeEnd: _commit,
                  clamp: _clamp,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The waveform strip with the fixed segment window in its middle.
///
/// The window is [windowWidth] wide and stands for the segment; the whole
/// track is drawn at that scale and scrolls under it, so dragging left moves
/// the start later. The window's accent fill grows from its left edge to the
/// playback [position]. Accessible as a slider: increase / decrease move the
/// start by [step].
class MusicWaveformStrip extends StatelessWidget {
  /// Creates the strip.
  const MusicWaveformStrip({
    required this.peaks,
    required this.segment,
    required this.trackDuration,
    required this.position,
    required this.onChanged,
    required this.onMoveBy,
    required this.onChangeEnd,
    required this.clamp,
    this.step = const Duration(seconds: 1),
    this.windowWidth = 120,
    super.key,
  });

  /// Waveform peaks.
  final List<double> peaks;

  /// The selected segment.
  final MusicSegment segment;

  /// Track length.
  final Duration trackDuration;

  /// Playback position within the track.
  final ValueListenable<Duration> position;

  /// Called with a requested start (semantic action).
  final ValueChanged<Duration> onChanged;

  /// Called with the time the waveform was dragged by.
  final ValueChanged<Duration> onMoveBy;

  /// Called when a drag or semantic action ends.
  final VoidCallback onChangeEnd;

  /// Clamps a requested start into a valid segment.
  final MusicSegment Function(Duration start) clamp;

  /// Semantic increase / decrease step.
  final Duration step;

  /// Width of the segment window (the design's 120 px).
  final double windowWidth;

  /// Height of the window pill.
  static const double windowHeight = 41;

  /// Height of the draggable area.
  static const double touchHeight = 56;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final increased = clamp(segment.start + step);
    final decreased = clamp(segment.start - step);
    return Semantics(
      container: true,
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
            final window = math
                .max(0, math.min(windowWidth, width - 32))
                .toDouble();
            final windowLeft = (width - window) / 2;
            final segmentMicros = segment.duration.inMicroseconds;
            // Pixels per microsecond of the track.
            final scale = segmentMicros <= 0 ? 0.0 : window / segmentMicros;
            final trackWidth = trackDuration <= Duration.zero
                ? window
                : trackDuration.inMicroseconds * scale;
            final originX = windowLeft - segment.start.inMicroseconds * scale;
            final radius = BorderRadius.circular(windowHeight / 2);
            return GestureDetector(
              key: const ValueKey('music-waveform-strip'),
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) {
                if (scale > 0) {
                  onMoveBy(
                    Duration(microseconds: (-details.delta.dx / scale).round()),
                  );
                }
              },
              onHorizontalDragEnd: (_) => onChangeEnd(),
              child: SizedBox(
                height: touchHeight,
                width: width,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Positioned(
                      key: const ValueKey('music-segment-window'),
                      left: windowLeft,
                      width: window,
                      height: windowHeight,
                      child: ClipRRect(
                        borderRadius: radius,
                        child: ValueListenableBuilder<Duration>(
                          valueListenable: position,
                          builder: (context, value, _) => Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              key: const ValueKey('music-segment-fill'),
                              widthFactor: _playedFraction(value),
                              heightFactor: 1,
                              child: ColoredBox(color: theme.accent),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: MusicWaveformPainter(
                            peaks: peaks,
                            originX: originX,
                            trackWidth: trackWidth,
                            color: theme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: windowLeft,
                      width: window,
                      height: windowHeight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          border: Border.all(color: theme.accent),
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

  /// How much of the segment has played at [value], 0–1.
  double _playedFraction(Duration value) {
    final length = segment.duration.inMicroseconds;
    if (length <= 0) {
      return 0;
    }
    final played = (value - segment.start).inMicroseconds / length;
    return played.clamp(0.0, 1.0);
  }
}
