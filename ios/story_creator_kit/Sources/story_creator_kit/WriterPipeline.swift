@preconcurrency import AVFoundation
import Foundation

/// Output of one pump step.
enum PumpStep {
  /// A sample was appended; its presentation time.
  case appended(CMTime)
  /// The source is exhausted.
  case finished
  /// Appending failed.
  case failed(Error)
}

/// Encoder settings shared by the video exporters.
enum OutputSettings {
  static func video(_ output: NativeOutput) -> [String: Any] {
    let fps = Int(output.frameRate)
    return [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: Int(output.width),
      AVVideoHeightKey: Int(output.height),
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: Int(output.videoBitrate),
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoExpectedSourceFrameRateKey: fps,
        AVVideoMaxKeyFrameIntervalKey: max(1, fps * 2),
      ],
      AVVideoColorPropertiesKey: [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
      ],
    ]
  }

  /// AAC-LC 128 kbps, 44.1 kHz stereo.
  static let audio: [String: Any] = [
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVSampleRateKey: 44_100,
    AVNumberOfChannelsKey: 2,
    AVEncoderBitRateKey: 128_000,
  ]

  /// What the reader decodes and mixes audio into before AAC encoding.
  static let pcm: [String: Any] = [
    AVFormatIDKey: kAudioFormatLinearPCM,
    AVSampleRateKey: 44_100,
    AVNumberOfChannelsKey: 2,
    AVLinearPCMBitDepthKey: 16,
    AVLinearPCMIsFloatKey: false,
    AVLinearPCMIsBigEndianKey: false,
    AVLinearPCMIsNonInterleaved: false,
  ]

  static func validate(_ output: NativeOutput) throws {
    guard output.width > 0, output.height > 0, output.width <= 8192, output.height <= 8192 else {
      throw storyError(.invalidInput, "Invalid output size \(output.width)x\(output.height)")
    }
    guard output.width % 2 == 0, output.height % 2 == 0 else {
      throw storyError(.invalidInput, "Output size must be even, got \(output.width)x\(output.height)")
    }
    guard (1...120).contains(output.frameRate) else {
      throw storyError(.invalidInput, "Invalid frame rate \(output.frameRate)")
    }
    guard output.videoBitrate > 0 else {
      throw storyError(.invalidInput, "Invalid bitrate \(output.videoBitrate)")
    }
  }

  /// Bytes the file will roughly need, with headroom.
  static func estimatedBytes(_ output: NativeOutput, seconds: Double) -> Int64 {
    let bits = (Double(output.videoBitrate) + 128_000) * max(1, seconds)
    return Int64(bits / 8 * 1.2) + 5_000_000
  }
}

/// Moves samples into an AVAssetWriter and finishes, cancels or fails it.
final class WriterPipeline {
  private let writer: AVAssetWriter
  private let outputURL: URL
  private let job: ExportJob
  private let duration: CMTime
  private let progress: (Double) -> Void
  private let lock = NSLock()
  private var failure: Error?

  init(
    writer: AVAssetWriter, outputURL: URL, job: ExportJob, duration: CMTime,
    progress: @escaping (Double) -> Void
  ) {
    self.writer = writer
    self.outputURL = outputURL
    self.job = job
    self.duration = duration
    self.progress = progress
  }

  /// Runs until every input is finished. [readers] are cancelled on job
  /// cancellation and checked for failures.
  func run(
    readers: [AVAssetReader],
    video: (input: AVAssetWriterInput, step: () -> PumpStep),
    audio: (input: AVAssetWriterInput, output: AVAssetReaderOutput)?
  ) async throws {
    guard writer.startWriting() else {
      deleteQuietly(outputURL)
      throw mapStoryError(
        writer.error ?? storyError(.encoder, "The writer did not start"), context: "Encoding")
    }
    writer.startSession(atSourceTime: .zero)
    for reader in readers where reader.status == .unknown {
      guard reader.startReading() else {
        writer.cancelWriting()
        deleteQuietly(outputURL)
        throw mapStoryError(
          reader.error ?? storyError(.unsupportedMedia, "Reading the source failed"),
          context: "Decoding")
      }
    }
    job.whenCancelled {
      readers.forEach { $0.cancelReading() }
    }
    progress(0)

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      let group = DispatchGroup()
      let totalSeconds = max(0.001, duration.seconds)

      group.enter()
      pump(
        input: video.input, label: "video", group: group,
        step: video.step,
        onAppended: { [progress] time in
          progress(min(0.99, max(0, time.seconds / totalSeconds)))
        })

      if let audio {
        group.enter()
        let output = audio.output
        let input = audio.input
        pump(
          input: audio.input, label: "audio", group: group,
          step: {
            guard let sample = output.copyNextSampleBuffer() else { return .finished }
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            return input.append(sample)
              ? .appended(time) : .failed(storyError(.encoder, "Appending audio failed"))
          },
          onAppended: { _ in })
      }

      group.notify(queue: .global(qos: .userInitiated)) { [self] in
        finish(readers: readers, continuation: continuation)
      }
    }
    progress(1)
  }

  private func pump(
    input: AVAssetWriterInput, label: String, group: DispatchGroup,
    step: @escaping () -> PumpStep, onAppended: @escaping (CMTime) -> Void
  ) {
    let queue = DispatchQueue(label: "story_creator_kit.\(label)", qos: .userInitiated)
    var done = false
    input.requestMediaDataWhenReady(on: queue) { [self] in
      if done {
        return
      }
      var stop = false
      while !stop && input.isReadyForMoreMediaData {
        if job.isCancelled || hasFailed {
          stop = true
          break
        }
        switch step() {
        case .appended(let time):
          onAppended(time)
        case .finished:
          stop = true
        case .failed(let error):
          record(error)
          stop = true
        }
      }
      if stop || job.isCancelled || hasFailed {
        done = true
        input.markAsFinished()
        group.leave()
      }
    }
  }

  private var hasFailed: Bool {
    lock.lock()
    defer { lock.unlock() }
    return failure != nil
  }

  private func record(_ error: Error) {
    lock.lock()
    if failure == nil {
      failure = error
    }
    lock.unlock()
  }

  private func finish(readers: [AVAssetReader], continuation: CheckedContinuation<Void, Error>) {
    if job.isCancelled {
      writer.cancelWriting()
      deleteQuietly(outputURL)
      continuation.resume(throwing: storyError(.cancelled, "Export \(job.id) was cancelled"))
      return
    }
    lock.lock()
    var error = failure
    lock.unlock()
    if error == nil, let failed = readers.first(where: { $0.status == .failed }) {
      error = mapStoryError(
        failed.error ?? storyError(.unsupportedMedia, "Decoding failed"), context: "Decoding")
    }
    if error == nil, writer.status == .failed {
      error = mapStoryError(
        writer.error ?? storyError(.encoder, "Encoding failed"), context: "Encoding")
    }
    if let error {
      writer.cancelWriting()
      deleteQuietly(outputURL)
      continuation.resume(throwing: mapStoryError(error, context: "Export"))
      return
    }
    writer.endSession(atSourceTime: duration)
    writer.finishWriting { [self] in
      if job.isCancelled {
        deleteQuietly(outputURL)
        continuation.resume(throwing: storyError(.cancelled, "Export \(job.id) was cancelled"))
      } else if writer.status == .completed {
        continuation.resume()
      } else {
        deleteQuietly(outputURL)
        continuation.resume(
          throwing: mapStoryError(
            writer.error ?? storyError(.encoder, "Finishing the file failed"), context: "Encoding"))
      }
    }
  }
}

func cmTime(ms: Int64) -> CMTime {
  CMTime(value: max(0, ms), timescale: 1000)
}

func milliseconds(_ time: CMTime) -> Int64 {
  Int64((time.seconds * 1000).rounded())
}

/// Adds the [segment] of [asset]'s first audio track to [composition] at 0.
/// Returns the new composition track, or nil when there is no audio.
func insertMusic(
  _ music: NativeAudioTrack, into composition: AVMutableComposition, maxDuration: CMTime
) async throws -> AVMutableCompositionTrack? {
  let url = try requireReadableFile(music.path, what: "Music file")
  let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
  let tracks: [AVAssetTrack]
  let duration: CMTime
  do {
    tracks = try await asset.loadTracks(withMediaType: .audio)
    duration = try await asset.load(.duration)
  } catch {
    throw storyError(
      .unsupportedMedia, "Cannot read music: \(url.lastPathComponent)",
      (error as NSError).localizedDescription)
  }
  guard let source = tracks.first else {
    throw storyError(.unsupportedMedia, "Music file has no audio: \(url.lastPathComponent)")
  }
  let start = cmTime(ms: music.startMs)
  let available = CMTimeSubtract(duration, start)
  let length = CMTimeMinimum(available, maxDuration)
  guard length.seconds > 0.01 else {
    return nil
  }
  guard
    let track = composition.addMutableTrack(
      withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
  else {
    throw storyError(.encoder, "Cannot add a music track")
  }
  do {
    try track.insertTimeRange(CMTimeRange(start: start, duration: length), of: source, at: .zero)
  } catch {
    throw mapStoryError(error, context: "Inserting music")
  }
  return track
}

func volumeParameters(_ track: AVAssetTrack, volume: Double) -> AVMutableAudioMixInputParameters {
  let parameters = AVMutableAudioMixInputParameters(track: track)
  parameters.setVolume(Float(min(1, max(0, volume))), at: .zero)
  return parameters
}
