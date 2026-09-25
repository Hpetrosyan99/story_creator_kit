import 'package:flutter/foundation.dart';

/// Strings shared across the story creator's screens.
@immutable
class CommonStrings {
  /// Creates the shared strings. Defaults are English.
  const CommonStrings({
    this.close = 'Close',
    this.back = 'Back',
    this.done = 'Done',
    this.cancel = 'Cancel',
    this.retry = 'Try again',
    this.discard = 'Discard',
    this.keepEditing = 'Keep editing',
    this.discardTitle = 'Discard this story?',
    this.discardMessage = 'Your edits will be lost.',
    this.openSettings = 'Open settings',
    this.genericError = 'Something went wrong.',
  });

  /// Close button label.
  final String close;

  /// Back button label.
  final String back;

  /// Confirm button label.
  final String done;

  /// Cancel button label.
  final String cancel;

  /// Retry button label.
  final String retry;

  /// Destructive confirm in the discard dialog.
  final String discard;

  /// Dismisses the discard dialog.
  final String keepEditing;

  /// Discard dialog title.
  final String discardTitle;

  /// Discard dialog message.
  final String discardMessage;

  /// Opens the system settings page of the app.
  final String openSettings;

  /// Fallback error message.
  final String genericError;
}
