@preconcurrency import AVFoundation
import Foundation

/// Peak levels of a file's audio, decoded with AVAssetReader.
enum WaveformExtractor {
  /// Decoding rate; plenty for peaks and keeps decoding cheap.
  private static let sampleRate = 8_000.0

  static func extract(path: String, buckets: Int) async throws -> [Double] {
    guard buckets > 0, buckets <= 100_000 else {
      throw storyError(.invalidInput, "buckets must be 1–100000, got \(buckets)")
    }
    let url = try requireReadableFile(path, what: "Audio file")
    let asset = AVURLAsset(url: url)
    let tracks: [AVAssetTrack]
    let duration: CMTime
    do {
      tracks = try await asset.loadTracks(withMediaType: .audio)
      duration = try await asset.load(.duration)
    } catch {
      throw storyError(
        .unsupportedMedia, "Cannot read audio: \(url.lastPathComponent)",
        (error as NSError).localizedDescription)
    }
    guard let track = tracks.first else {
      // A video without sound: silence.
      return Array(repeating: 0, count: buckets)
    }
    return try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          continuation.resume(
            returning: try decodePeaks(asset: asset, track: track, duration: duration, buckets: buckets))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private static func decodePeaks(
    asset: AVAsset, track: AVAssetTrack, duration: CMTime, buckets: Int
  ) throws -> [Double] {
    let reader: AVAssetReader
    do {
      reader = try AVAssetReader(asset: asset)
    } catch {
      throw mapStoryError(error, context: "Waveform")
    }
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else {
      throw storyError(.unsupportedMedia, "Audio track cannot be decoded")
    }
    reader.add(output)
    guard reader.startReading() else {
      throw mapStoryError(
        reader.error ?? storyError(.unsupportedMedia, "Audio decoding failed"), context: "Waveform")
    }
    let seconds = duration.isNumeric && duration.seconds > 0 ? duration.seconds : 1
    let totalSamples = max(1.0, seconds * sampleRate)
    var peaks = [Double](repeating: 0, count: buckets)
    var index = 0.0
    while let buffer = output.copyNextSampleBuffer() {
      guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
      var length = 0
      var pointer: UnsafeMutablePointer<Int8>?
      guard
        CMBlockBufferGetDataPointer(
          block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
          dataPointerOut: &pointer) == kCMBlockBufferNoErr, let pointer
      else { continue }
      let count = length / 2
      pointer.withMemoryRebound(to: Int16.self, capacity: count) { samples in
        for i in 0..<count {
          let bucket = min(buckets - 1, Int(index / totalSamples * Double(buckets)))
          let level = abs(Double(samples[i])) / 32768
          if level > peaks[bucket] {
            peaks[bucket] = level
          }
          index += 1
        }
      }
    }
    if reader.status == .failed {
      throw mapStoryError(reader.error ?? storyError(.unknown, "Waveform"), context: "Waveform")
    }
    return peaks.map { min(1, $0) }
  }
}
