import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../api/config/output_options.dart';
import '../api/config/story_creator_config.dart';
import '../api/errors/story_exception.dart';
import '../api/events/story_event.dart';
import '../api/result/story_result.dart';
import '../core/session_files.dart';
import '../core/story_canvas.dart';
import '../model/story_document.dart';
import '../model/story_media.dart';
import '../model/story_overlay.dart';
import '../model/trim_range.dart';
import '../services/export/story_exporter.dart';
import '../services/story_services.dart';

/// Steps of the story flow.
enum StoryFlowStep {
  /// Camera and gallery.
  camera,

  /// Editing.
  editor,

  /// Export in progress (editor underneath).
  exporting,

  /// Showing the exported file (editor underneath).
  preview,
}

/// Drives the flow camera → editor → export → preview → result.
///
/// Owns no UI; `StoryCreatorPage` renders the current [step].
class StoryFlowController extends ChangeNotifier {
  /// Creates the controller.
  StoryFlowController({
    required this.config,
    required this.services,
    required this.session,
    required this.report,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Host configuration.
  final StoryCreatorConfig config;

  /// Platform services.
  final StoryServices services;

  /// Session working directory.
  final SessionFiles session;

  /// Event sink (the scope's `report`).
  final void Function(StoryEvent event) report;

  final DateTime Function() _clock;

  StoryFlowStep _step = StoryFlowStep.camera;
  StoryDocument? _initialDocument;
  StoryDocument? _exportDocument;
  ExportedStory? _exported;
  int _editorGeneration = 0;
  bool _finished = false;

  /// Current step.
  StoryFlowStep get step => _step;

  /// Document the editor starts from; set from the editor step on.
  StoryDocument? get initialDocument => _initialDocument;

  /// Document being exported / previewed.
  StoryDocument? get exportDocument => _exportDocument;

  /// Exported file shown in preview.
  ExportedStory? get exported => _exported;

  /// Changes whenever new media opens the editor, so the editor is rebuilt
  /// from scratch.
  int get editorGeneration => _editorGeneration;

  /// Media from the camera or gallery is ready: open the editor.
  void mediaReady(StoryMedia media) {
    _initialDocument = initialDocumentFor(media);
    _editorGeneration++;
    report(
      StoryEvent(
        media.source == StorySourceKind.camera
            ? StoryEventType.captured
            : StoryEventType.mediaPicked,
        properties: {'type': media.type.name},
      ),
    );
    _go(StoryFlowStep.editor);
  }

  /// The first document for [media]: default placement and, for videos
  /// longer than the maximum, a trim to the first allowed seconds.
  StoryDocument initialDocumentFor(StoryMedia media) {
    TrimRange? trim;
    final duration = media.duration;
    final max = config.constraints.maxVideoDuration;
    if (media.isVideo && duration != null && duration > max) {
      trim = TrimRange(Duration.zero, max);
    }
    return StoryDocument(
      media: media,
      placement: StoryCanvas.defaultPlacement(media),
      filterId: config.editor.filters.first.isIdentity
          ? null
          : config.editor.filters.first.id,
      trim: trim,
    );
  }

  /// The user left the editor: back to the camera.
  void leaveEditor() {
    _initialDocument = null;
    _go(StoryFlowStep.camera);
  }

  /// The user confirmed the edits.
  void requestExport(StoryDocument document) {
    _exportDocument = document;
    report(
      StoryEvent(
        StoryEventType.exportStarted,
        properties: {'type': document.outputType.name},
      ),
    );
    _go(StoryFlowStep.exporting);
  }

  /// Export was cancelled or failed and the user went back.
  void exportAborted() {
    report(const StoryEvent(StoryEventType.exportCancelled));
    _go(StoryFlowStep.editor);
  }

  /// Export finished. Returns the outcome when no preview is shown.
  Future<StoryOutcome?> exportFinished(ExportedStory story) async {
    _exported = story;
    report(
      StoryEvent(
        StoryEventType.exportCompleted,
        properties: {
          'type': story.type.name,
          'bytes': story.fileSizeBytes,
          if (story.duration != null)
            'durationMs': story.duration!.inMilliseconds,
        },
      ),
    );
    if (!config.output.showPreview) {
      return complete(savedToGallery: false);
    }
    _go(StoryFlowStep.preview);
    return null;
  }

  /// From preview back to the editor; the exported file is discarded.
  Future<void> backToEditor() async {
    await _deleteExported();
    _go(StoryFlowStep.editor);
  }

  /// The user confirmed the exported story.
  Future<StoryOutcome> complete({required bool savedToGallery}) async {
    final story = _exported;
    final document = _exportDocument;
    if (story == null || document == null) {
      return const StoryFailed(
        StoryException(StoryErrorCode.unknown, 'complete() before export'),
      );
    }
    var saved = savedToGallery;
    if (!saved && config.output.saveToGallery == SaveToGalleryMode.always) {
      try {
        await services.gallerySaver.save(
          story.path,
          story.type,
          album: config.output.galleryAlbum,
        );
        saved = true;
        report(const StoryEvent(StoryEventType.savedToGallery));
      } on Object catch (e, s) {
        // The story is still returned; the host learns about the failed save.
        final error = e is StoryException
            ? e
            : StoryException(
                StoryErrorCode.saveToGalleryFailed,
                'Saving to the gallery failed.',
                e,
                s,
              );
        report(
          StoryEvent(
            StoryEventType.error,
            properties: {'code': error.code.name},
            error: error,
            stackTrace: s,
          ),
        );
      }
    }
    _finished = true;
    _exported = null;
    report(const StoryEvent(StoryEventType.completed));
    return StoryCompleted(buildResult(story, document, savedToGallery: saved));
  }

  /// The user closed the creator.
  Future<StoryOutcome> cancel(StoryCancelReason reason) async {
    await _deleteExported();
    _finished = true;
    report(
      StoryEvent(StoryEventType.cancelled, properties: {'reason': reason.name}),
    );
    return StoryCancelled(reason);
  }

  /// Whether [complete] or [cancel] ran.
  bool get finished => _finished;

  /// Builds the host-facing result.
  StoryResult buildResult(
    ExportedStory story,
    StoryDocument document, {
    required bool savedToGallery,
  }) {
    final music = document.music;
    return StoryResult(
      path: story.path,
      type: story.type,
      mimeType: story.mimeType,
      width: story.width,
      height: story.height,
      fileSizeBytes: story.fileSizeBytes,
      duration: story.duration,
      thumbnailPath: story.thumbnailPath,
      savedToGallery: savedToGallery,
      metadata: StoryMetadata(
        source: document.media.source,
        sourceType: document.media.type,
        createdAt: _clock(),
        trimStart: document.media.isVideo
            ? (document.trim?.start ?? Duration.zero)
            : null,
        trimEnd: document.media.isVideo
            ? (document.trim?.end ?? document.media.duration)
            : null,
        originalAudioVolume: document.media.isVideo
            ? document.originalVolume
            : 0,
        music: music == null
            ? null
            : StoryMusicMetadata(
                trackId: music.track.id,
                title: music.track.title,
                artist: music.track.artist,
                start: music.start,
                duration: music.duration,
                volume: music.volume,
                extra: music.track.extra,
              ),
        filterId: document.filterId,
        texts: [
          for (final o in document.overlays.whereType<TextOverlay>())
            StoryTextMetadata(
              text: o.text,
              fontId: o.style.fontId,
              colorValue: o.style.color.toARGB32(),
            ),
        ],
        stickerIds: [
          for (final o in document.overlays.whereType<StickerOverlay>())
            o.stickerId,
        ],
        emojis: [
          for (final o in document.overlays.whereType<EmojiOverlay>()) o.emoji,
        ],
        hasDrawing: document.strokes.isNotEmpty,
      ),
    );
  }

  Future<void> _deleteExported() async {
    final story = _exported;
    _exported = null;
    if (story == null) {
      return;
    }
    for (final path in [story.path, story.thumbnailPath]) {
      if (path == null) {
        continue;
      }
      try {
        final file = File(path);
        if (file.existsSync()) {
          await file.delete();
        }
      } on FileSystemException catch (e, s) {
        report(
          StoryEvent(
            StoryEventType.error,
            properties: const {'code': 'cleanup'},
            error: StoryException(StoryErrorCode.unknown, 'delete $path', e, s),
            stackTrace: s,
          ),
        );
      }
    }
  }

  void _go(StoryFlowStep step) {
    _step = step;
    notifyListeners();
  }
}
