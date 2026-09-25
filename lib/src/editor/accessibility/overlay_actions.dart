import 'dart:math' as math;
import 'dart:ui';

import '../../api/strings/editor_strings.dart';
import '../../core/story_canvas.dart';
import '../../model/story_overlay.dart';
import '../editor_controller.dart';

/// Non-gesture overlay adjustments, used by the semantics actions and the
/// Adjust panel.
enum OverlayAction {
  /// Move up by [OverlayActions.moveStep].
  moveUp,

  /// Move down.
  moveDown,

  /// Move left.
  moveLeft,

  /// Move right.
  moveRight,

  /// Scale up by [OverlayActions.scaleStep].
  enlarge,

  /// Scale down.
  shrink,

  /// Rotate counter-clockwise by [OverlayActions.rotateStep].
  rotateLeft,

  /// Rotate clockwise.
  rotateRight,

  /// Move to the top of the stack.
  bringToFront,

  /// Open the text editor (text overlays only).
  edit,

  /// Remove the overlay.
  delete,
}

/// Applies [OverlayAction]s.
abstract final class OverlayActions {
  /// Move distance in canvas units (5 % of the canvas width).
  static const double moveStep = StoryCanvas.width * 0.05;

  /// Scale factor per step.
  static const double scaleStep = 1.15;

  /// Rotation per step.
  static const double rotateStep = 15 * math.pi / 180;

  /// Actions offered for [overlay].
  static List<OverlayAction> available(StoryOverlay overlay) => [
    for (final action in OverlayAction.values)
      if (action != OverlayAction.edit || overlay is TextOverlay) action,
  ];

  /// The label of [action].
  static String label(OverlayAction action, EditorStrings strings) =>
      switch (action) {
        OverlayAction.moveUp => strings.moveUp,
        OverlayAction.moveDown => strings.moveDown,
        OverlayAction.moveLeft => strings.moveLeft,
        OverlayAction.moveRight => strings.moveRight,
        OverlayAction.enlarge => strings.enlarge,
        OverlayAction.shrink => strings.shrink,
        OverlayAction.rotateLeft => strings.rotateLeft,
        OverlayAction.rotateRight => strings.rotateRight,
        OverlayAction.bringToFront => strings.bringToFront,
        OverlayAction.edit => strings.edit,
        OverlayAction.delete => strings.delete,
      };

  /// Applies [action] to the overlay with [id] as one undo step. `edit`
  /// calls [onEdit] instead.
  static void apply(
    EditorController controller,
    String id,
    OverlayAction action, {
    required void Function(TextOverlay overlay) onEdit,
  }) {
    final overlay = controller.overlayById(id);
    if (overlay == null) {
      return;
    }
    final t = overlay.transform;
    switch (action) {
      case OverlayAction.moveUp:
        controller.transformOverlay(
          id,
          t.copyWith(position: t.position + const Offset(0, -moveStep)),
        );
      case OverlayAction.moveDown:
        controller.transformOverlay(
          id,
          t.copyWith(position: t.position + const Offset(0, moveStep)),
        );
      case OverlayAction.moveLeft:
        controller.transformOverlay(
          id,
          t.copyWith(position: t.position + const Offset(-moveStep, 0)),
        );
      case OverlayAction.moveRight:
        controller.transformOverlay(
          id,
          t.copyWith(position: t.position + const Offset(moveStep, 0)),
        );
      case OverlayAction.enlarge:
        controller.transformOverlay(id, t.copyWith(scale: t.scale * scaleStep));
      case OverlayAction.shrink:
        controller.transformOverlay(id, t.copyWith(scale: t.scale / scaleStep));
      case OverlayAction.rotateLeft:
        controller.transformOverlay(
          id,
          t.copyWith(rotation: t.rotation - rotateStep),
        );
      case OverlayAction.rotateRight:
        controller.transformOverlay(
          id,
          t.copyWith(rotation: t.rotation + rotateStep),
        );
      case OverlayAction.bringToFront:
        controller.bringToFront(id);
      case OverlayAction.edit:
        if (overlay is TextOverlay) {
          onEdit(overlay);
        }
      case OverlayAction.delete:
        controller.deleteOverlay(id);
    }
  }
}
