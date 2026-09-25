package com.mabrook.story_creator_kit

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Registers the story_creator_kit native API. */
class StoryCreatorKitPlugin : FlutterPlugin {
  private var api: StoryNativeApiImpl? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    val impl = StoryNativeApiImpl(binding.applicationContext, StoryNativeEvents(binding.binaryMessenger))
    api = impl
    StoryNativeApi.setUp(binding.binaryMessenger, impl)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    StoryNativeApi.setUp(binding.binaryMessenger, null)
    api?.dispose()
    api = null
  }
}

/**
 * The native API. Pigeon calls the suspend functions on the main dispatcher;
 * file and codec work moves to [Dispatchers.IO], Transformer runs on the main
 * looper.
 */
internal class StoryNativeApiImpl(
  context: Context,
  private val events: StoryNativeEvents,
) : StoryNativeApi {
  private val exporter = MediaExporter(context)
  private val jobs = ExportJobRegistry()
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

  fun dispose() {
    jobs.cancelAll()
    scope.cancel()
  }

  override suspend fun exportVideo(request: VideoExportRequest): NativeExportResult {
    val job = jobs.begin(request.jobId)
    try {
      return exporter.exportVideo(request, job, progressSink(request.jobId))
    } catch (e: Throwable) {
      throw mapError(e, "Video export")
    } finally {
      jobs.end(request.jobId)
    }
  }

  override suspend fun exportStillVideo(request: StillVideoExportRequest): NativeExportResult {
    val job = jobs.begin(request.jobId)
    try {
      return exporter.exportStill(request, job, progressSink(request.jobId))
    } catch (e: Throwable) {
      throw mapError(e, "Still video export")
    } finally {
      jobs.end(request.jobId)
    }
  }

  override suspend fun encodeJpeg(request: JpegEncodeRequest): NativeExportResult = io("JPEG encoding") {
    StillImageTools.encodeJpeg(request)
  }

  override fun cancelExport(jobId: String) {
    jobs.cancel(jobId)
  }

  override suspend fun probe(path: String): NativeMediaProbe = io("Probe") { MediaProber.probe(path) }

  override suspend fun waveform(path: String, buckets: Long): List<Double> = io("Waveform") {
    WaveformExtractor.extract(path, buckets.toInt())
  }

  override suspend fun thumbnails(
    path: String,
    timesMs: List<Long>,
    maxWidth: Long,
    outputDirectory: String,
  ): List<String> = io("Thumbnails") {
    StillImageTools.thumbnails(path, timesMs, maxWidth.toInt(), outputDirectory)
  }

  private suspend fun <T> io(what: String, block: () -> T): T = withContext(Dispatchers.IO) {
    try {
      block()
    } catch (e: Throwable) {
      throw mapError(e, what)
    }
  }

  /** Sends progress on the main thread, at most every 1 % (always 0 and 1). */
  private fun progressSink(jobId: String): (Double) -> Unit {
    var last = -1.0
    return { value ->
      val edge = value <= 0.0 || value >= 1.0
      if ((edge && value != last) || value - last >= 0.01) {
        last = value
        scope.launch {
          try {
            events.onExportProgress(jobId, value)
          } catch (_: Throwable) {
            // The Dart side may have gone away; progress is best effort.
          }
        }
      }
    }
  }
}

/** A running export that can be cancelled from another thread. */
internal class ExportJob(val id: String) {
  private val lock = Any()
  private var cancelled = false
  private val handlers = mutableListOf<() -> Unit>()

  val isCancelled: Boolean
    get() = synchronized(lock) { cancelled }

  fun whenCancelled(handler: () -> Unit) {
    val runNow = synchronized(lock) {
      if (!cancelled) handlers.add(handler)
      cancelled
    }
    if (runNow) handler()
  }

  fun cancel() {
    val toRun = synchronized(lock) {
      if (cancelled) return
      cancelled = true
      handlers.toList().also { handlers.clear() }
    }
    toRun.forEach { it() }
  }

  fun throwIfCancelled() {
    if (isCancelled) throw storyError(ErrorCodes.CANCELLED, "Export $id was cancelled")
  }
}

/** Jobs by id; a cancel that arrives before its job starts is remembered. */
internal class ExportJobRegistry {
  private val jobs = HashMap<String, ExportJob>()
  private val cancelledEarly = LinkedHashSet<String>()

  @Synchronized
  fun begin(id: String): ExportJob {
    if (id.isEmpty()) throw storyError(ErrorCodes.INVALID_INPUT, "jobId is empty")
    if (jobs.containsKey(id)) throw storyError(ErrorCodes.INVALID_INPUT, "A job with id $id is already running")
    val job = ExportJob(id)
    if (cancelledEarly.remove(id)) job.cancel()
    jobs[id] = job
    return job
  }

  @Synchronized
  fun end(id: String) {
    jobs.remove(id)
  }

  fun cancel(id: String) {
    val job = synchronized(this) {
      jobs[id] ?: run {
        cancelledEarly.add(id)
        if (cancelledEarly.size > 32) cancelledEarly.remove(cancelledEarly.first())
        null
      }
    }
    job?.cancel()
  }

  fun cancelAll() {
    val all = synchronized(this) { jobs.values.toList() }
    all.forEach { it.cancel() }
  }
}
