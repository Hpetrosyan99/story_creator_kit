@preconcurrency import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads dimensions, duration, rotation and tracks of images and videos.
enum MediaProber {
  static func probe(path: String) async throws -> NativeMediaProbe {
    let url = try requireReadableFile(path, what: "Media file")
    let size = fileSize(url)
    if let image = probeImage(url: url, fileSize: size) {
      return image
    }
    return try await probeAsset(url: url, fileSize: size)
  }

  /// Image facts, or nil when [url] is not an image.
  static func probeImage(url: URL, fileSize: Int64) -> NativeMediaProbe? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let type = CGImageSourceGetType(source) as String?,
      let utType = UTType(type), utType.conforms(to: .image),
      CGImageSourceGetCount(source) > 0,
      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
      let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
    else {
      return nil
    }
    let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    let swaps = orientation >= 5 && orientation <= 8
    return NativeMediaProbe(
      width: Int64(swaps ? height : width),
      height: Int64(swaps ? width : height),
      fileSizeBytes: fileSize,
      rotationDegrees: Int64(rotationForExif(orientation)),
      hasVideo: false,
      hasAudio: false,
      durationMs: nil,
      videoCodec: nil,
      audioCodec: nil,
      frameRate: nil
    )
  }

  static func rotationForExif(_ orientation: Int) -> Int {
    switch orientation {
    case 3, 4: return 180
    case 5, 6: return 90
    case 7, 8: return 270
    default: return 0
    }
  }

  private static func probeAsset(url: URL, fileSize: Int64) async throws -> NativeMediaProbe {
    let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    let duration: CMTime
    let videoTracks: [AVAssetTrack]
    let audioTracks: [AVAssetTrack]
    do {
      duration = try await asset.load(.duration)
      videoTracks = try await asset.loadTracks(withMediaType: .video)
      audioTracks = try await asset.loadTracks(withMediaType: .audio)
    } catch {
      throw storyError(
        .unsupportedMedia, "Cannot read media: \(url.lastPathComponent)",
        (error as NSError).localizedDescription)
    }
    if videoTracks.isEmpty && audioTracks.isEmpty {
      throw storyError(.unsupportedMedia, "No audio or video track: \(url.lastPathComponent)")
    }
    var width: Int64 = 0
    var height: Int64 = 0
    var rotation = 0
    var videoCodec: String?
    var frameRate: Double?
    if let video = videoTracks.first {
      let (naturalSize, transform, fps, formats) = try await video.load(
        .naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions)
      let display = naturalSize.applying(transform)
      width = Int64(abs(display.width).rounded())
      height = Int64(abs(display.height).rounded())
      rotation = VideoOrientation.rotationDegrees(transform)
      videoCodec = formats.first.map { fourCC(CMFormatDescriptionGetMediaSubType($0)) }
      frameRate = fps > 0 ? Double(fps) : nil
    }
    var audioCodec: String?
    if let audio = audioTracks.first {
      let formats = try await audio.load(.formatDescriptions)
      audioCodec = formats.first.map { fourCC(CMFormatDescriptionGetMediaSubType($0)) }
    }
    let seconds = duration.isNumeric ? duration.seconds : 0
    return NativeMediaProbe(
      width: width,
      height: height,
      fileSizeBytes: fileSize,
      rotationDegrees: Int64(rotation),
      hasVideo: !videoTracks.isEmpty,
      hasAudio: !audioTracks.isEmpty,
      durationMs: Int64((seconds * 1000).rounded()),
      videoCodec: videoCodec,
      audioCodec: audioCodec,
      frameRate: frameRate
    )
  }

  static func fourCC(_ code: FourCharCode) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
    let printable = bytes.allSatisfy { $0 >= 0x20 && $0 < 0x7F }
    guard printable, let text = String(bytes: bytes, encoding: .ascii) else {
      return String(code)
    }
    return text.trimmingCharacters(in: .whitespaces)
  }
}

/// Orientation helpers for a track's `preferredTransform`.
enum VideoOrientation {
  /// Clockwise display rotation in degrees (0, 90, 180, 270).
  static func rotationDegrees(_ t: CGAffineTransform) -> Int {
    let degrees = Int((atan2(Double(t.b), Double(t.a)) * 180 / .pi).rounded())
    return ((degrees % 360) + 360) % 360
  }

  /// The image orientation that turns decoded frames into display frames.
  static func imageOrientation(_ t: CGAffineTransform) -> CGImagePropertyOrientation {
    let a = Int(t.a.rounded())
    let b = Int(t.b.rounded())
    let c = Int(t.c.rounded())
    let d = Int(t.d.rounded())
    switch (a, b, c, d) {
    case (0, 1, -1, 0): return .right
    case (-1, 0, 0, -1): return .down
    case (0, -1, 1, 0): return .left
    case (-1, 0, 0, 1): return .upMirrored
    case (1, 0, 0, -1): return .downMirrored
    case (0, 1, 1, 0): return .leftMirrored
    case (0, -1, -1, 0): return .rightMirrored
    default: return .up
    }
  }
}
