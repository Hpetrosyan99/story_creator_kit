@preconcurrency import AVFoundation
import Foundation

/// Error codes shared with the Dart side (see `pigeons/story_native_api.dart`).
enum StoryErrorCode: String {
  case cancelled
  case invalidInput = "invalid_input"
  case unsupportedMedia = "unsupported_media"
  case noSpace = "no_space"
  case encoder
  case io
  case unknown
}

func storyError(_ code: StoryErrorCode, _ message: String, _ details: String? = nil) -> PigeonError {
  PigeonError(code: code.rawValue, message: message, details: details)
}

/// Maps any thrown error to a `PigeonError` with one of the documented codes.
func mapStoryError(_ error: Error, context: String) -> PigeonError {
  if let pigeon = error as? PigeonError {
    return pigeon
  }
  let ns = error as NSError
  let details = "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
  if isOutOfSpace(ns) {
    return storyError(.noSpace, "\(context): not enough free space", details)
  }
  if ns.domain == AVFoundationErrorDomain {
    switch AVError.Code(rawValue: ns.code) {
    case .fileFormatNotRecognized, .decoderNotFound, .decodeFailed, .failedToLoadMediaData,
      .contentIsUnavailable, .noDataCaptured, .formatUnsupported:
      return storyError(.unsupportedMedia, "\(context): media cannot be decoded", details)
    case .encoderNotFound, .encoderTemporarilyUnavailable, .invalidVideoComposition,
      .exportFailed, .operationNotAllowed, .videoCompositorFailed:
      return storyError(.encoder, "\(context): encoding failed", details)
    case .noLongerPlayable, .fileFailedToParse:
      return storyError(.unsupportedMedia, "\(context): media cannot be read", details)
    default:
      break
    }
  }
  if ns.domain == NSCocoaErrorDomain {
    switch ns.code {
    case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
      return storyError(.invalidInput, "\(context): file not found", details)
    case NSFileReadCorruptFileError, NSFileReadUnknownError, NSFileWriteUnknownError,
      NSFileWriteNoPermissionError, NSFileReadNoPermissionError, NSFileWriteInvalidFileNameError:
      return storyError(.io, "\(context): file access failed", details)
    default:
      break
    }
  }
  if ns.domain == NSPOSIXErrorDomain {
    return storyError(.io, "\(context): file access failed", details)
  }
  return storyError(.unknown, "\(context) failed", details)
}

private func isOutOfSpace(_ error: NSError) -> Bool {
  if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError {
    return true
  }
  if error.domain == NSPOSIXErrorDomain && error.code == Int(ENOSPC) {
    return true
  }
  if error.domain == AVFoundationErrorDomain && error.code == AVError.diskFull.rawValue {
    return true
  }
  if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
    return isOutOfSpace(underlying)
  }
  return false
}

/// Checks that [path] names an existing, readable regular file.
func requireReadableFile(_ path: String, what: String) throws -> URL {
  var isDirectory: ObjCBool = false
  guard !path.isEmpty, FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
    !isDirectory.boolValue
  else {
    throw storyError(.invalidInput, "\(what) does not exist: \(path)")
  }
  guard FileManager.default.isReadableFile(atPath: path) else {
    throw storyError(.io, "\(what) is not readable: \(path)")
  }
  return URL(fileURLWithPath: path)
}

/// Prepares [path] for writing: creates the parent directory and removes an
/// existing file.
func prepareOutput(_ path: String) throws -> URL {
  guard !path.isEmpty else {
    throw storyError(.invalidInput, "Output path is empty")
  }
  let url = URL(fileURLWithPath: path)
  do {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: path) {
      try FileManager.default.removeItem(at: url)
    }
  } catch {
    throw mapStoryError(error, context: "Preparing output")
  }
  return url
}

/// Size of the file at [url] in bytes, or 0.
func fileSize(_ url: URL) -> Int64 {
  let values = try? url.resourceValues(forKeys: [.fileSizeKey])
  return Int64(values?.fileSize ?? 0)
}

/// Throws `no_space` when the volume holding [url] has less than [bytes]
/// free. Uses the disk-space API for reason E174.1 (checking that there is
/// enough space to write files).
func requireFreeSpace(_ bytes: Int64, at url: URL) throws {
  let directory = url.deletingLastPathComponent()
  guard
    let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
    let available = values.volumeAvailableCapacityForImportantUsage
  else {
    return
  }
  if available < bytes {
    throw storyError(
      .noSpace, "Not enough free space: need \(bytes) bytes, have \(available)")
  }
}

func deleteQuietly(_ url: URL) {
  try? FileManager.default.removeItem(at: url)
}
