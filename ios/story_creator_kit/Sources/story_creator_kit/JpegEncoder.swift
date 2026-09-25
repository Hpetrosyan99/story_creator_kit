import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encodes straight RGBA pixels as a JPEG file.
enum JpegEncoder {
  static func encode(_ request: JpegEncodeRequest) throws -> NativeExportResult {
    let width = Int(request.width)
    let height = Int(request.height)
    let bytes = request.rgba.data
    guard width > 0, height > 0 else {
      throw storyError(.invalidInput, "Invalid JPEG size \(width)x\(height)")
    }
    guard bytes.count == width * height * 4 else {
      throw storyError(
        .invalidInput, "Expected \(width * height * 4) RGBA bytes, got \(bytes.count)")
    }
    guard (1...100).contains(request.quality) else {
      throw storyError(.invalidInput, "JPEG quality must be 1–100, got \(request.quality)")
    }
    let url = try prepareOutput(request.outputPath)
    try requireFreeSpace(Int64(bytes.count / 4) + 1_000_000, at: url)

    // The frame is opaque; alpha is ignored rather than premultiplied.
    guard let provider = CGDataProvider(data: bytes as CFData),
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else {
      throw storyError(.encoder, "Could not create an image from the pixels")
    }
    try writeJpeg(image, to: url, quality: Double(request.quality) / 100)
    return NativeExportResult(
      path: request.outputPath,
      width: Int64(width),
      height: Int64(height),
      fileSizeBytes: fileSize(url),
      durationMs: nil
    )
  }

  static func writeJpeg(_ image: CGImage, to url: URL, quality: Double) throws {
    guard
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
    else {
      throw storyError(.io, "Cannot create \(url.path)")
    }
    let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
    CGImageDestinationAddImage(destination, image, options as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      deleteQuietly(url)
      if let values = try? url.deletingLastPathComponent().resourceValues(
        forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
        let free = values.volumeAvailableCapacityForImportantUsage, free < 1_000_000
      {
        throw storyError(.noSpace, "Not enough free space to write \(url.lastPathComponent)")
      }
      throw storyError(.io, "Writing \(url.lastPathComponent) failed")
    }
  }
}
