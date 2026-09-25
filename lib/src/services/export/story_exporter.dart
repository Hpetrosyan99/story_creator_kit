import 'package:flutter/foundation.dart';

import '../../api/config/output_options.dart';
import '../../api/result/story_result.dart';
import '../../core/session_files.dart';
import '../../model/story_document.dart';
import '../../render/painters/story_paint_resources.dart';

/// An exported file, before the flow turns it into a `StoryResult`.
@immutable
class ExportedStory {
  /// Creates an exported story.
  const ExportedStory({
    required this.path,
    required this.type,
    required this.width,
    required this.height,
    required this.fileSizeBytes,
    this.duration,
    this.thumbnailPath,
  });

  /// Absolute path in the export directory.
  final String path;

  /// Photo (JPEG) or video (MP4).
  final StoryMediaType type;

  /// Pixel width.
  final int width;

  /// Pixel height.
  final int height;

  /// File size.
  final int fileSizeBytes;

  /// Video length.
  final Duration? duration;

  /// Poster frame for videos.
  final String? thumbnailPath;

  /// MIME type.
  String get mimeType =>
      type == StoryMediaType.photo ? 'image/jpeg' : 'video/mp4';
}

/// Thrown by [ExportJob.result] when the job was cancelled.
class ExportCancelledException implements Exception {
  /// Creates the exception.
  const ExportCancelledException();

  @override
  String toString() => 'ExportCancelledException';
}

/// Inputs an export needs besides the document.
@immutable
class ExportContext {
  /// Creates a context.
  const ExportContext({
    required this.session,
    required this.outputDirectory,
    required this.output,
    required this.resources,
  });

  /// Session working directory for intermediate files.
  final SessionFiles session;

  /// Where the final file goes.
  final String outputDirectory;

  /// Output settings.
  final OutputOptions output;

  /// Fonts, sticker images and filters used by the painters.
  final StoryPaintResources resources;
}

/// A running export.
abstract class ExportJob {
  /// Progress 0–1. Completes when the job ends.
  Stream<double> get progress;

  /// The exported file. Throws [ExportCancelledException] after [cancel], or
  /// `StoryException(exportFailed | insufficientStorage)`.
  Future<ExportedStory> get result;

  /// Cancels the job and deletes partial output.
  Future<void> cancel();
}

/// Renders a `StoryDocument` into a JPEG or MP4.
abstract class StoryExporter {
  /// Starts exporting [document].
  ExportJob start(StoryDocument document, ExportContext context);
}
