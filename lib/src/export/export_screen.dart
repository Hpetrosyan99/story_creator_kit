import 'dart:async';

import 'package:flutter/material.dart';

import '../api/errors/story_exception.dart';
import '../core/session_files.dart';
import '../core/story_scope.dart';
import '../model/story_document.dart';
import '../render/painters/story_paint_resources_loader.dart';
import '../services/export/story_exporter.dart';
import 'widgets/export_failure_view.dart';
import 'widgets/export_progress_ring.dart';

/// Export progress overlay with cancel, failure and retry.
///
/// Shown above the (inactive) editor: a dimmed layer with a circular
/// progress ring and a Cancel button that asks for confirmation. A failure
/// shows the reason with Retry and Back. System back asks to cancel while
/// exporting and goes back after a failure.
class ExportScreen extends StatefulWidget {
  /// Creates the export screen.
  const ExportScreen({
    required this.document,
    required this.onExported,
    required this.onAbort,
    super.key,
  });

  /// What to export.
  final StoryDocument document;

  /// Called with the exported file.
  final ValueChanged<ExportedStory> onExported;

  /// Called when the user cancels or gives up after a failure; returns to
  /// the editor.
  final VoidCallback onAbort;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  ExportJob? _job;
  StreamSubscription<double>? _progressSubscription;
  final ValueNotifier<double> _progress = ValueNotifier(0);
  StoryException? _failure;
  bool _leaving = false;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  @override
  void dispose() {
    unawaited(_progressSubscription?.cancel());
    final job = _job;
    if (job != null && !_leaving) {
      // Removed without a decision (flow closed): stop native work.
      unawaited(job.cancel());
    }
    _progress.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!mounted) {
      return;
    }
    final scope = StoryScope.read(context);
    setState(() => _failure = null);
    _progress.value = 0;
    try {
      await ensureStoryPaintResources(
        scope.resources,
        widget.document,
        scope.config.editor,
      );
      final outputDirectory = await SessionFiles.exportDirectory(
        scope.config.output.outputDirectory,
      );
      if (!mounted || _leaving) {
        return;
      }
      final job = scope.services.exporter.start(
        widget.document,
        ExportContext(
          session: scope.session,
          outputDirectory: outputDirectory.path,
          output: scope.config.output,
          resources: scope.resources,
        ),
      );
      _job = job;
      await _progressSubscription?.cancel();
      _progressSubscription = job.progress.listen(
        (p) => _progress.value = p.clamp(0, 1).toDouble(),
        onError: (Object _) {},
      );
      final story = await job.result;
      if (!mounted || _leaving) {
        return;
      }
      _leaving = true;
      _progress.value = 1;
      widget.onExported(story);
    } on ExportCancelledException {
      // Cancelled by the user; _cancel already left.
      return;
    } on Object catch (e, s) {
      final error = e is StoryException
          ? e
          : StoryException(
              StoryErrorCode.exportFailed,
              'Export failed unexpectedly.',
              e,
              s,
            );
      if (mounted) {
        StoryScope.read(context).reportError(error, s);
      }
      if (!mounted || _leaving) {
        return;
      }
      _job = null;
      setState(() => _failure = error);
    }
  }

  Future<void> _requestCancel() async {
    if (_leaving || _confirming) {
      return;
    }
    final scope = StoryScope.read(context);
    final strings = scope.strings;
    final theme = scope.theme;
    _confirming = true;
    final stop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.surface,
        title: Text(strings.export.cancelExportTitle, style: theme.titleStyle),
        content: Text(
          strings.export.cancelExportMessage,
          style: theme.bodyStyle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.export.keepExporting, style: theme.labelStyle),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              strings.export.stopExport,
              style: theme.labelStyle.copyWith(color: theme.error),
            ),
          ),
        ],
      ),
    );
    _confirming = false;
    if (stop != true || !mounted || _leaving || _failure != null) {
      return;
    }
    await _cancel();
  }

  Future<void> _cancel() async {
    _leaving = true;
    final job = _job;
    _job = null;
    await job?.cancel();
    if (mounted) {
      widget.onAbort();
    }
  }

  void _back() {
    if (_leaving) {
      return;
    }
    _leaving = true;
    widget.onAbort();
  }

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final strings = scope.strings;
    final failure = _failure;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        if (_failure != null) {
          _back();
        } else {
          unawaited(_requestCancel());
        }
      },
      child: ColoredBox(
        color: theme.scrim,
        child: SafeArea(
          child: Center(
            child: failure == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ExportProgressRing(
                        progress: _progress,
                        color: theme.accent,
                        trackColor: theme.outline,
                        textStyle: theme.titleStyle,
                        semanticsLabel: strings.export.exportProgress,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        strings.export.exporting,
                        style: theme.bodyStyle,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed: _requestCancel,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(120, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              theme.chipRadius,
                            ),
                            side: BorderSide(color: theme.outline),
                          ),
                        ),
                        child: Text(
                          strings.export.cancelExport,
                          style: theme.labelStyle,
                        ),
                      ),
                    ],
                  )
                : ExportFailureView(
                    message: failure.code == StoryErrorCode.insufficientStorage
                        ? strings.export.notEnoughSpace
                        : strings.export.exportFailed,
                    retryLabel: strings.common.retry,
                    backLabel: strings.common.back,
                    theme: theme,
                    onRetry: _start,
                    onBack: _back,
                  ),
          ),
        ),
      ),
    );
  }
}
