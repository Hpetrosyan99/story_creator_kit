@preconcurrency import AVFoundation
import CoreImage
import Foundation

/// Parameters of one story frame, carried to the compositor by the
/// video-composition instruction.
struct StoryFrameSpec {
  /// Composition track holding the source video.
  let trackID: CMPersistentTrackID
  /// The source track's `preferredTransform`.
  let sourceTransform: CGAffineTransform
  /// Where the displayed video goes, in output pixels, origin top-left.
  let videoRect: CGRect
  let mirror: Bool
  /// 4×5 row-major matrix with offsets in 0–255, or nil.
  let colorMatrix: [Double]?
  /// Full-canvas overlay drawn on top, already at output size.
  let overlay: CIImage?
  let renderSize: CGSize
}

/// Instruction covering the whole output with one [StoryFrameSpec].
final class StoryCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol,
  @unchecked Sendable
{
  let timeRange: CMTimeRange
  let enablePostProcessing = false
  let containsTweening = false
  let requiredSourceTrackIDs: [NSValue]?
  let passthroughTrackID = kCMPersistentTrackID_Invalid
  let spec: StoryFrameSpec

  init(timeRange: CMTimeRange, spec: StoryFrameSpec) {
    self.timeRange = timeRange
    self.spec = spec
    requiredSourceTrackIDs = [NSNumber(value: spec.trackID)]
  }
}

/// Custom compositor: orients, mirrors, colour-filters and places the video
/// frame on a black canvas, then draws the overlay PNG on top.
///
/// A custom compositor is used instead of AVVideoCompositionCoreAnimationTool,
/// which is unreliable in offline rendering and deprecated in iOS 27.
final class StoryCompositor: NSObject, AVVideoCompositing {
  private let queue = DispatchQueue(label: "story_creator_kit.compositor")
  private let lock = NSLock()
  private var cancelled = false

  /// Colour management off: pixel values are processed as stored, exactly
  /// like Flutter's `ColorFilter.matrix` in the editor preview.
  private let context = CIContext(options: [
    .workingColorSpace: NSNull(),
    .outputColorSpace: NSNull(),
    .cacheIntermediates: false,
  ])

  var sourcePixelBufferAttributes: [String: any Sendable]? {
    [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
  }

  var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
    [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
  }

  func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

  func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
    queue.async { [self] in
      lock.lock()
      let isCancelled = cancelled
      lock.unlock()
      if isCancelled {
        request.finishCancelledRequest()
        return
      }
      guard let instruction = request.videoCompositionInstruction as? StoryCompositionInstruction
      else {
        request.finish(with: compositorError("Unexpected instruction"))
        return
      }
      let spec = instruction.spec
      guard let source = request.sourceFrame(byTrackID: spec.trackID) else {
        request.finish(with: compositorError("Missing source frame"))
        return
      }
      guard let output = request.renderContext.newPixelBuffer() else {
        request.finish(with: compositorError("No output buffer"))
        return
      }
      let image = StoryCompositor.compose(source: CIImage(cvPixelBuffer: source), spec: spec)
      context.render(
        image, to: output,
        bounds: CGRect(origin: .zero, size: spec.renderSize), colorSpace: nil)
      request.finish(withComposedVideoFrame: output)
    }
  }

  func cancelAllPendingVideoCompositionRequests() {
    lock.lock()
    cancelled = true
    lock.unlock()
    queue.sync {}
    lock.lock()
    cancelled = false
    lock.unlock()
  }

  private func compositorError(_ message: String) -> NSError {
    NSError(
      domain: "story_creator_kit", code: -1,
      userInfo: [NSLocalizedDescriptionKey: message])
  }

  /// Builds the output frame in Core Image coordinates (origin bottom-left).
  static func compose(source: CIImage, spec: StoryFrameSpec) -> CIImage {
    let canvas = CGRect(origin: .zero, size: spec.renderSize)
    var video = source.oriented(VideoOrientation.imageOrientation(spec.sourceTransform))
    video = video.transformed(
      by: CGAffineTransform(translationX: -video.extent.minX, y: -video.extent.minY))
    if spec.mirror {
      video = video.transformed(
        by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -video.extent.width, y: 0))
    }
    if let matrix = spec.colorMatrix, matrix.count == 20 {
      video = applyColorMatrix(video, matrix)
    }
    let rect = spec.videoRect
    let sx = rect.width / max(1, video.extent.width)
    let sy = rect.height / max(1, video.extent.height)
    video = video.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
    let targetY = spec.renderSize.height - rect.minY - rect.height
    video = video.transformed(
      by: CGAffineTransform(
        translationX: rect.minX - video.extent.minX, y: targetY - video.extent.minY))
    let background = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(
      to: canvas)
    var frame = video.cropped(to: canvas).composited(over: background)
    if let overlay = spec.overlay {
      frame = overlay.composited(over: frame)
    }
    return frame.cropped(to: canvas)
  }

  /// Same maths as Flutter's `ColorFilter.matrix`: rows are R, G, B, A; the
  /// fifth column is an offset in 0–255. Applied to unpremultiplied colour.
  static func applyColorMatrix(_ image: CIImage, _ m: [Double]) -> CIImage {
    func vector(_ row: Int) -> CIVector {
      CIVector(
        x: CGFloat(m[row * 5]), y: CGFloat(m[row * 5 + 1]), z: CGFloat(m[row * 5 + 2]),
        w: CGFloat(m[row * 5 + 3]))
    }
    let bias = CIVector(
      x: CGFloat(m[4] / 255), y: CGFloat(m[9] / 255), z: CGFloat(m[14] / 255),
      w: CGFloat(m[19] / 255))
    let filtered = image.applyingFilter(
      "CIColorMatrix",
      parameters: [
        "inputRVector": vector(0),
        "inputGVector": vector(1),
        "inputBVector": vector(2),
        "inputAVector": vector(3),
        "inputBiasVector": bias,
      ])
    return filtered.applyingFilter(
      "CIColorClamp",
      parameters: [
        "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
      ])
  }
}

/// Builds the video composition, using the iOS 26 configuration API when
/// available.
func makeStoryVideoComposition(
  instruction: StoryCompositionInstruction, renderSize: CGSize, frameRate: Int
) -> AVVideoComposition {
  let frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, frameRate)))
  if #available(iOS 26.0, *) {
    let configuration = AVVideoComposition.Configuration(
      colorPrimaries: AVVideoColorPrimaries_ITU_R_709_2,
      colorTransferFunction: AVVideoTransferFunction_ITU_R_709_2,
      colorYCbCrMatrix: AVVideoYCbCrMatrix_ITU_R_709_2,
      customVideoCompositorClass: StoryCompositor.self,
      frameDuration: frameDuration,
      instructions: [instruction],
      renderSize: renderSize
    )
    return AVVideoComposition(configuration: configuration)
  }
  let composition = AVMutableVideoComposition()
  composition.customVideoCompositorClass = StoryCompositor.self
  composition.frameDuration = frameDuration
  composition.renderSize = renderSize
  composition.instructions = [instruction]
  composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
  composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
  composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
  return composition
}
