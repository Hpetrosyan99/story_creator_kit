import Flutter
import Foundation
import UIKit

/// Registers the story_creator_kit native API.
///
/// Every method does its heavy work on background queues; Pigeon delivers
/// replies on the main thread.
public class StoryCreatorKitPlugin: NSObject, FlutterPlugin, StoryNativeApi {
  private let events: StoryNativeEvents
  private let jobs = ExportJobRegistry()
  private let workQueue = DispatchQueue(
    label: "story_creator_kit.work", qos: .userInitiated, attributes: .concurrent)

  init(messenger: FlutterBinaryMessenger) {
    events = StoryNativeEvents(binaryMessenger: messenger)
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let instance = StoryCreatorKitPlugin(messenger: messenger)
    StoryNativeApiSetup.setUp(binaryMessenger: messenger, api: instance)
    registrar.publish(instance)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    jobs.cancelAll()
    StoryNativeApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
  }

  // MARK: - Export

  func exportVideo(request: VideoExportRequest) async throws -> NativeExportResult {
    let job = try jobs.begin(request.jobId)
    defer { jobs.end(request.jobId) }
    let exporter = VideoExporter(request: request, job: job, progress: progressSink(request.jobId))
    return try await exporter.run()
  }

  func exportStillVideo(request: StillVideoExportRequest) async throws -> NativeExportResult {
    let job = try jobs.begin(request.jobId)
    defer { jobs.end(request.jobId) }
    let exporter = StillVideoExporter(
      request: request, job: job, progress: progressSink(request.jobId))
    return try await exporter.run()
  }

  func encodeJpeg(request: JpegEncodeRequest) async throws -> NativeExportResult {
    try await runOffMain { try JpegEncoder.encode(request) }
  }

  func cancelExport(jobId: String) throws {
    jobs.cancel(jobId)
  }

  // MARK: - Inspection

  func probe(path: String) async throws -> NativeMediaProbe {
    try await MediaProber.probe(path: path)
  }

  func waveform(path: String, buckets: Int64) async throws -> [Double] {
    try await WaveformExtractor.extract(path: path, buckets: Int(buckets))
  }

  func thumbnails(
    path: String, timesMs: [Int64], maxWidth: Int64, outputDirectory: String
  ) async throws -> [String] {
    try await ThumbnailGenerator.generate(
      path: path, timesMs: timesMs, maxWidth: Int(maxWidth), outputDirectory: outputDirectory)
  }

  // MARK: - Helpers

  private func runOffMain<T>(_ work: @escaping () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      workQueue.async {
        do {
          continuation.resume(returning: try work())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// Sends progress to Dart on the main thread, at most every 100 ms or
  /// 1 %, and always for 0 and 1.
  private func progressSink(_ jobId: String) -> (Double) -> Void {
    let throttle = ProgressThrottle()
    return { [weak self] value in
      guard let self, throttle.shouldSend(value) else { return }
      DispatchQueue.main.async {
        Task { @MainActor in
          try? await self.events.onExportProgress(jobId: jobId, progress: value)
        }
      }
    }
  }
}

/// Decides which progress values are worth sending.
final class ProgressThrottle {
  private let lock = NSLock()
  private var lastValue = -1.0
  private var lastTime = Date.distantPast

  func shouldSend(_ value: Double) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let now = Date()
    let isEdge = value <= 0 || value >= 1
    if isEdge && value == lastValue {
      return false
    }
    if isEdge || value - lastValue >= 0.01 || now.timeIntervalSince(lastTime) >= 0.1 {
      lastValue = value
      lastTime = now
      return true
    }
    return false
  }
}

/// A running export that can be cancelled from another thread.
final class ExportJob {
  let id: String
  private let lock = NSLock()
  private var cancelled = false
  private var onCancel: [() -> Void] = []

  init(id: String) {
    self.id = id
  }

  var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }

  /// Runs [handler] when the job is cancelled (immediately if it already is).
  func whenCancelled(_ handler: @escaping () -> Void) {
    lock.lock()
    if cancelled {
      lock.unlock()
      handler()
      return
    }
    onCancel.append(handler)
    lock.unlock()
  }

  func cancel() {
    lock.lock()
    if cancelled {
      lock.unlock()
      return
    }
    cancelled = true
    let handlers = onCancel
    onCancel.removeAll()
    lock.unlock()
    handlers.forEach { $0() }
  }

  func throwIfCancelled() throws {
    if isCancelled {
      throw storyError(.cancelled, "Export \(id) was cancelled")
    }
  }
}

/// Jobs by id. A cancel that arrives before the job registered is remembered
/// so the job fails immediately when it starts.
final class ExportJobRegistry {
  private let lock = NSLock()
  private var jobs: [String: ExportJob] = [:]
  private var cancelledEarly: Set<String> = []

  func begin(_ id: String) throws -> ExportJob {
    lock.lock()
    defer { lock.unlock() }
    guard !id.isEmpty else {
      throw storyError(.invalidInput, "jobId is empty")
    }
    guard jobs[id] == nil else {
      throw storyError(.invalidInput, "A job with id \(id) is already running")
    }
    let job = ExportJob(id: id)
    if cancelledEarly.remove(id) != nil {
      job.cancel()
    }
    jobs[id] = job
    return job
  }

  func end(_ id: String) {
    lock.lock()
    jobs[id] = nil
    lock.unlock()
  }

  func cancel(_ id: String) {
    lock.lock()
    let job = jobs[id]
    if job == nil {
      // Remember briefly; the Dart side may cancel right after starting.
      cancelledEarly.insert(id)
      if cancelledEarly.count > 32 {
        cancelledEarly.removeFirst()
      }
    }
    lock.unlock()
    job?.cancel()
  }

  func cancelAll() {
    lock.lock()
    let all = Array(jobs.values)
    lock.unlock()
    all.forEach { $0.cancel() }
  }
}
