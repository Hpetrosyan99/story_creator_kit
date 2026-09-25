import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import '../../api/config/editor_options.dart';
import '../../api/strings/editor_strings.dart';
import '../../model/story_overlay.dart';
import '../../render/painters/story_paint_resources.dart';
import '../accessibility/overlay_actions.dart';
import 'overlay_geometry.dart';

/// Invisible semantics nodes over each overlay, with custom actions (move,
/// resize, rotate, bring to front, edit, delete) so screen-reader users can
/// do everything the gestures do.
class OverlaySemanticsLayer extends StatelessWidget {
  /// Creates the layer.
  const OverlaySemanticsLayer({
    required this.overlays,
    required this.resources,
    required this.options,
    required this.strings,
    required this.viewScale,
    required this.onAction,
    required this.onActivate,
    this.selectedId,
    super.key,
  });

  /// Overlays bottom to top.
  final List<StoryOverlay> overlays;

  /// Fonts and stickers for bounds.
  final StoryPaintResources resources;

  /// Sticker labels.
  final EditorOptions options;

  /// Labels.
  final EditorStrings strings;

  /// Screen pixels per canvas unit.
  final double viewScale;

  /// The selected overlay.
  final String? selectedId;

  /// An action was chosen for an overlay.
  final void Function(StoryOverlay overlay, OverlayAction action) onAction;

  /// The overlay was activated (double tap with a screen reader).
  final ValueChanged<StoryOverlay> onActivate;

  /// Semantics label and value of [overlay].
  static (String, String) describe(
    StoryOverlay overlay,
    EditorStrings strings,
    EditorOptions options,
  ) => switch (overlay) {
    TextOverlay(:final text) => (strings.textOverlay, text),
    StickerOverlay(:final stickerId) => (
      strings.stickerOverlay,
      options.stickers
              .where((s) => s.id == stickerId)
              .map((s) => s.label)
              .firstOrNull ??
          '',
    ),
    EmojiOverlay(:final emoji) => (strings.emojiOverlay, emoji),
  };

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      for (final overlay in overlays)
        _OverlayNode(
          key: ValueKey(overlay.id),
          overlay: overlay,
          rect: _scaled(OverlayGeometry.bounds(overlay, resources)),
          description: describe(overlay, strings, options),
          selected: overlay.id == selectedId,
          actions: {
            for (final action in OverlayActions.available(overlay))
              CustomSemanticsAction(
                label: OverlayActions.label(action, strings),
              ): () =>
                  onAction(overlay, action),
          },
          onActivate: () => onActivate(overlay),
        ),
    ],
  );

  Rect _scaled(Rect r) => Rect.fromLTRB(
    r.left * viewScale,
    r.top * viewScale,
    r.right * viewScale,
    r.bottom * viewScale,
  );
}

class _OverlayNode extends StatelessWidget {
  const _OverlayNode({
    required this.overlay,
    required this.rect,
    required this.description,
    required this.selected,
    required this.actions,
    required this.onActivate,
    super.key,
  });

  final StoryOverlay overlay;
  final Rect rect;
  final (String, String) description;
  final bool selected;
  final Map<CustomSemanticsAction, VoidCallback> actions;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) => Positioned.fromRect(
    rect: rect,
    child: Semantics(
      container: true,
      label: description.$1,
      value: description.$2,
      selected: selected,
      onTap: onActivate,
      customSemanticsActions: actions,
      child: const SizedBox.expand(),
    ),
  );
}
