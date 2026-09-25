import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../core/story_canvas.dart';
import '../../model/drawing_stroke.dart';
import '../../render/painters/story_edits_painter.dart';
import '../../render/painters/stroke_renderer.dart';
import '../drawing/drawing_brush.dart';

/// The stroke layer: finished strokes replayed from a cached [ui.Picture]
/// recorded with the shared painter, plus the stroke being drawn.
///
/// When [enabled], the first pointer draws a stroke with [brush] and
/// [onStroke] receives it on release.
class DrawingLayer extends StatefulWidget {
  /// Creates the layer.
  const DrawingLayer({
    required this.strokes,
    required this.viewScale,
    required this.brush,
    required this.enabled,
    required this.onStroke,
    super.key,
  });

  /// Finished strokes.
  final List<DrawingStroke> strokes;

  /// Screen pixels per canvas unit.
  final double viewScale;

  /// Brush for new strokes.
  final DrawingBrush brush;

  /// Whether pointer input draws.
  final bool enabled;

  /// A stroke was finished.
  final ValueChanged<DrawingStroke> onStroke;

  /// Minimum distance between recorded points, canvas units.
  static const double minPointDistance = 1.5;

  @override
  State<DrawingLayer> createState() => _DrawingLayerState();
}

class _DrawingLayerState extends State<DrawingLayer> {
  final ValueNotifier<DrawingStroke?> _live = ValueNotifier(null);
  final List<StrokePoint> _points = [];
  int? _pointer;
  ui.Picture? _committed;
  List<DrawingStroke>? _committedFor;

  @override
  void dispose() {
    _committed?.dispose();
    _live.dispose();
    super.dispose();
  }

  ui.Picture? _picture() {
    if (identical(_committedFor, widget.strokes)) {
      return _committed;
    }
    _committed?.dispose();
    _committedFor = widget.strokes;
    if (widget.strokes.isEmpty) {
      return _committed = null;
    }
    final recorder = ui.PictureRecorder();
    StoryEditsPainter.paintStrokes(
      Canvas(recorder, StoryCanvas.bounds),
      widget.strokes,
    );
    return _committed = recorder.endRecording();
  }

  StrokePoint _point(PointerEvent event) {
    final p = event.localPosition / widget.viewScale;
    final range = event.pressureMax - event.pressureMin;
    final pressure = event.kind == PointerDeviceKind.stylus && range > 0
        ? ((event.pressure - event.pressureMin) / range).clamp(0.0, 1.0)
        : 0.5;
    return StrokePoint(p.dx, p.dy, pressure);
  }

  DrawingStroke _stroke() => DrawingStroke(
    points: List.unmodifiable(_points),
    color: widget.brush.color,
    size: widget.brush.size,
    tool: widget.brush.tool,
  );

  void _onDown(PointerDownEvent event) {
    if (_pointer != null) {
      return;
    }
    _pointer = event.pointer;
    _points
      ..clear()
      ..add(_point(event));
    _live.value = _stroke();
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    final point = _point(event);
    final last = _points.last;
    final dx = point.x - last.x;
    final dy = point.y - last.y;
    const min = DrawingLayer.minPointDistance;
    if (dx * dx + dy * dy < min * min) {
      return;
    }
    _points.add(point);
    _live.value = _stroke();
  }

  void _onUp(PointerUpEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    final stroke = _stroke();
    _pointer = null;
    _points.clear();
    _live.value = null;
    widget.onStroke(stroke);
  }

  void _onCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    _points.clear();
    _live.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final paint = RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _StrokesPainter(
          picture: _picture(),
          live: _live,
          scale: widget.viewScale,
        ),
      ),
    );
    if (!widget.enabled) {
      return IgnorePointer(child: paint);
    }
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: paint,
    );
  }
}

class _StrokesPainter extends CustomPainter {
  _StrokesPainter({
    required this.picture,
    required this.live,
    required this.scale,
  }) : super(repaint: live);

  final ui.Picture? picture;
  final ValueNotifier<DrawingStroke?> live;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final current = live.value;
    if (picture == null && current == null) {
      return;
    }
    canvas
      ..clipRect(Offset.zero & size)
      ..scale(scale);
    final erasing = current?.tool == StrokeTool.eraser;
    if (erasing) {
      canvas.saveLayer(StoryCanvas.bounds, Paint());
    }
    if (picture != null) {
      canvas.drawPicture(picture!);
    }
    if (current != null) {
      StrokeRenderer.paintStroke(canvas, current);
    }
    if (erasing) {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_StrokesPainter oldDelegate) =>
      !identical(oldDelegate.picture, picture) || oldDelegate.scale != scale;
}
