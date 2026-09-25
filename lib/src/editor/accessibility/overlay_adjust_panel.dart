import 'package:flutter/material.dart';

import '../../core/story_scope.dart';
import '../../model/story_overlay.dart';
import '../widgets/editor_icon_button.dart';
import '../widgets/editor_panel.dart';
import 'overlay_actions.dart';

/// Buttons that do what the gestures do, for one overlay at a time:
/// choose the overlay, move, resize, rotate, bring to front, edit, delete.
class OverlayAdjustPanel extends StatelessWidget {
  /// Creates the panel.
  const OverlayAdjustPanel({
    required this.overlay,
    required this.description,
    required this.onAction,
    required this.onSelect,
    required this.onClose,
    super.key,
  });

  /// The overlay being adjusted.
  final StoryOverlay overlay;

  /// Readable name of [overlay].
  final String description;

  /// An action was chosen.
  final ValueChanged<OverlayAction> onAction;

  /// Select the previous (-1) or next (+1) overlay.
  final ValueChanged<int> onSelect;

  /// Close tapped.
  final VoidCallback onClose;

  static const Map<OverlayAction, IconData> _icons = {
    OverlayAction.moveUp: Icons.arrow_upward,
    OverlayAction.moveDown: Icons.arrow_downward,
    OverlayAction.moveLeft: Icons.arrow_back,
    OverlayAction.moveRight: Icons.arrow_forward,
    OverlayAction.enlarge: Icons.zoom_in,
    OverlayAction.shrink: Icons.zoom_out,
    OverlayAction.rotateLeft: Icons.rotate_left,
    OverlayAction.rotateRight: Icons.rotate_right,
    OverlayAction.bringToFront: Icons.flip_to_front,
    OverlayAction.edit: Icons.edit,
    OverlayAction.delete: Icons.delete_outline,
  };

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final strings = scope.strings;
    return EditorPanel(
      child: Semantics(
        container: true,
        label: strings.editor.adjust,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                EditorIconButton(
                  icon: Icons.chevron_left,
                  label: strings.editor.previousItem,
                  onPressed: () => onSelect(-1),
                ),
                Expanded(
                  child: Text(
                    description,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyStyle,
                  ),
                ),
                EditorIconButton(
                  icon: Icons.chevron_right,
                  label: strings.editor.nextItem,
                  onPressed: () => onSelect(1),
                ),
                const SizedBox(width: 8),
                EditorIconButton(
                  icon: Icons.close,
                  label: strings.common.close,
                  onPressed: onClose,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in OverlayActions.available(overlay))
                  EditorIconButton(
                    icon: _icons[action]!,
                    label: OverlayActions.label(action, strings.editor),
                    onPressed: () => onAction(action),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
