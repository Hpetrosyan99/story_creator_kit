import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/story_canvas.dart';
import '../../model/media_placement.dart';
import '../../model/overlay_transform.dart';
import '../../model/story_overlay.dart';
import '../../render/painters/story_paint_resources.dart';
import '../editor_controller.dart';
import 'canvas_interaction.dart';
import 'overlay_geometry.dart';
import 'trash_zone.dart';

/// One scale gesture over the whole canvas with its own hit testing.
///
/// - Starting on an overlay moves, pinch-scales and rotates it (the second
///   finger may land anywhere), brings it to the front and shows the trash
///   zone; releasing over the trash deletes it.
/// - Starting elsewhere: two fingers move and scale the media; a one-finger
///   horizontal swipe switches the filter.
/// - Taps are reported through [onTap] with the overlay under the finger.
///
/// The recognizer restarts whenever a finger is added or lifted, so the
/// start transform is snapshotted on every start and deltas are applied to
/// it (never accumulated per update).
class CanvasGestureLayer extends StatefulWidget {
  /// Creates the layer.
  const CanvasGestureLayer({
    required this.controller,
    required this.interaction,
    required this.resources,
    required this.viewScale,
    required this.onTap,
    required this.onFilterSwipe,
    super.key,
  });

  /// Editor state.
  final EditorController controller;

  /// Drag feedback.
  final CanvasInteraction interaction;

  /// Fonts and stickers for overlay sizes.
  final StoryPaintResources resources;

  /// Screen pixels per canvas unit.
  final double viewScale;

  /// A tap; the overlay under it, or `null` for empty canvas.
  final ValueChanged<StoryOverlay?> onTap;

  /// A horizontal swipe on the media: +1 next filter, -1 previous.
  final ValueChanged<int> onFilterSwipe;

  /// Snap distance to the centre lines, in screen pixels.
  static const double snapDistance = 10;

  /// Rotation snap tolerance.
  static const double rotationSnap = 5 * math.pi / 180;

  /// Minimum horizontal travel of a filter swipe, in screen pixels.
  static const double swipeDistance = 48;

  /// Minimum touch size of an overlay, in screen pixels.
  static const double minTouchExtent = 48;

  @override
  State<CanvasGestureLayer> createState() => _CanvasGestureLayerState();
}

class _GestureSession {
  _GestureSession(this.targetId);

  final String? targetId;
  int maxPointers = 0;
  Offset startFocal = Offset.zero;
  OverlayTransform? startTransform;
  MediaPlacement? startPlacement;
  Offset swipeOrigin = Offset.zero;
  Offset swipeLast = Offset.zero;
  bool overTrash = false;
  bool snapVertical = false;
  bool snapHorizontal = false;
  bool snapRotation = false;
}

class _CanvasGestureLayerState extends State<CanvasGestureLayer> {
  _GestureSession? _session;

  /// Where each current pointer went down (local), in down order. The
  /// recognizer reports its start only after the touch slop, so the first
  /// finger's down position decides what was grabbed and where the drag
  /// started.
  final Map<int, Offset> _downs = {};

  double get _s => widget.viewScale;

  EditorController get _controller => widget.controller;

  void _onTapUp(TapUpDetails details) {
    final hit = OverlayGeometry.hitTest(
      _controller.document.overlays,
      details.localPosition / _s,
      widget.resources,
      minExtent: CanvasGestureLayer.minTouchExtent / _s,
    );
    widget.onTap(hit);
  }

  void _onScaleStart(ScaleStartDetails details) {
    var focal = details.localFocalPoint / _s;
    var session = _session;
    if (session == null) {
      final firstDown = _downs.isEmpty ? null : _downs.values.first;
      final grab = (firstDown ?? details.localFocalPoint) / _s;
      if (details.pointerCount == 1 && firstDown != null) {
        focal = grab;
      }
      final hit = OverlayGeometry.hitTest(
        _controller.document.overlays,
        grab,
        widget.resources,
        minExtent: CanvasGestureLayer.minTouchExtent / _s,
      );
      session = _session = _GestureSession(hit?.id)
        ..swipeOrigin = firstDown ?? details.localFocalPoint
        ..swipeLast = details.localFocalPoint;
      _controller.beginGesture();
      if (hit != null) {
        _controller
          ..bringToFront(hit.id)
          ..select(hit.id);
        widget.interaction.startDrag(hit.id);
      }
    }
    session
      ..maxPointers = math.max(session.maxPointers, details.pointerCount)
      ..startFocal = focal
      ..startTransform = _controller.overlayById(session.targetId)?.transform
      ..startPlacement = _controller.document.placement;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final session = _session;
    if (session == null) {
      return;
    }
    session.maxPointers = math.max(session.maxPointers, details.pointerCount);
    final focal = details.localFocalPoint / _s;
    final targetId = session.targetId;
    final start = session.startTransform;
    if (targetId != null && start != null) {
      _updateOverlay(session, targetId, start, focal, details);
      return;
    }
    if (targetId != null) {
      return;
    }
    if (session.maxPointers >= 2) {
      final placement = session.startPlacement!;
      _controller.setPlacement(
        MediaPlacement(
          scale: placement.scale * details.scale,
          offset: placement.offset + (focal - session.startFocal),
        ),
      );
    } else {
      session.swipeLast = details.localFocalPoint;
    }
  }

  void _updateOverlay(
    _GestureSession session,
    String id,
    OverlayTransform start,
    Offset focal,
    ScaleUpdateDetails details,
  ) {
    var position = start.position + (focal - session.startFocal);
    var rotation = start.rotation + details.rotation;
    var scale = start.scale * details.scale;
    final snap = CanvasGestureLayer.snapDistance / _s;
    const center = StoryCanvas.center;
    final snapVertical = (position.dx - center.dx).abs() < snap;
    final snapHorizontal = (position.dy - center.dy).abs() < snap;
    if (snapVertical) {
      position = Offset(center.dx, position.dy);
    }
    if (snapHorizontal) {
      position = Offset(position.dx, center.dy);
    }
    var snapRotation = false;
    if (session.maxPointers >= 2) {
      const quarter = math.pi / 2;
      final nearest = (rotation / quarter).roundToDouble() * quarter;
      if ((rotation - nearest).abs() < CanvasGestureLayer.rotationSnap) {
        rotation = nearest;
        snapRotation = true;
      }
    }
    final trash = TrashZone.centerIn(context.size ?? Size.zero);
    final overTrash =
        (details.localFocalPoint - trash).distance < TrashZone.hitRadius;
    if (overTrash) {
      scale = math.min(scale, start.scale) * TrashZone.shrink;
    }
    if (overTrash && !session.overTrash) {
      HapticFeedback.mediumImpact();
    }
    final snapped =
        (snapVertical && !session.snapVertical) ||
        (snapHorizontal && !session.snapHorizontal) ||
        (snapRotation && !session.snapRotation);
    if (snapped) {
      HapticFeedback.selectionClick();
    }
    session
      ..overTrash = overTrash
      ..snapVertical = snapVertical
      ..snapHorizontal = snapHorizontal
      ..snapRotation = snapRotation;
    widget.interaction.updateDrag(
      overTrash: overTrash,
      snapVertical: snapVertical,
      snapHorizontal: snapHorizontal,
    );
    _controller.transformOverlay(
      id,
      OverlayTransform(position: position, scale: scale, rotation: rotation),
    );
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (details.pointerCount > 0) {
      return;
    }
    _finish(details.velocity);
  }

  void _onPointerGone(PointerEvent event) {
    _downs.remove(event.pointer);
    if (_downs.isNotEmpty || _session == null) {
      return;
    }
    // After a finger is lifted from a pinch the recognizer waits for new
    // movement before restarting, so it may never report the final end.
    // The recognizer handles this event after the listener: give it the
    // chance to end the gesture (with its velocity) first.
    final session = _session;
    scheduleMicrotask(() {
      if (mounted && identical(_session, session)) {
        _finish(Velocity.zero);
      }
    });
  }

  void _finish(Velocity velocity) {
    final session = _session;
    if (session == null) {
      return;
    }
    _session = null;
    final targetId = session.targetId;
    if (targetId != null) {
      if (session.overTrash) {
        _controller.deleteOverlay(targetId);
        HapticFeedback.heavyImpact();
      }
      _controller.endGesture();
      widget.interaction.endDrag();
      return;
    }
    _controller.endGesture();
    if (session.maxPointers == 1) {
      final delta = session.swipeLast - session.swipeOrigin;
      final vx = velocity.pixelsPerSecond.dx;
      final horizontal = delta.dx.abs() > delta.dy.abs() * 1.5;
      if (horizontal &&
          (delta.dx.abs() > CanvasGestureLayer.swipeDistance ||
              vx.abs() > 600)) {
        widget.onFilterSwipe(delta.dx < 0 ? 1 : -1);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (e) => _downs[e.pointer] = e.localPosition,
    onPointerUp: _onPointerGone,
    onPointerCancel: _onPointerGone,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTapUp: _onTapUp,
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onScaleEnd: _onScaleEnd,
      child: const SizedBox.expand(),
    ),
  );
}
