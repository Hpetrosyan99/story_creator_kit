import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/story_scope.dart';
import '../../model/trim_range.dart';
import '../../services/video/video_session.dart';
import '../widgets/editor_panel.dart';

/// Video trimmer: a strip of frames, two handles bounding the kept part
/// (between the minimum and maximum story length) and a playhead.
class TrimBar extends StatefulWidget {
  /// Creates the trimmer.
  const TrimBar({
    required this.total,
    required this.range,
    required this.minDuration,
    required this.maxDuration,
    required this.thumbnails,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
    this.playback,
    super.key,
  });

  /// Length of the source video.
  final Duration total;

  /// Current kept range.
  final TrimRange range;

  /// Shortest allowed range.
  final Duration minDuration;

  /// Longest allowed range.
  final Duration maxDuration;

  /// Frame images spread evenly over the video.
  final Future<List<String>> thumbnails;

  /// Player state for the playhead.
  final ValueListenable<VideoPlaybackState>? playback;

  /// A handle drag (or accessibility step) starts.
  final VoidCallback onChangeStart;

  /// The range changed; [position] is the time under the moved handle.
  final void Function(TrimRange range, Duration position) onChanged;

  /// The change ended.
  final VoidCallback onChangeEnd;

  /// Width of the touch area of a handle.
  static const double handleTouchWidth = 48;

  /// Accessibility step of a handle.
  static const Duration step = Duration(milliseconds: 500);

  /// Clamps a new start so that `end - start` stays within [min]…[max].
  static Duration clampStart(
    Duration start,
    Duration end, {
    required Duration min,
    required Duration max,
  }) {
    final lower = end - max > Duration.zero ? end - max : Duration.zero;
    final upper = end - min;
    return _clamp(start, lower, upper);
  }

  /// Clamps a new end so that `end - start` stays within [min]…[max] and
  /// the end within [total].
  static Duration clampEnd(
    Duration start,
    Duration end, {
    required Duration total,
    required Duration min,
    required Duration max,
  }) {
    final lower = start + min;
    final upper = start + max < total ? start + max : total;
    return _clamp(end, lower, upper);
  }

  static Duration _clamp(Duration value, Duration lower, Duration upper) {
    if (upper < lower) {
      return lower;
    }
    if (value < lower) {
      return lower;
    }
    if (value > upper) {
      return upper;
    }
    return value;
  }

  /// `m:ss.d`.
  static String format(Duration d) {
    final tenths = (d.inMilliseconds / 100).round();
    final minutes = tenths ~/ 600;
    final seconds = (tenths % 600) ~/ 10;
    final fraction = tenths % 10;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.$fraction';
  }

  @override
  State<TrimBar> createState() => _TrimBarState();
}

class _TrimBarState extends State<TrimBar> {
  Duration _dragOrigin = Duration.zero;
  double _dragStartX = 0;

  Duration _at(double dx, double width) => Duration(
    microseconds: (widget.total.inMicroseconds * (dx / width)).round(),
  );

  void _moveStart(Duration start) {
    final clamped = TrimBar.clampStart(
      start,
      widget.range.end,
      min: widget.minDuration,
      max: widget.maxDuration,
    );
    widget.onChanged(TrimRange(clamped, widget.range.end), clamped);
  }

  void _moveEnd(Duration end) {
    final clamped = TrimBar.clampEnd(
      widget.range.start,
      end,
      total: widget.total,
      min: widget.minDuration,
      max: widget.maxDuration,
    );
    widget.onChanged(TrimRange(widget.range.start, clamped), clamped);
  }

  void _step(VoidCallback change) {
    widget.onChangeStart();
    change();
    widget.onChangeEnd();
  }

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final strings = scope.strings.editor;
    final range = widget.range;
    return EditorPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: strings.trimLength,
            value: TrimBar.format(range.duration),
            excludeSemantics: true,
            child: Text(
              TrimBar.format(range.duration),
              style: theme.labelStyle,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const pad = TrimBar.handleTouchWidth / 2;
                final width = math.max<double>(
                  1,
                  constraints.maxWidth - 2 * pad,
                );
                final total = widget.total.inMicroseconds == 0
                    ? 1
                    : widget.total.inMicroseconds;
                double x(Duration d) => pad + width * d.inMicroseconds / total;
                final startX = x(range.start);
                final endX = x(range.end);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: pad,
                      width: width,
                      top: 4,
                      bottom: 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          theme.cornerRadius / 2,
                        ),
                        child: _ThumbnailStrip(thumbnails: widget.thumbnails),
                      ),
                    ),
                    Positioned(
                      left: pad,
                      width: startX - pad,
                      top: 4,
                      bottom: 4,
                      child: ColoredBox(color: theme.scrim),
                    ),
                    Positioned(
                      left: endX,
                      right: pad,
                      top: 4,
                      bottom: 4,
                      child: ColoredBox(color: theme.scrim),
                    ),
                    Positioned(
                      left: startX,
                      width: math.max<double>(0, endX - startX),
                      top: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.accent, width: 3),
                            borderRadius: BorderRadius.circular(
                              theme.cornerRadius / 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (widget.playback != null)
                      ValueListenableBuilder<VideoPlaybackState>(
                        valueListenable: widget.playback!,
                        builder: (context, state, _) => Positioned(
                          left: x(state.position) - 1,
                          width: 2,
                          top: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: ColoredBox(color: theme.onSurface),
                          ),
                        ),
                      ),
                    _Handle(
                      key: const ValueKey('trimStart'),
                      centerX: startX,
                      label: strings.trimStart,
                      value: range.start,
                      color: theme.accent,
                      onDragStart: (dx) {
                        _dragOrigin = range.start;
                        _dragStartX = dx;
                        widget.onChangeStart();
                      },
                      onDragUpdate: (dx) => _moveStart(
                        _dragOrigin + _at(dx - _dragStartX, width),
                      ),
                      onDragEnd: widget.onChangeEnd,
                      onIncrease: () =>
                          _step(() => _moveStart(range.start + TrimBar.step)),
                      onDecrease: () =>
                          _step(() => _moveStart(range.start - TrimBar.step)),
                    ),
                    _Handle(
                      key: const ValueKey('trimEnd'),
                      centerX: endX,
                      label: strings.trimEnd,
                      value: range.end,
                      color: theme.accent,
                      onDragStart: (dx) {
                        _dragOrigin = range.end;
                        _dragStartX = dx;
                        widget.onChangeStart();
                      },
                      onDragUpdate: (dx) =>
                          _moveEnd(_dragOrigin + _at(dx - _dragStartX, width)),
                      onDragEnd: widget.onChangeEnd,
                      onIncrease: () =>
                          _step(() => _moveEnd(range.end + TrimBar.step)),
                      onDecrease: () =>
                          _step(() => _moveEnd(range.end - TrimBar.step)),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle({
    required this.centerX,
    required this.label,
    required this.value,
    required this.color,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onIncrease,
    required this.onDecrease,
    super.key,
  });

  final double centerX;
  final String label;
  final Duration value;
  final Color color;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;

  @override
  Widget build(BuildContext context) => Positioned(
    left: centerX - TrimBar.handleTouchWidth / 2,
    width: TrimBar.handleTouchWidth,
    top: 0,
    bottom: 0,
    child: Semantics(
      slider: true,
      label: label,
      value: TrimBar.format(value),
      increasedValue: TrimBar.format(value + TrimBar.step),
      decreasedValue: TrimBar.format(
        value > TrimBar.step ? value - TrimBar.step : Duration.zero,
      ),
      onIncrease: onIncrease,
      onDecrease: onDecrease,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) => onDragStart(d.globalPosition.dx),
        onHorizontalDragUpdate: (d) => onDragUpdate(d.globalPosition.dx),
        onHorizontalDragEnd: (_) => onDragEnd(),
        onHorizontalDragCancel: onDragEnd,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const SizedBox(width: 10, height: 64),
          ),
        ),
      ),
    ),
  );
}

class _ThumbnailStrip extends StatelessWidget {
  const _ThumbnailStrip({required this.thumbnails});

  final Future<List<String>> thumbnails;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    return ColoredBox(
      color: theme.surfaceVariant,
      child: FutureBuilder<List<String>>(
        future: thumbnails,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: theme.onSurfaceMuted,
              ),
            );
          }
          final paths = snapshot.data;
          if (paths == null || paths.isEmpty) {
            return const SizedBox.expand();
          }
          return Row(
            children: [
              for (final path in paths)
                Expanded(
                  child: Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    height: double.infinity,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.expand(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
