@preconcurrency import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

/// Encodes one composed frame as a video of a fixed length, with optional
/// music (photo story with music).
final class StillVideoExporter {
  private let request: StillVideoExportRequest
  private let job: ExportJob
  private let progress: (Double) -> Void

  init(request: StillVideoExportRequest, job: ExportJob, progress: @escaping (Double) -> Void) {
    self.request = request
    self.job = job
    self.progress = progress
  }

  func run() async throws -> NativeExportResult {
    let output = request.output
    try OutputSettings.validate(output)
    guard request.durationMs > 0 else {
      throw storyError(.invalidInput, "durationMs must be positive, got \(request.durationMs)")
    }
    let frameURL = try requireReadableFile(request.framePath, what: "Frame image")
    let outputURL = try prepareOutput(output.path)
    let duration = cmTime(ms: request.durationMs)
    try requireFreeSpace(
      OutputSettings.estimatedBytes(output, seconds: duration.seconds), at: outputURL)
    let pixelBuffer = try makePixelBuffer(
      frameURL: frameURL, width: Int(output.width), height: Int(output.height))
    try job.throwIfCancelled()

    // Music reader.
    var readers: [AVAssetReader] = []
    var audioOutput: AVAssetReaderAudioMixOutput?
    if let music = request.music, music.volume > 0 {
      let composition = AVMutableComposition()
      if let track = try await insertMusic(music, into: composition, maxDuration: duration) {
        let reader: AVAssetReader
        do {
          reader = try AVAssetReader(asset: composition)
        } catch {
          throw mapStoryError(error, context: "Decoding music")
        }
        let mixOutput = AVAssetReaderAudioMixOutput(
          audioTracks: [track], audioSettings: OutputSettings.pcm)
        let mix = AVMutableAudioMix()
        mix.inputParameters = [volumeParameters(track, volume: music.volume)]
        mixOutput.audioMix = mix
        mixOutput.alwaysCopiesSampleData = false
        if reader.canAdd(mixOutput) {
          reader.add(mixOutput)
          readers.append(reader)
          audioOutput = mixOutput
        }
      }
    }

    // Writer.
    let writer: AVAssetWriter
    do {
      writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    } catch {
      throw mapStoryError(error, context: "Creating the output")
    }
    writer.shouldOptimizeForNetworkUse = true
    let videoInput = AVAssetWriterInput(
      mediaType: .video, outputSettings: OutputSettings.video(output))
    videoInput.expectsMediaDataInRealTime = false
    guard writer.canAdd(videoInput) else {
      throw storyError(.encoder, "The encoder rejected the video settings")
    }
    writer.add(videoInput)
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: videoInput,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: Int(output.width),
        kCVPixelBufferHeightKey as String: Int(output.height),
      ])
    var audioInput: AVAssetWriterInput?
    if audioOutput != nil {
      let input = AVAssetWriterInput(mediaType: .audio, outputSettings: OutputSettings.audio)
      input.expectsMediaDataInRealTime = false
      if writer.canAdd(input) {
        writer.add(input)
        audioInput = input
      }
    }

    let fps = Int32(output.frameRate)
    let frameCount = max(1, Int((duration.seconds * Double(fps)).rounded(.up)))
    var frame = 0
    let pipeline = WriterPipeline(
      writer: writer, outputURL: outputURL, job: job, duration: duration, progress: progress)
    try await pipeline.run(
      readers: readers,
      video: (
        input: videoInput,
        step: {
          guard frame < frameCount else { return .finished }
          let time = CMTime(value: CMTimeValue(frame), timescale: fps)
          frame += 1
          return adaptor.append(pixelBuffer, withPresentationTime: time)
            ? .appended(time) : .failed(storyError(.encoder, "Appending a frame failed"))
        }
      ),
      audio: audioInput.flatMap { input in audioOutput.map { (input: input, output: $0) } }
    )

    return NativeExportResult(
      path: output.path,
      width: output.width,
      height: output.height,
      fileSizeBytes: fileSize(outputURL),
      durationMs: request.durationMs
    )
  }

  /// Decodes [frameURL] and draws it scaled into a BGRA buffer of the output
  /// size.
  private func makePixelBuffer(frameURL: URL, width: Int, height: Int) throws -> CVPixelBuffer {
    guard let source = CGImageSourceCreateWithURL(frameURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw storyError(.invalidInput, "Frame is not a readable image: \(frameURL.lastPathComponent)")
    }
    var buffer: CVPixelBuffer?
    let attributes: [String: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
      attributes as CFDictionary, &buffer)
    guard status == kCVReturnSuccess, let buffer else {
      throw storyError(.encoder, "Cannot allocate a frame buffer (\(status))")
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard
      let context = CGContext(
        data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
          | CGBitmapInfo.byteOrder32Little.rawValue)
    else {
      throw storyError(.encoder, "Cannot draw the frame")
    }
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return buffer
  }
}
