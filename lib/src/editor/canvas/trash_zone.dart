import 'package:flutter/material.dart';

import '../../core/story_scope.dart';
import 'canvas_interaction.dart';

/// The delete target shown at the bottom centre while an overlay is being
/// dragged. Chrome only; never exported.
class TrashZone extends StatelessWidget {
  /// Creates the trash zone.
  const TrashZone({required this.interaction, super.key});

  /// Drag state.
  final CanvasInteraction interaction;

  /// Distance of the zone's centre from the canvas bottom, screen pixels.
  static const double bottomOffset = 88;

  /// Visual radius, screen pixels.
  static const double radius = 28;

  /// Radius within which a drop deletes, screen pixels.
  static const double hitRadius = 44;

  /// Scale applied to an overlay hovering over the zone.
  static const double shrink = 0.5;

  /// Centre of the zone in a canvas view of [size].
  static Offset centerIn(Size size) =>
      Offset(size.width / 2, size.height - bottomOffset);

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ListenableBuilder(
      listenable: interaction,
      builder: (context, _) {
        final visible = interaction.dragging;
        final over = interaction.overTrash;
        return LayoutBuilder(
          builder: (context, constraints) {
            final center = centerIn(constraints.biggest);
            return Stack(
              children: [
                Positioned(
                  left: center.dx - hitRadius,
                  top: center.dy - hitRadius,
                  width: hitRadius * 2,
                  height: hitRadius * 2,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: visible ? 1 : 0,
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 150),
                      child: Semantics(
                        container: true,
                        label: scope.strings.editor.dragToDelete,
                        excludeSemantics: true,
                        child: Center(
                          child: AnimatedScale(
                            scale: over ? 1.3 : 1,
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 120),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: over
                                    ? theme.error
                                    : theme.controlBackground,
                                border: Border.all(color: theme.onSurface),
                              ),
                              child: SizedBox.square(
                                dimension: radius * 2,
                                child: Icon(
                                  Icons.delete_outline,
                                  color: theme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
