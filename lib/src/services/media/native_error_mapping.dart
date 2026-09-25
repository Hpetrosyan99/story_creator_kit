import 'dart:io';

import 'package:flutter/services.dart';

import '../../api/errors/story_exception.dart';

/// Error codes sent by the native side (see `pigeons/story_native_api.dart`).
abstract final class NativeErrorCodes {
  /// The job was cancelled.
  static const String cancelled = 'cancelled';

  /// A request field is wrong (missing file, bad rect…).
  static const String invalidInput = 'invalid_input';

  /// The file cannot be decoded.
  static const String unsupportedMedia = 'unsupported_media';

  /// Not enough storage.
  static const String noSpace = 'no_space';

  /// The platform encoder failed.
  static const String encoder = 'encoder';

  /// Reading or writing a file failed.
  static const String io = 'io';
}

/// Maps a failed inspection call to `mediaUnsupported` / `mediaUnavailable`.
StoryException inspectionError(
  Object error,
  StackTrace stackTrace,
  String what,
) {
  if (error is StoryException) {
    return error;
  }
  if (error is PlatformException) {
    final code = switch (error.code) {
      NativeErrorCodes.unsupportedMedia => StoryErrorCode.mediaUnsupported,
      NativeErrorCodes.noSpace => StoryErrorCode.insufficientStorage,
      _ => StoryErrorCode.mediaUnavailable,
    };
    return StoryException(code, '$what: ${error.message}', error, stackTrace);
  }
  return StoryException(
    StoryErrorCode.mediaUnavailable,
    '$what failed',
    error,
    stackTrace,
  );
}

/// Maps a failed export step to `exportFailed` / `insufficientStorage`.
///
/// Cancellation is not mapped here; callers check [isNativeCancellation].
StoryException exportError(Object error, StackTrace stackTrace, String what) {
  if (error is StoryException) {
    return error;
  }
  if (error is PlatformException) {
    final code = error.code == NativeErrorCodes.noSpace
        ? StoryErrorCode.insufficientStorage
        : StoryErrorCode.exportFailed;
    return StoryException(
      code,
      '$what (${error.code}): ${error.message}',
      error,
      stackTrace,
    );
  }
  if (error is FileSystemException && _isNoSpace(error.osError)) {
    return StoryException(
      StoryErrorCode.insufficientStorage,
      '$what: ${error.message}',
      error,
      stackTrace,
    );
  }
  return StoryException(
    StoryErrorCode.exportFailed,
    '$what failed',
    error,
    stackTrace,
  );
}

/// Whether [error] is the native `cancelled` failure.
bool isNativeCancellation(Object error) =>
    error is PlatformException && error.code == NativeErrorCodes.cancelled;

// ENOSPC is 28 on Linux/Android and Darwin.
bool _isNoSpace(OSError? error) => error?.errorCode == 28;
