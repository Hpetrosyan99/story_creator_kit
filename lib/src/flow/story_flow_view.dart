import 'package:flutter/material.dart';

import '../api/result/story_result.dart';
import '../camera/camera_screen.dart';
import '../core/story_scope.dart';
import '../editor/editor_screen.dart';
import '../export/export_screen.dart';
import '../preview/preview_screen.dart';
import 'story_flow_controller.dart';

/// Renders the flow's current step.
///
/// The editor stays mounted under export and preview so its state (and undo
/// history) survives a round trip. Back handling: the camera step closes the
/// creator; the editor, export and preview screens handle back themselves.
class StoryFlowView extends StatelessWidget {
  /// Creates the view.
  const StoryFlowView({
    required this.controller,
    required this.onFinished,
    super.key,
  });

  /// Flow state.
  final StoryFlowController controller;

  /// Called once with the outcome.
  final ValueChanged<StoryOutcome> onFinished;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final step = controller.step;
        final initial = controller.initialDocument;
        final exportDocument = controller.exportDocument;
        final exported = controller.exported;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) {
              return;
            }
            switch (step) {
              case StoryFlowStep.camera:
                onFinished(
                  await controller.cancel(StoryCancelReason.userCancelled),
                );
              case StoryFlowStep.editor:
              case StoryFlowStep.exporting:
              case StoryFlowStep.preview:
                // These screens handle back themselves.
                break;
            }
          },
          child: ColoredBox(
            color: theme.background,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (step == StoryFlowStep.camera)
                  CameraScreen(
                    onMediaReady: controller.mediaReady,
                    onClose: () async => onFinished(
                      await controller.cancel(StoryCancelReason.userCancelled),
                    ),
                  ),
                if (step != StoryFlowStep.camera && initial != null)
                  EditorScreen(
                    key: ValueKey(controller.editorGeneration),
                    initialDocument: initial,
                    active: step == StoryFlowStep.editor,
                    onExport: controller.requestExport,
                    onBack: controller.leaveEditor,
                  ),
                if (step == StoryFlowStep.exporting && exportDocument != null)
                  ExportScreen(
                    document: exportDocument,
                    onExported: (story) async {
                      final outcome = await controller.exportFinished(story);
                      if (outcome != null) {
                        onFinished(outcome);
                      }
                    },
                    onAbort: controller.exportAborted,
                  ),
                if (step == StoryFlowStep.preview && exported != null)
                  PreviewScreen(
                    story: exported,
                    onConfirm: ({required savedToGallery}) async => onFinished(
                      await controller.complete(savedToGallery: savedToGallery),
                    ),
                    onBack: controller.backToEditor,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
