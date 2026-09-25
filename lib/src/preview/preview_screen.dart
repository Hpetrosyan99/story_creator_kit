import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../api/config/output_options.dart';
import '../api/errors/story_exception.dart';
import '../api/result/story_result.dart';
import '../api/theme/story_creator_theme.dart';
import '../core/story_scope.dart';
import '../services/export/story_exporter.dart';
import '../services/video/video_session.dart';
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
      child: ColoredBox(
        color: theme.background,
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 9 / 16,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              theme.cornerRadius,
                            ),
                            child: ColoredBox(
                              color: theme.surface,
                              child: _isVideo
                                  ? Semantics(
                                      label: strings.export.videoPreview,
                                      child: _VideoPreview(session: _video),
                                    )
                                  : Image.file(
                                      File(widget.story.path),
                                      fit: BoxFit.cover,
                                      semanticLabel:
                                          strings.export.photoPreview,
                                      gaplessPlayback: true,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        _PillButton(
                          label: strings.export.backToEditor,
                          icon: Icons.edit_outlined,
                          theme: theme,
                          onPressed: _back,
                        ),
                        if (showSave) ...[
                          const SizedBox(width: 8),
                          _PillButton(
                            label: _saved
                                ? strings.export.savedLabel
                                : strings.export.saveToGallery,
                            icon: _saved
                                ? Icons.check_rounded
                                : Icons.download_rounded,
                            theme: theme,
                            busy: _saving,
                            onPressed: _saved || _saving ? null : _save,
                            iconOnly: true,
                          ),
                        ],
                        const Spacer(),
                        FilledButton(
                          onPressed: _confirm,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(128, 48),
                            backgroundColor: theme.accent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                theme.chipRadius * 2,
                              ),
                            ),
                          ),
                          child: Text(
                            strings.export.useStory,
                            style: theme.labelStyle.copyWith(
                              color: theme.onAccent,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 80,
                child: PreviewToast(controller: _toast, theme: theme),
              ),
            ],
          ),
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

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.icon,
    required this.theme,
    required this.onPressed,
    this.busy = false,
    this.iconOnly = false,
  });

  final String label;
  final IconData icon;
  final StoryCreatorTheme theme;
  final VoidCallback? onPressed;
  final bool busy;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final content = busy
        ? SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
          )
        : Icon(icon, color: t.onSurface, size: 20);
    return Semantics(
      button: true,
      label: label,
      enabled: onPressed != null,
      excludeSemantics: true,
      child: Material(
        color: t.surfaceVariant,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: iconOnly ? 12 : 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  content,
                  if (!iconOnly) ...[
                    const SizedBox(width: 8),
                    Text(label, style: t.labelStyle),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
