// Extracts evenly spaced frames of a video as PNGs (for demo GIFs).
//   swift tool/extract_frames.swift <video.mp4> <out-dir> <fps> <max-width>
import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 5, let fps = Double(args[3]), let maxWidth = Double(args[4]) else {
  print("usage: extract_frames.swift <video> <out-dir> <fps> <max-width>")
  exit(1)
}
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let outDir = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.maximumSize = CGSize(width: maxWidth, height: maxWidth * 4)
generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 60)
generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)

let semaphore = DispatchSemaphore(value: 0)
Task {
  let duration = try await asset.load(.duration).seconds
  let count = Int(duration * fps)
  for i in 0..<count {
    let time = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
    let image = try await generator.image(at: time).image
    let url = outDir.appendingPathComponent(String(format: "f%05d.png", i))
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
  }
  print("\(count) frames")
  semaphore.signal()
}
semaphore.wait()
