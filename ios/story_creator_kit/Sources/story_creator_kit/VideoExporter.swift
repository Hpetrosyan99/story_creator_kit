@preconcurrency import AVFoundation
import CoreImage
import Foundation

/// Exports a source video onto the story canvas (see `VideoExportRequest`).
///
/// Pipeline: AVMutableComposition (trimmed video, original audio, music
/// segment) → AVAssetReader with a custom compositor and an audio mix →
/// AVAssetWriter (H.264 High, AAC-LC). Reader/writer is used instead of
/// AVAssetExportSession so bitrate, frame rate and audio format are exact,
/// and progress/cancel work the same on iOS 16–27.
final class VideoExporter {
  private let request: VideoExportRequest
  private let job: ExportJob
  private let progress: (Double) -> Void

  init(request: VideoExportRequest, job: ExportJob, progress: @escaping (Double) -> Void) {
    self.request = request
    self.job = job
    self.progress = progress
  }

  func run() async throws -> NativeExportResult {
    let output = request.output
    try OutputSettings.validate(output)
    try validateRequest()
    let sourceURL = try requireReadableFile(request.sourcePath, what: "Source video")
    let outputURL = try prepareOutput(output.path)
    try job.throwIfCancelled()

    let asset = AVURLAsset(
      url: sourceURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    let assetDuration: CMTime
    let videoTracks: [AVAssetTrack]
    let audioTracks: [AVAssetTrack]
    do {
      assetDuration = try await asset.load(.duration)
      videoTracks = try await asset.loadTracks(withMediaType: .video)
      audioTracks = try await asset.loadTracks(withMediaType: .audio)
    } catch {
      throw storyError(
        .unsupportedMedia, "Cannot read the source video",
        (error as NSError).localizedDescription)
    }
    guard let sourceVideo = videoTracks.first else {
      throw storyError(.unsupportedMedia, "The source has no video track")
    }
    let transform = try await sourceVideo.load(.preferredTransform)

    let start = cmTime(ms: request.trimStartMs)
    let end = CMTimeMinimum(cmTime(ms: request.trimEndMs), assetDuration)
    guard CMTimeCompare(end, start) > 0 else {
      throw storyError(
        .invalidInput,
        "Trim \(request.trimStartMs)–\(request.trimEndMs) ms is outside the video (\(milliseconds(assetDuration)) ms)"
      )
    }
    let duration = CMTimeSubtract(end, start)
    try requireFreeSpace(
      OutputSettings.estimatedBytes(output, seconds: duration.seconds), at: outputURL)

    // Composition.
    let composition = AVMutableComposition()
    guard
      let videoTrack = composition.addMutableTrack(
        withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    else {
      throw storyError(.encoder, "Cannot add a video track")
    }
    do {
      try videoTrack.insertTimeRange(
        CMTimeRange(start: start, end: end), of: sourceVideo, at: .zero)
    } catch {
      throw mapStoryError(error, context: "Trimming the video")
    }
    var mixTracks: [AVAssetTrack] = []
    var mixParameters: [AVMutableAudioMixInputParameters] = []
    if request.originalVolume > 0, let sourceAudio = audioTracks.first,
      let audioTrack = composition.addMutableTrack(
        withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
    {
      do {
        try audioTrack.insertTimeRange(
          CMTimeRange(start: start, end: end), of: sourceAudio, at: .zero)
        mixTracks.append(audioTrack)
        mixParameters.append(volumeParameters(audioTrack, volume: request.originalVolume))
      } catch {
        composition.removeTrack(audioTrack)
      }
    }
    if let music = request.music, music.volume > 0,
      let musicTrack = try await insertMusic(music, into: composition, maxDuration: duration)
    {
      mixTracks.append(musicTrack)
      mixParameters.append(volumeParameters(musicTrack, volume: music.volume))
    }
    try job.throwIfCancelled()

    // Video composition.
    let renderSize = CGSize(width: Int(output.width), height: Int(output.height))
    let spec = StoryFrameSpec(
      trackID: videoTrack.trackID,
      sourceTransform: transform,
      videoRect: CGRect(
        x: request.videoRect.left, y: request.videoRect.top,
        width: request.videoRect.width, height: request.videoRect.height),
      mirror: request.mirror,
      colorMatrix: request.colorMatrix,
      overlay: try loadOverlay(size: renderSize),
      renderSize: renderSize
    )
    let instruction = StoryCompositionInstruction(
      timeRange: CMTimeRange(start: .zero, duration: duration), spec: spec)
    let videoComposition = makeStoryVideoComposition(
      instruction: instruction, renderSize: renderSize, frameRate: Int(output.frameRate))

    // Reader.
    let reader: AVAssetReader
    do {
      reader = try AVAssetReader(asset: composition)
    } catch {
      throw mapStoryError(error, context: "Decoding")
    }
    reader.timeRange = CMTimeRange(start: .zero, duration: duration)
    let videoOutput = AVAssetReaderVideoCompositionOutput(
      videoTracks: [videoTrack],
      videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    videoOutput.videoComposition = videoComposition
    videoOutput.alwaysCopiesSampleData = false
    guard reader.canAdd(videoOutput) else {
      throw storyError(.unsupportedMedia, "The video cannot be decoded")
    }
    reader.add(videoOutput)
    var audioOutput: AVAssetReaderAudioMixOutput?
    if !mixTracks.isEmpty {
      let mixOutput = AVAssetReaderAudioMixOutput(
        audioTracks: mixTracks, audioSettings: OutputSettings.pcm)
      let mix = AVMutableAudioMix()
      mix.inputParameters = mixParameters
      mixOutput.audioMix = mix
      mixOutput.alwaysCopiesSampleData = false
      if reader.canAdd(mixOutput) {
        reader.add(mixOutput)
        audioOutput = mixOutput
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
    var audioInput: AVAssetWriterInput?
    if audioOutput != nil {
      let input = AVAssetWriterInput(mediaType: .audio, outputSettings: OutputSettings.audio)
      input.expectsMediaDataInRealTime = false
      if writer.canAdd(input) {
        writer.add(input)
        audioInput = input
      }
    }

    let pipeline = WriterPipeline(
      writer: writer, outputURL: outputURL, job: job, duration: duration, progress: progress)
    try await pipeline.run(
      readers: [reader],
      video: (
        input: videoInput,
        step: {
          guard let sample = videoOutput.copyNextSampleBuffer() else { return .finished }
          let time = CMSampleBufferGetPresentationTimeStamp(sample)
          return videoInput.append(sample)
            ? .appended(time) : .failed(storyError(.encoder, "Appending video failed"))
        }
      ),
      audio: audioInput.flatMap { input in audioOutput.map { (input: input, output: $0) } }
    )

    return NativeExportResult(
      path: output.path,
      width: output.width,
      height: output.height,
      fileSizeBytes: fileSize(outputURL),
      durationMs: milliseconds(duration)
    )
  }

  private func validateRequest() throws {
    let rect = request.videoRect
    guard rect.width > 0, rect.height > 0, rect.width.isFinite, rect.height.isFinite,
      rect.left.isFinite, rect.top.isFinite
    else {
      throw storyError(.invalidInput, "Invalid videoRect \(rect)")
    }
    guard request.trimStartMs >= 0, request.trimEndMs > request.trimStartMs else {
      throw storyError(
        .invalidInput, "Invalid trim \(request.trimStartMs)–\(request.trimEndMs) ms")
    }
    if let matrix = request.colorMatrix, matrix.count != 20 {
      throw storyError(.invalidInput, "colorMatrix needs 20 values, got \(matrix.count)")
    }
    guard request.originalVolume >= 0 else {
      throw storyError(.invalidInput, "originalVolume must be ≥ 0")
    }
  }

  private func loadOverlay(size: CGSize) throws -> CIImage? {
    guard let path = request.overlayPngPath else {
      return nil
    }
    let url = try requireReadableFile(path, what: "Overlay image")
    guard let image = CIImage(contentsOf: url) else {
      throw storyError(.invalidInput, "Overlay is not a readable image: \(url.lastPathComponent)")
    }
    let extent = image.extent
    if extent.size == size && extent.origin == .zero {
      return image
    }
    return image.transformed(
      by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
        .concatenating(
          CGAffineTransform(
            scaleX: size.width / max(1, extent.width), y: size.height / max(1, extent.height))))
  }
}
