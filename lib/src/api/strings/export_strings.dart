import 'package:flutter/foundation.dart';

/// Export, preview and save strings.
///
/// Owned by the export area; add fields here as that area needs them.
@immutable
class ExportStrings {
  /// Creates the export strings. Defaults are English.
  const ExportStrings({
    this.exporting = 'Creating your story…',
    this.cancelExport = 'Cancel',
    this.exportFailed = 'Your story could not be created.',
    this.notEnoughSpace = 'There is not enough free space on this device.',
    this.previewTitle = 'Preview',
    this.useStory = 'Use story',
    this.backToEditor = 'Edit',
    this.saveToGallery = 'Save to gallery',
    this.savedToGallery = 'Saved to your gallery.',
    this.saveFailed = 'Could not save to your gallery.',
    this.cancelExportTitle = 'Stop creating your story?',
    this.cancelExportMessage = 'Your edits are kept.',
    this.stopExport = 'Stop',
    this.keepExporting = 'Continue',
    this.exportProgress = 'Export progress',
    this.savedLabel = 'Saved',
    this.photoPreview = 'Story photo',
    this.videoPreview = 'Story video',
  });

  /// Export progress title.
  final String exporting;

  /// Cancel export action.
  final String cancelExport;

  /// Export failure message.
  final String exportFailed;

  /// Export failure message for a full disk.
  final String notEnoughSpace;

  /// Preview screen title.
  final String previewTitle;

  /// Confirms the exported story.
  final String useStory;

  /// Returns from preview to the editor.
  final String backToEditor;

  /// Save-to-gallery action.
  final String saveToGallery;

  /// Save success message.
  final String savedToGallery;

  /// Save failure message.
  final String saveFailed;

  /// Title of the dialog confirming that the export should stop.
  final String cancelExportTitle;

  /// Message of the stop-export dialog.
  final String cancelExportMessage;

  /// Confirms stopping the export.
  final String stopExport;

  /// Dismisses the stop-export dialog.
  final String keepExporting;

  /// Semantics label of the progress ring.
  final String exportProgress;

  /// Label of the save button after a successful save.
  final String savedLabel;

  /// Semantics label of the exported photo in the preview.
  final String photoPreview;

  /// Semantics label of the exported video in the preview.
  final String videoPreview;
}
