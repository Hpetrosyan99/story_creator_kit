import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../api/config/output_options.dart';
import '../api/errors/story_exception.dart';
import '../api/result/story_result.dart';
import '../core/story_scope.dart';
import '../services/export/story_exporter.dart';
import '../services/video/video_session.dart';
import '../ui/story_icon.dart';
import '../ui/story_nav_button.dart';
import '../ui/story_stage.dart';
import '../ui/story_surface.dart';
import 'widgets/preview_toast.dart';

/// Plays the exported file; confirm or go back to editing.
///
/// Videos loop with their own audio; photos show the JPEG. The story is
/// shown full-bleed in a rounded 9:16 frame. Bottom bar: "Edit" (back), a
/// save button when `OutputOptions.saveToGallery` is
/// [SaveToGalleryMode.button], and the accent "Use story" button.
class PreviewScreen extends StatefulWidget {
  /// Creates the preview.
  const PreviewScreen({
    required this.story,
    required this.onConfirm,
    required this.onBack,
    super.key,
  });

  /// The exported file.
  final ExportedStory story;

  /// Called when the user confirms; `savedToGallery` tells whether the user
  /// already saved it with the save button.
  final void Function({required bool savedToGallery}) onConfirm;

  /// Called to return to the editor.
  final VoidCallback onBack;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  VideoSession? _video;
  bool _saving = false;
  bool _saved = false;
  bool _done = false;
  final PreviewToastController _toast = PreviewToastController();

  bool get _isVideo => widget.story.type == StoryMediaType.video;

  @override
  void initState() {
    super.initState();
    if (_isVideo) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_open()));
    }
  }

  Future<void> _open() async {
    if (!mounted) {
      return;
    }
    final scope = StoryScope.read(context);
    final session = scope.services.createVideoSession();
    setState(() => _video = session);
    try {
      await session.open(widget.story.path);
      await session.setPlaybackRange(null);
      if (mounted && !_done) {
        await session.play();
      }
    } on StoryException catch (e, s) {
      if (mounted) {
        scope.reportError(e, s);
      }
    }
  }

  @override
  void dispose() {
    unawaited(_video?.dispose());
    _toast.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _saved) {
      return;
    }
    final scope = StoryScope.read(context);
    final strings = scope.strings.export;
    setState(() => _saving = true);
    try {
      await scope.services.gallerySaver.save(
        widget.story.path,
        widget.story.type,
        album: scope.config.output.galleryAlbum,
      );
      if (!mounted) {
        return;
      }
      setState(() => _saved = true);
      _toast.show(strings.savedToGallery);
    } on StoryException catch (e, s) {
      scope.reportError(e, s);
      if (mounted) {
        _toast.show(strings.saveFailed, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _back() {
    if (_done) {
      return;
    }
    _done = true;
    unawaited(_video?.pause());
    widget.onBack();
  }

  void _confirm() {
    if (_done) {
      return;
    }
    _done = true;
    unawaited(_video?.pause());
    widget.onConfirm(savedToGallery: _saved);
  }

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final strings = scope.strings;
    final showSave =
        scope.config.output.saveToGallery == SaveToGalleryMode.button;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _back();
        }
      },
      child: StoryStage(
        card: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: theme.surface,
              child: _isVideo
                  ? Semantics(
                      label: strings.export.videoPreview,
                      child: _VideoPreview(session: _video),
                    )
                  : Image.file(
                      File(widget.story.path),
                      fit: BoxFit.cover,
                      semanticLabel: strings.export.photoPreview,
                      gaplessPlayback: true,
                    ),
            ),
            Positioned(
              top: 10,
              left: 14,
              right: 14,
              child: Row(
                children: [
                  StoryNavButton(
                    icon: StoryIcons.close,
                    label: strings.export.backToEditor,
                    onPressed: _back,
                  ),
                  const Spacer(),
                  StoryNavButton(
                    icon: StoryIcons.check,
                    label: strings.export.useStory,
                    style: StoryNavButtonStyle.accent,
                    onPressed: _confirm,
                  ),
                ],
              ),
            ),
            if (showSave)
              Positioned(
                right: 16,
                bottom: 16,
                child: _SaveButton(
                  label: _saved
                      ? strings.export.savedLabel
                      : strings.export.saveToGallery,
                  saved: _saved,
                  onPressed: _saved || _saving ? null : _save,
                ),
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 88,
              child: PreviewToast(controller: _toast, theme: theme),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPreview extends StatelessWidget {
  const _VideoPreview({required this.session});

  final VideoSession? session;

  @override
  Widget build(BuildContext context) {
    final session = this.session;
    if (session == null) {
      return const SizedBox.expand();
    }
    return ValueListenableBuilder<VideoPlaybackState>(
      valueListenable: session.state,
      builder: (context, state, _) {
        if (!state.initialized) {
          return const SizedBox.expand();
        }
        final size = state.size.isEmpty ? const Size(9, 16) : state.size;
        return FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: session.buildView(),
          ),
        );
      },
    );
  }
}

/// Save-to-gallery pill on the preview card.
class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.label,
    required this.saved,
    required this.onPressed,
  });

  final String label;
  final bool saved;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    return Semantics(
      button: true,
      label: label,
      enabled: onPressed != null,
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: StorySurface(
          fill: theme.pillBackground,
          radius: 22,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Icon(
                saved ? Icons.check_rounded : Icons.download_rounded,
                color: theme.onSurface,
                size: 20,
              ),
              Text(label, style: theme.bodyStyle),
            ],
          ),
        ),
      ),
    );
  }
}
