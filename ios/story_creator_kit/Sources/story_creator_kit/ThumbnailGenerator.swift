@preconcurrency import AVFoundation
import Foundation
import ImageIO

/// JPEG frames of a video (or a downscaled copy of an image).
enum ThumbnailGenerator {
  static func generate(
    path: String, timesMs: [Int64], maxWidth: Int, outputDirectory: String
  ) async throws -> [String] {
    guard maxWidth > 0 else {
      throw storyError(.invalidInput, "maxWidth must be positive")
    }
    let url = try requireReadableFile(path, what: "Media file")
    let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      throw mapStoryError(error, context: "Thumbnails")
    }
    if timesMs.isEmpty {
      return []
    }
    let stem = "thumb_\(UUID().uuidString.prefix(8))"
    if MediaProber.probeImage(url: url, fileSize: 0) != nil {
      return try imageThumbnails(
        url: url, count: timesMs.count, maxWidth: maxWidth, directory: directory, stem: stem)
    }
    return try await videoThumbnails(
      url: url, timesMs: timesMs, maxWidth: maxWidth, directory: directory, stem: stem)
  }

  private static func videoThumbnails(
    url: URL, timesMs: [Int64], maxWidth: Int, directory: URL, stem: String
  ) async throws -> [String] {
    let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    let duration: CMTime
    let tracks: [AVAssetTrack]
    do {
      duration = try await asset.load(.duration)
      tracks = try await asset.loadTracks(withMediaType: .video)
    } catch {
      throw storyError(
        .unsupportedMedia, "Cannot read video: \(url.lastPathComponent)",
        (error as NSError).localizedDescription)
    }
    guard let track = tracks.first else {
      throw storyError(.unsupportedMedia, "No video track: \(url.lastPathComponent)")
    }
    let fps = (try? await track.load(.nominalFrameRate)) ?? 30
    let frame = CMTime(value: 1, timescale: CMTimeScale(max(1, fps.rounded())))
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: maxWidth, height: maxWidth * 8)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let lastFrame = CMTimeSubtract(duration, frame)
    var paths: [String] = []
    for (i, ms) in timesMs.enumerated() {
      var time = CMTime(value: max(0, ms), timescale: 1000)
      if lastFrame.isNumeric && CMTimeCompare(time, lastFrame) > 0 {
        time = CMTimeMaximum(.zero, lastFrame)
      }
      let image: CGImage
      do {
        image = try await generator.image(at: time).image
      } catch {
        throw storyError(
          .unsupportedMedia, "Cannot decode a frame at \(ms) ms",
          (error as NSError).localizedDescription)
      }
      let out = directory.appendingPathComponent("\(stem)_\(i).jpg")
      try JpegEncoder.writeJpeg(image, to: out, quality: 0.85)
      paths.append(out.path)
    }
    return paths
  }

  private static func imageThumbnails(
    url: URL, count: Int, maxWidth: Int, directory: URL, stem: String
  ) throws -> [String] {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      throw storyError(.unsupportedMedia, "Cannot read image: \(url.lastPathComponent)")
    }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxWidth,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else {
      throw storyError(.unsupportedMedia, "Cannot decode image: \(url.lastPathComponent)")
    }
    let out = directory.appendingPathComponent("\(stem)_0.jpg")
    try JpegEncoder.writeJpeg(image, to: out, quality: 0.85)
    return Array(repeating: out.path, count: count)
  }
}
