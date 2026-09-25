@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package com.mabrook.story_creator_kit

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.ChannelMixingAudioProcessor
import androidx.media3.common.audio.ChannelMixingMatrix
import androidx.media3.common.audio.SonicAudioProcessor
import androidx.media3.common.audio.ToInt16PcmAudioProcessor
import androidx.media3.common.util.Size
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.DefaultVideoFrameProcessor
import androidx.media3.effect.FrameDropEffect
import androidx.media3.effect.GlMatrixTransformation
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.RgbMatrix
import androidx.media3.effect.TextureOverlay
import androidx.media3.transformer.AudioEncoderSettings
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import com.google.common.collect.ImmutableList
import java.io.File
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.max
import kotlin.math.min
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

/**
 * Media3 Transformer exports.
 *
 * The composition holds the (trimmed) source video in sequence 0 and the
 * music segment in sequence 1. Every audio input is normalised to 16-bit PCM,
 * stereo, 44.1 kHz with its volume applied, because Transformer mixes only
 * inputs with the same PCM format.
 */
internal class MediaExporter(private val context: Context) {
  private val mainHandler = Handler(Looper.getMainLooper())

  suspend fun exportVideo(
    request: VideoExportRequest,
    job: ExportJob,
    progress: (Double) -> Unit,
  ): NativeExportResult {
    val output = request.output
    validateOutput(output)
    validateVideoRequest(request)
    val prepared = withContext(Dispatchers.IO) {
      val source = requireReadableFile(request.sourcePath, "Source video")
      val out = prepareOutput(output.path)
      val probe = MediaProber.probe(source.path)
      if (!probe.hasVideo) throw storyError(ErrorCodes.UNSUPPORTED_MEDIA, "The source has no video track")
      val durationMs = probe.durationMs ?: 0
      val endMs = min(request.trimEndMs, durationMs)
      if (endMs <= request.trimStartMs) {
        throw storyError(
          ErrorCodes.INVALID_INPUT,
          "Trim ${request.trimStartMs}–${request.trimEndMs} ms is outside the video ($durationMs ms)",
        )
      }
      val outDurationMs = endMs - request.trimStartMs
      requireFreeSpace(estimatedBytes(output, outDurationMs), out)
      val overlay = request.overlayPngPath?.let { loadOverlay(it, output) }
      val music = request.music?.takeIf { it.volume > 0 }?.let { musicItem(it, outDurationMs) }
      PreparedVideo(source, out, probe.hasAudio, endMs, outDurationMs, overlay, music)
    }
    job.throwIfCancelled()

    val keepAudio = prepared.hasAudio && request.originalVolume > 0
    val videoEffects = mutableListOf<Effect>(
      FrameDropEffect.createDefaultFrameDropEffect(output.frameRate.toFloat()),
    )
    request.colorMatrix?.let { videoEffects.add(colorMatrixEffect(it)) }
    videoEffects.add(
      PlacementTransformation(
        outputWidth = output.width.toInt(),
        outputHeight = output.height.toInt(),
        rect = request.videoRect,
        mirror = request.mirror,
      ),
    )
    prepared.overlay?.let {
      videoEffects.add(OverlayEffect(ImmutableList.of<TextureOverlay>(BitmapOverlay.createStaticBitmapOverlay(it))))
    }
    val videoItem = EditedMediaItem.Builder(
      MediaItem.Builder()
        .setUri(Uri.fromFile(prepared.source))
        .setClippingConfiguration(
          MediaItem.ClippingConfiguration.Builder()
            .setStartPositionMs(request.trimStartMs)
            .setEndPositionMs(prepared.endMs)
            .build(),
        )
        .build(),
    )
      .setRemoveAudio(!keepAudio)
      .setEffects(
        Effects(
          if (keepAudio) audioNormalizers(request.originalVolume.toFloat()) else emptyList(),
          videoEffects,
        ),
      )
      .build()
    val videoSequence = if (keepAudio) {
      EditedMediaItemSequence.withAudioAndVideoFrom(listOf(videoItem))
    } else {
      EditedMediaItemSequence.withVideoFrom(listOf(videoItem))
    }
    val sequences = mutableListOf(videoSequence)
    prepared.music?.let { sequences.add(EditedMediaItemSequence.withAudioFrom(listOf(it))) }
    val composition = Composition.Builder(sequences)
      .apply {
        if (Build.VERSION.SDK_INT >= 29) setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
      }
      .build()
    run(composition, prepared.output, output, job, progress)
    return withContext(Dispatchers.IO) {
      NativeExportResult(
        path = output.path,
        width = output.width,
        height = output.height,
        fileSizeBytes = prepared.output.length(),
        durationMs = prepared.durationMs,
      )
    }
  }

  suspend fun exportStill(
    request: StillVideoExportRequest,
    job: ExportJob,
    progress: (Double) -> Unit,
  ): NativeExportResult {
    val output = request.output
    validateOutput(output)
    if (request.durationMs <= 0) {
      throw storyError(ErrorCodes.INVALID_INPUT, "durationMs must be positive, got ${request.durationMs}")
    }
    val prepared = withContext(Dispatchers.IO) {
      val frame = requireReadableFile(request.framePath, "Frame image")
      if (MediaProber.probeImage(frame) == null) {
        throw storyError(ErrorCodes.INVALID_INPUT, "Frame is not a readable image: ${frame.name}")
      }
      val out = prepareOutput(output.path)
      requireFreeSpace(estimatedBytes(output, request.durationMs), out)
      val music = request.music?.takeIf { it.volume > 0 }?.let { musicItem(it, request.durationMs) }
      Triple(frame, out, music)
    }
    job.throwIfCancelled()
    val (frame, out, music) = prepared
    val mime = if (frame.name.lowercase().endsWith(".png")) MimeTypes.IMAGE_PNG else MimeTypes.IMAGE_JPEG
    val imageItem = EditedMediaItem.Builder(
      MediaItem.Builder()
        .setUri(Uri.fromFile(frame))
        .setMimeType(mime)
        .setImageDurationMs(request.durationMs)
        .build(),
    )
      .setDurationUs(request.durationMs * 1000)
      .setFrameRate(output.frameRate.toInt())
      .setEffects(
        Effects(
          emptyList(),
          listOf(
            Presentation.createForWidthAndHeight(
              output.width.toInt(), output.height.toInt(), Presentation.LAYOUT_STRETCH_TO_FIT,
            ),
          ),
        ),
      )
      .build()
    val sequences = mutableListOf(EditedMediaItemSequence.withVideoFrom(listOf(imageItem)))
    music?.let { sequences.add(EditedMediaItemSequence.withAudioFrom(listOf(it))) }
    run(Composition.Builder(sequences).build(), out, output, job, progress)
    return withContext(Dispatchers.IO) {
      NativeExportResult(
        path = output.path,
        width = output.width,
        height = output.height,
        fileSizeBytes = out.length(),
        durationMs = request.durationMs,
      )
    }
  }

  /** Runs [composition] on the main looper until it completes, fails or is cancelled. */
  private suspend fun run(
    composition: Composition,
    out: File,
    output: NativeOutput,
    job: ExportJob,
    progress: (Double) -> Unit,
  ) = withContext(Dispatchers.Main) {
    suspendCancellableCoroutine { continuation ->
      var finished = false
      lateinit var transformer: Transformer
      val holder = ProgressHolder()
      val poll = object : Runnable {
        override fun run() {
          if (finished) return
          if (transformer.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) {
            progress(min(0.99, holder.progress / 100.0))
          }
          mainHandler.postDelayed(this, PROGRESS_INTERVAL_MS)
        }
      }
      fun finish(error: Throwable?) {
        if (finished) return
        finished = true
        mainHandler.removeCallbacks(poll)
        if (error != null) {
          out.delete()
          continuation.resumeWithException(error)
        } else {
          progress(1.0)
          continuation.resume(Unit)
        }
      }
      val listener = object : Transformer.Listener {
        override fun onCompleted(composition: Composition, exportResult: ExportResult) {
          if (job.isCancelled) {
            finish(storyError(ErrorCodes.CANCELLED, "Export ${job.id} was cancelled"))
          } else {
            finish(null)
          }
        }

        override fun onError(
          composition: Composition,
          exportResult: ExportResult,
          exportException: ExportException,
        ) {
          finish(
            if (job.isCancelled) {
              storyError(ErrorCodes.CANCELLED, "Export ${job.id} was cancelled")
            } else {
              mapError(exportException, "Export")
            },
          )
        }
      }
      transformer = Transformer.Builder(context)
        .setLooper(Looper.getMainLooper())
        .setVideoMimeType(MimeTypes.VIDEO_H264)
        .setAudioMimeType(MimeTypes.AUDIO_AAC)
        .setPortraitEncodingEnabled(true)
        .setEncoderFactory(
          DefaultEncoderFactory.Builder(context)
            .setRequestedVideoEncoderSettings(
              VideoEncoderSettings.Builder().setBitrate(output.videoBitrate.toInt()).build(),
            )
            .setRequestedAudioEncoderSettings(
              AudioEncoderSettings.Builder().setBitrate(AUDIO_BITRATE).build(),
            )
            .setEnableFallback(true)
            .build(),
        )
        .setVideoFrameProcessorFactory(
          // Effects work on the stored (gamma-encoded) values, like Flutter's
          // ColorFilter.matrix in the editor preview.
          DefaultVideoFrameProcessor.Factory.Builder()
            .setSdrWorkingColorSpace(DefaultVideoFrameProcessor.WORKING_COLOR_SPACE_ORIGINAL)
            .build(),
        )
        .addListener(listener)
        .build()
      job.whenCancelled {
        mainHandler.post {
          if (finished) return@post
          transformer.cancel()
          finish(storyError(ErrorCodes.CANCELLED, "Export ${job.id} was cancelled"))
        }
      }
      continuation.invokeOnCancellation {
        mainHandler.post {
          if (!finished) {
            finished = true
            transformer.cancel()
            mainHandler.removeCallbacks(poll)
            out.delete()
          }
        }
      }
      try {
        progress(0.0)
        transformer.start(composition, out.path)
        mainHandler.postDelayed(poll, PROGRESS_INTERVAL_MS)
      } catch (e: Exception) {
        finish(mapError(e, "Starting the export"))
      }
    }
  }

  private data class PreparedVideo(
    val source: File,
    val output: File,
    val hasAudio: Boolean,
    val endMs: Long,
    val durationMs: Long,
    val overlay: Bitmap?,
    val music: EditedMediaItem?,
  )

  /** The music segment [startMs, startMs + lengthMs) as an audio-only item, or null when empty. */
  private fun musicItem(music: NativeAudioTrack, lengthMs: Long): EditedMediaItem? {
    val file = requireReadableFile(music.path, "Music file")
    val probe = try {
      MediaProber.probe(file.path)
    } catch (e: FlutterError) {
      throw storyError(ErrorCodes.UNSUPPORTED_MEDIA, "Cannot read music: ${file.name}", e.message)
    }
    if (!probe.hasAudio) throw storyError(ErrorCodes.UNSUPPORTED_MEDIA, "Music file has no audio: ${file.name}")
    val startMs = max(0L, music.startMs)
    val durationMs = probe.durationMs ?: Long.MAX_VALUE
    val endMs = min(durationMs, startMs + lengthMs)
    if (endMs - startMs < 10) return null
    return EditedMediaItem.Builder(
      MediaItem.Builder()
        .setUri(Uri.fromFile(file))
        .setClippingConfiguration(
          MediaItem.ClippingConfiguration.Builder()
            .setStartPositionMs(startMs)
            .setEndPositionMs(endMs)
            .build(),
        )
        .build(),
    )
      .setRemoveVideo(true)
      .setEffects(Effects(audioNormalizers(music.volume.toFloat()), emptyList()))
      .build()
  }

  private fun loadOverlay(path: String, output: NativeOutput): Bitmap {
    val file = requireReadableFile(path, "Overlay image")
    val options = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 }
    val bitmap = BitmapFactory.decodeFile(file.path, options)
      ?: throw storyError(ErrorCodes.INVALID_INPUT, "Overlay is not a readable image: ${file.name}")
    val w = output.width.toInt()
    val h = output.height.toInt()
    if (bitmap.width == w && bitmap.height == h) return bitmap
    return Bitmap.createScaledBitmap(bitmap, w, h, true).also { if (it !== bitmap) bitmap.recycle() }
  }

  private fun validateOutput(output: NativeOutput) {
    if (output.width <= 0 || output.height <= 0 || output.width > 8192 || output.height > 8192) {
      throw storyError(ErrorCodes.INVALID_INPUT, "Invalid output size ${output.width}x${output.height}")
    }
    if (output.width % 2 != 0L || output.height % 2 != 0L) {
      throw storyError(ErrorCodes.INVALID_INPUT, "Output size must be even, got ${output.width}x${output.height}")
    }
    if (output.frameRate !in 1..120) throw storyError(ErrorCodes.INVALID_INPUT, "Invalid frame rate ${output.frameRate}")
    if (output.videoBitrate <= 0) throw storyError(ErrorCodes.INVALID_INPUT, "Invalid bitrate ${output.videoBitrate}")
  }

  private fun validateVideoRequest(request: VideoExportRequest) {
    val r = request.videoRect
    if (!(r.width > 0 && r.height > 0 && r.left.isFinite() && r.top.isFinite() && r.width.isFinite() && r.height.isFinite())) {
      throw storyError(ErrorCodes.INVALID_INPUT, "Invalid videoRect $r")
    }
    if (request.trimStartMs < 0 || request.trimEndMs <= request.trimStartMs) {
      throw storyError(ErrorCodes.INVALID_INPUT, "Invalid trim ${request.trimStartMs}–${request.trimEndMs} ms")
    }
    request.colorMatrix?.let {
      if (it.size != 20) throw storyError(ErrorCodes.INVALID_INPUT, "colorMatrix needs 20 values, got ${it.size}")
    }
    if (request.originalVolume < 0) throw storyError(ErrorCodes.INVALID_INPUT, "originalVolume must be ≥ 0")
  }

  private fun estimatedBytes(output: NativeOutput, durationMs: Long): Long {
    val seconds = max(1.0, durationMs / 1000.0)
    return ((output.videoBitrate + AUDIO_BITRATE) * seconds / 8 * 1.2).toLong() + 5_000_000L
  }

  companion object {
    private const val PROGRESS_INTERVAL_MS = 200L
    private const val AUDIO_BITRATE = 128_000
    private const val SAMPLE_RATE = 44_100

    /** 16-bit PCM → stereo with [volume] applied → 44.1 kHz. */
    fun audioNormalizers(volume: Float): List<AudioProcessor> {
      val gain = volume.coerceIn(0f, 1f)
      val mixer = ChannelMixingAudioProcessor()
      for (channels in 1..8) {
        try {
          mixer.putChannelMixingMatrix(ChannelMixingMatrix.createForConstantGain(channels, 2).scaleBy(gain))
        } catch (_: RuntimeException) {
          // No default down-mix for this layout; such inputs fail as unsupported.
        }
      }
      val resampler = SonicAudioProcessor().apply { setOutputSampleRateHz(SAMPLE_RATE) }
      return listOf(ToInt16PcmAudioProcessor(), mixer, resampler)
    }

    /**
     * Flutter's row-major 4×5 matrix (offsets 0–255) as a column-major 4×4 GL
     * matrix. The offsets go into the alpha column, which is exact for opaque
     * video frames (alpha = 1).
     */
    fun glColorMatrix(m: List<Double>): FloatArray {
      val gl = FloatArray(16)
      for (row in 0 until 3) {
        for (col in 0 until 3) gl[col * 4 + row] = m[row * 5 + col].toFloat()
        gl[12 + row] = (m[row * 5 + 3] + m[row * 5 + 4] / 255.0).toFloat()
      }
      gl[15] = 1f
      return gl
    }

    private fun colorMatrixEffect(m: List<Double>): RgbMatrix {
      val gl = glColorMatrix(m)
      return RgbMatrix { _, _ -> gl }
    }
  }
}

/**
 * Places the display-oriented video frame into [rect] (output pixels, origin
 * top-left) on an output canvas of [outputWidth]×[outputHeight]; parts
 * outside the canvas are clipped. Mirrors horizontally when [mirror].
 */
internal class PlacementTransformation(
  private val outputWidth: Int,
  private val outputHeight: Int,
  rect: NativeRect,
  mirror: Boolean,
) : GlMatrixTransformation {
  private val matrix: FloatArray

  init {
    val w = outputWidth.toDouble()
    val h = outputHeight.toDouble()
    val sx = rect.width / w * (if (mirror) -1 else 1)
    val sy = rect.height / h
    val tx = 2 * (rect.left + rect.width / 2) / w - 1
    val ty = 1 - 2 * (rect.top + rect.height / 2) / h
    matrix = floatArrayOf(
      sx.toFloat(), 0f, 0f, 0f,
      0f, sy.toFloat(), 0f, 0f,
      0f, 0f, 1f, 0f,
      tx.toFloat(), ty.toFloat(), 0f, 1f,
    )
  }

  override fun configure(inputWidth: Int, inputHeight: Int): Size = Size(outputWidth, outputHeight)

  override fun getGlMatrixArray(presentationTimeUs: Long): FloatArray = matrix
}
