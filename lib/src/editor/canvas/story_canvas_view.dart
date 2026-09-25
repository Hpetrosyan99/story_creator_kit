import 'package:flutter/widgets.dart';

import '../../api/config/editor_options.dart';
import '../../api/strings/editor_strings.dart';
import '../../model/drawing_stroke.dart';
import '../../model/story_document.dart';
import '../../model/story_overlay.dart';
import '../../render/painters/story_paint_resources.dart';
import '../accessibility/overlay_actions.dart';
import '../drawing/drawing_brush.dart';
import '../editor_controller.dart';
import '../filters/filter_strip.dart';
import 'canvas_gesture_layer.dart';
import 'canvas_interaction.dart';
import 'drawing_layer.dart';
import 'media_layer.dart';
import 'overlay_layer.dart';
import 'overlay_semantics.dart';
import 'snap_guides.dart';
import 'trash_zone.dart';

/// The 1080×1920 canvas scaled to the view: background, media, strokes and
/// overlays (all edits drawn by the shared painters), plus interaction
/// chrome (snap guides, trash zone, filter name) that is never exported.
class StoryCanvasView extends StatelessWidget {
  /// Creates the view.
  const StoryCanvasView({
    required this.document,
    required this.controller,
    required this.interaction,
    required this.resources,
    required this.resourcesRevision,
    required this.options,
    required this.strings,
    required this.viewScale,
    required this.brush,
    required this.drawing,
    required this.onTap,
    required this.onFilterSwipe,
    required this.onStroke,
    required this.onOverlayAction,
    required this.onOverlayActivate,
    required this.onCanvasActivate,
    this.video,
    this.hiddenOverlayId,
    super.key,
  });

  /// The document to show.
  final StoryDocument document;

  /// Editor state (gestures).
  final EditorController controller;

  /// Drag feedback.
  final CanvasInteraction interaction;

  /// Fonts, stickers and filters.
  final StoryPaintResources resources;

  /// Changes when resources finish loading.
  final int resourcesRevision;

  /// Editor options.
  final EditorOptions options;

  /// Labels.
  final EditorStrings strings;

  /// Screen pixels per canvas unit.
  final double viewScale;

  /// Brush of the drawing tool.
  final DrawingBrush brush;

  /// Whether the drawing tool is active (input draws strokes).
  final bool drawing;

  /// The video view, for videos.
  final Widget? video;

  /// Overlay hidden while the text editor shows it.
  final String? hiddenOverlayId;

  /// A tap on the canvas (overlay under it, or `null`).
  final ValueChanged<StoryOverlay?> onTap;

  /// Horizontal swipe on the media.
  final ValueChanged<int> onFilterSwipe;

  /// A stroke was drawn.
  final ValueChanged<DrawingStroke> onStroke;

  /// An accessibility action on an overlay.
  final void Function(StoryOverlay overlay, OverlayAction action)
  onOverlayAction;

  /// An overlay was activated with a screen reader.
  final ValueChanged<StoryOverlay> onOverlayActivate;

  /// The canvas was activated with a screen reader (adds text).
  final VoidCallback? onCanvasActivate;

  @override
  Widget build(BuildContext context) {
    final filter = resources.filter(document.filterId);
    return Stack(
      fit: StackFit.expand,
      children: [
        BackgroundLayer(background: document.background, viewScale: viewScale),
        MediaLayer(
          media: document.media,
          placement: document.placement,
          viewScale: viewScale,
          filter: filter,
          video: video,
        ),
        DrawingLayer(
          strokes: document.strokes,
          viewScale: viewScale,
          brush: brush,
          enabled: drawing,
          onStroke: onStroke,
        ),
        OverlayLayer(
          overlays: document.overlays,
          resources: resources,
          viewScale: viewScale,
          resourcesRevision: resourcesRevision,
          hiddenId: hiddenOverlayId,
        ),
        SnapGuides(interaction: interaction),
        if (!drawing)
          Semantics(
            container: true,
            label: strings.canvas,
            hint: onCanvasActivate == null ? null : strings.canvasHint,
            onTap: onCanvasActivate,
            child: CanvasGestureLayer(
              controller: controller,
              interaction: interaction,
              resources: resources,
              viewScale: viewScale,
              onTap: onTap,
              onFilterSwipe: onFilterSwipe,
            ),
          ),
        if (!drawing)
          OverlaySemanticsLayer(
            overlays: [
              for (final o in document.overlays)
                if (o.id != hiddenOverlayId) o,
            ],
            resources: resources,
            options: options,
            strings: strings,
            viewScale: viewScale,
            selectedId: controller.selectedId,
            onAction: onOverlayAction,
            onActivate: onOverlayActivate,
          ),
        TrashZone(interaction: interaction),
        Center(
          child: ListenableBuilder(
            listenable: interaction,
            builder: (context, _) =>
                FilterNameLabel(label: interaction.filterLabel),
          ),
        ),
      ],
    );
  }
}
