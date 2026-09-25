package com.mabrook.story_creator_kit

import android.os.StatFs
import androidx.media3.transformer.ExportException
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException

/** Error codes shared with the Dart side (see `pigeons/story_native_api.dart`). */
internal object ErrorCodes {
  const val CANCELLED = "cancelled"
  const val INVALID_INPUT = "invalid_input"
  const val UNSUPPORTED_MEDIA = "unsupported_media"
  const val NO_SPACE = "no_space"
  const val ENCODER = "encoder"
  const val IO = "io"
  const val UNKNOWN = "unknown"
}

internal fun storyError(code: String, message: String, details: String? = null) =
  FlutterError(code, message, details)

/** Maps any throwable to a [FlutterError] with one of the documented codes. */
internal fun mapError(error: Throwable, context: String): FlutterError {
  if (error is FlutterError) return error
  val details = "${error.javaClass.simpleName}: ${error.message}"
  if (isOutOfSpace(error)) {
    return storyError(ErrorCodes.NO_SPACE, "$context: not enough free space", details)
  }
  return when (error) {
    is ExportException -> storyError(exportCode(error), "$context: ${error.errorCodeName}", details)
    is FileNotFoundException -> storyError(ErrorCodes.INVALID_INPUT, "$context: file not found", details)
    is IOException -> storyError(ErrorCodes.IO, "$context: file access failed", details)
    is SecurityException -> storyError(ErrorCodes.IO, "$context: no permission", details)
    is IllegalArgumentException -> storyError(ErrorCodes.INVALID_INPUT, "$context: invalid input", details)
    else -> storyError(ErrorCodes.UNKNOWN, "$context failed", details)
  }
}

private fun exportCode(error: ExportException): String = when (error.errorCode) {
  ExportException.ERROR_CODE_IO_FILE_NOT_FOUND -> ErrorCodes.INVALID_INPUT
  ExportException.ERROR_CODE_IO_NO_PERMISSION,
  ExportException.ERROR_CODE_IO_UNSPECIFIED,
  ExportException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE -> ErrorCodes.IO
  ExportException.ERROR_CODE_DECODER_INIT_FAILED,
  ExportException.ERROR_CODE_DECODING_FAILED,
  ExportException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED -> ErrorCodes.UNSUPPORTED_MEDIA
  ExportException.ERROR_CODE_ENCODER_INIT_FAILED,
  ExportException.ERROR_CODE_ENCODING_FAILED,
  ExportException.ERROR_CODE_ENCODING_FORMAT_UNSUPPORTED,
  ExportException.ERROR_CODE_VIDEO_FRAME_PROCESSING_FAILED,
  ExportException.ERROR_CODE_AUDIO_PROCESSING_FAILED,
  ExportException.ERROR_CODE_MUXING_FAILED,
  ExportException.ERROR_CODE_MUXING_TIMEOUT,
  ExportException.ERROR_CODE_MUXING_APPEND -> ErrorCodes.ENCODER
  else -> ErrorCodes.UNKNOWN
}

private fun isOutOfSpace(error: Throwable?): Boolean {
  var current = error
  var depth = 0
  while (current != null && depth < 8) {
    val message = current.message ?: ""
    if (message.contains("ENOSPC") || message.contains("No space left", ignoreCase = true)) {
      return true
    }
    current = current.cause
    depth++
  }
  return false
}

/** Checks that [path] is an existing readable file. */
internal fun requireReadableFile(path: String, what: String): File {
  val file = File(path)
  if (path.isEmpty() || !file.isFile) {
    throw storyError(ErrorCodes.INVALID_INPUT, "$what does not exist: $path")
  }
  if (!file.canRead()) {
    throw storyError(ErrorCodes.IO, "$what is not readable: $path")
  }
  return file
}

/** Creates the parent directory of [path] and removes an existing file. */
internal fun prepareOutput(path: String): File {
  if (path.isEmpty()) throw storyError(ErrorCodes.INVALID_INPUT, "Output path is empty")
  val file = File(path)
  val parent = file.parentFile
  if (parent != null && !parent.isDirectory && !parent.mkdirs()) {
    throw storyError(ErrorCodes.IO, "Cannot create ${parent.path}")
  }
  if (file.exists() && !file.delete()) {
    throw storyError(ErrorCodes.IO, "Cannot replace $path")
  }
  return file
}

/** Throws `no_space` when the volume holding [file] has less than [bytes] free. */
internal fun requireFreeSpace(bytes: Long, file: File) {
  val dir = file.parentFile ?: return
  val available = try {
    StatFs(dir.path).availableBytes
  } catch (_: IllegalArgumentException) {
    return
  }
  if (available < bytes) {
    throw storyError(ErrorCodes.NO_SPACE, "Not enough free space: need $bytes bytes, have $available")
  }
}
