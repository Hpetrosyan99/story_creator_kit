// Generates the small synthetic video fixtures used by the export
// integration tests. No third-party media is involved.
//
//   swift example/integration_test/tool/make_fixtures.swift example/integration_test/assets
//
// Every clip shows the same *display* picture: quadrants red (top-left),
// green (top-right), blue (bottom-left), white (bottom-right) and a centre
// square whose colour encodes the second: yellow, cyan, magenta, orange.
// Audio, when present, is a 440 Hz sine at half scale.
import AVFoundation
import CoreVideo
import Foundation

struct Fixture {
  let name: String
  let codec: AVVideoCodecType
  let displayWidth: Int
  let displayHeight: Int
  /// Clockwise rotation stored in the track (0 or 90).
  let rotation: Int
  /// 0 = no audio track.
  let audioChannels: Int
  let seconds: Int
}

let fixtures = [
  Fixture(name: "landscape_h264_stereo.mp4", codec: .h264, displayWidth: 640, displayHeight: 360, rotation: 0, audioChannels: 2, seconds: 4),
  Fixture(name: "portrait_rotated90_h264.mp4", codec: .h264, displayWidth: 360, displayHeight: 640, rotation: 90, audioChannels: 2, seconds: 4),
  Fixture(name: "portrait_hevc_mono.mp4", codec: .hevc, displayWidth: 360, displayHeight: 640, rotation: 0, audioChannels: 1, seconds: 4),
  Fixture(name: "landscape_h264_silent.mp4", codec: .h264, displayWidth: 640, displayHeight: 360, rotation: 0, audioChannels: 0, seconds: 4),
]

let fps: Int32 = 30
let sampleRate = 44_100.0

typealias RGB = (UInt8, UInt8, UInt8)

func displayColor(x: Int, y: Int, w: Int, h: Int, second: Int) -> RGB {
  let square = min(w, h) / 4
  if abs(x - w / 2) < square / 2 && abs(y - h / 2) < square / 2 {
    switch second {
    case 0: return (255, 255, 0)
    case 1: return (0, 255, 255)
    case 2: return (255, 0, 255)
    default: return (255, 128, 0)
    }
  }
  switch (x < w / 2, y < h / 2) {
  case (true, true): return (255, 0, 0)
  case (false, true): return (0, 255, 0)
  case (true, false): return (0, 0, 255)
  case (false, false): return (255, 255, 255)
  }
}

func makeFrame(_ f: Fixture, second: Int) -> CVPixelBuffer {
  let encodedW = f.rotation == 90 ? f.displayHeight : f.displayWidth
  let encodedH = f.rotation == 90 ? f.displayWidth : f.displayHeight
  var buffer: CVPixelBuffer?
  CVPixelBufferCreate(nil, encodedW, encodedH, kCVPixelFormatType_32BGRA, nil, &buffer)
  let pb = buffer!
  CVPixelBufferLockBaseAddress(pb, [])
  let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
  let stride = CVPixelBufferGetBytesPerRow(pb)
  for y in 0..<encodedH {
    for x in 0..<encodedW {
      // Display = encoded rotated clockwise: (x, y) -> (H-1-y, x).
      let dx = f.rotation == 90 ? encodedH - 1 - y : x
      let dy = f.rotation == 90 ? x : y
      let (r, g, b) = displayColor(x: dx, y: dy, w: f.displayWidth, h: f.displayHeight, second: second)
      let p = base + y * stride + x * 4
      p[0] = b
      p[1] = g
      p[2] = r
      p[3] = 255
    }
  }
  CVPixelBufferUnlockBaseAddress(pb, [])
  return pb
}

func audioBuffer(channels: Int, startFrame: Int, frames: Int) -> CMSampleBuffer {
  var asbd = AudioStreamBasicDescription(
    mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
    mBytesPerPacket: UInt32(2 * channels), mFramesPerPacket: 1, mBytesPerFrame: UInt32(2 * channels),
    mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 16, mReserved: 0)
  var format: CMAudioFormatDescription?
  CMAudioFormatDescriptionCreate(
    allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
    magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
  var samples = [Int16](repeating: 0, count: frames * channels)
  for i in 0..<frames {
    let t = Double(startFrame + i) / sampleRate
    let v = Int16(sin(2 * .pi * 440 * t) * 16_000)
    for c in 0..<channels { samples[i * channels + c] = v }
  }
  let length = samples.count * 2
  var block: CMBlockBuffer?
  CMBlockBufferCreateWithMemoryBlock(
    allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil,
    customBlockSource: nil, offsetToData: 0, dataLength: length, flags: 0, blockBufferOut: &block)
  samples.withUnsafeBytes { raw in
    _ = CMBlockBufferReplaceDataBytes(
      with: raw.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: length)
  }
  var sample: CMSampleBuffer?
  CMAudioSampleBufferCreateReadyWithPacketDescriptions(
    allocator: nil, dataBuffer: block!, formatDescription: format!, sampleCount: frames,
    presentationTimeStamp: CMTime(value: CMTimeValue(startFrame), timescale: CMTimeScale(sampleRate)),
    packetDescriptions: nil, sampleBufferOut: &sample)
  return sample!
}

func write(_ f: Fixture, to directory: URL) throws {
  let url = directory.appendingPathComponent(f.name)
  try? FileManager.default.removeItem(at: url)
  let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
  let encodedW = f.rotation == 90 ? f.displayHeight : f.displayWidth
  let encodedH = f.rotation == 90 ? f.displayWidth : f.displayHeight
  let video = AVAssetWriterInput(
    mediaType: .video,
    outputSettings: [
      AVVideoCodecKey: f.codec, AVVideoWidthKey: encodedW, AVVideoHeightKey: encodedH,
      AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 600_000],
      // Tagged like camera footage so every decoder uses the same matrix.
      AVVideoColorPropertiesKey: [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
      ],
    ])
  video.expectsMediaDataInRealTime = false
  if f.rotation == 90 {
    video.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(encodedH), ty: 0)
  }
  writer.add(video)
  let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: nil)
  var audio: AVAssetWriterInput?
  if f.audioChannels > 0 {
    let input = AVAssetWriterInput(
      mediaType: .audio,
      outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: f.audioChannels, AVEncoderBitRateKey: 64_000,
      ])
    input.expectsMediaDataInRealTime = false
    writer.add(input)
    audio = input
  }
  writer.startWriting()
  writer.startSession(atSourceTime: .zero)
  let frames = (0..<f.seconds).map { makeFrame(f, second: $0) }
  // Interleave by time: the writer stalls one input while waiting for the other.
  let totalFrames = Int(fps) * f.seconds
  let totalSamples = Int(sampleRate) * f.seconds
  var frame = 0
  var sample = 0
  while frame < totalFrames || (audio != nil && sample < totalSamples) {
    let videoTime = Double(frame) / Double(fps)
    let audioTime = Double(sample) / sampleRate
    if frame < totalFrames && (audio == nil || sample >= totalSamples || videoTime <= audioTime) {
      if video.isReadyForMoreMediaData {
        adaptor.append(frames[frame / Int(fps)], withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        frame += 1
      } else {
        usleep(500)
      }
    } else if let audio {
      if audio.isReadyForMoreMediaData {
        let n = min(4096, totalSamples - sample)
        audio.append(audioBuffer(channels: f.audioChannels, startFrame: sample, frames: n))
        sample += n
      } else {
        usleep(500)
      }
    }
  }
  video.markAsFinished()
  audio?.markAsFinished()
  writer.endSession(atSourceTime: CMTime(value: CMTimeValue(f.seconds), timescale: 1))
  let done = DispatchSemaphore(value: 0)
  writer.finishWriting { done.signal() }
  done.wait()
  guard writer.status == .completed else {
    throw writer.error ?? NSError(domain: "fixtures", code: 1)
  }
  print("wrote \(url.path)")
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for fixture in fixtures {
  try write(fixture, to: out)
}
