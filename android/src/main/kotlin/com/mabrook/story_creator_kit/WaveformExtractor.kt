package com.mabrook.story_creator_kit

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/** Peak levels of a file's audio, decoded with MediaExtractor + MediaCodec. */
internal object WaveformExtractor {
  private const val TIMEOUT_US = 10_000L

  fun extract(path: String, buckets: Int): List<Double> {
    if (buckets !in 1..100_000) {
      throw storyError(ErrorCodes.INVALID_INPUT, "buckets must be 1–100000, got $buckets")
    }
    val file = requireReadableFile(path, "Audio file")
    val extractor = MediaExtractor()
    try {
      try {
        extractor.setDataSource(file.path)
      } catch (e: Exception) {
        throw storyError(ErrorCodes.UNSUPPORTED_MEDIA, "Cannot read audio: ${file.name}", e.message)
      }
      var trackIndex = -1
      var format: MediaFormat? = null
      for (i in 0 until extractor.trackCount) {
        val f = extractor.getTrackFormat(i)
        if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
          trackIndex = i
          format = f
          break
        }
      }
      if (format == null) return List(buckets) { 0.0 }
      extractor.selectTrack(trackIndex)
      val durationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) {
        format.getLong(MediaFormat.KEY_DURATION)
      } else {
        MediaProber.probe(path).durationMs?.times(1000) ?: 1L
      }.coerceAtLeast(1L)
      return decode(extractor, format, durationUs, buckets)
    } finally {
      extractor.release()
    }
  }

  private fun decode(
    extractor: MediaExtractor,
    format: MediaFormat,
    durationUs: Long,
    buckets: Int,
  ): List<Double> {
    val mime = format.getString(MediaFormat.KEY_MIME)!!
    val codec = try {
      MediaCodec.createDecoderByType(mime).apply { configure(format, null, null, 0) }
    } catch (e: Exception) {
      throw storyError(ErrorCodes.UNSUPPORTED_MEDIA, "No decoder for $mime", e.message)
    }
    val peaks = DoubleArray(buckets)
    try {
      codec.start()
      val info = MediaCodec.BufferInfo()
      var inputDone = false
      var outputDone = false
      var channels = if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) else 1
      var sampleRate = if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) format.getInteger(MediaFormat.KEY_SAMPLE_RATE) else 44_100
      var isFloat = false
      while (!outputDone) {
        if (!inputDone) {
          val inIndex = codec.dequeueInputBuffer(TIMEOUT_US)
          if (inIndex >= 0) {
            val buffer = codec.getInputBuffer(inIndex)!!
            val size = extractor.readSampleData(buffer, 0)
            if (size < 0) {
              codec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
              inputDone = true
            } else {
              codec.queueInputBuffer(inIndex, 0, size, extractor.sampleTime, 0)
              extractor.advance()
            }
          }
        }
        val outIndex = codec.dequeueOutputBuffer(info, TIMEOUT_US)
        when {
          outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
            val out = codec.outputFormat
            channels = out.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            sampleRate = out.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            isFloat = out.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
              out.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
          }
          outIndex >= 0 -> {
            val buffer = codec.getOutputBuffer(outIndex)
            if (buffer != null && info.size > 0) {
              buffer.position(info.offset)
              buffer.limit(info.offset + info.size)
              buffer.order(ByteOrder.nativeOrder())
              val bytesPerSample = if (isFloat) 4 else 2
              val frames = info.size / (bytesPerSample * max(1, channels))
              val startUs = info.presentationTimeUs
              for (frame in 0 until frames) {
                var level = 0.0
                for (c in 0 until channels) {
                  val v = if (isFloat) abs(buffer.float.toDouble()) else abs(buffer.short.toDouble()) / 32768.0
                  if (v > level) level = v
                }
                val timeUs = startUs + frame * 1_000_000L / max(1, sampleRate)
                val bucket = min(buckets - 1, max(0, (timeUs.toDouble() / durationUs * buckets).toInt()))
                if (level > peaks[bucket]) peaks[bucket] = level
              }
            }
            codec.releaseOutputBuffer(outIndex, false)
            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
          }
        }
      }
    } catch (e: FlutterError) {
      throw e
    } catch (e: Exception) {
      throw storyError(ErrorCodes.UNSUPPORTED_MEDIA, "Audio decoding failed", e.message)
    } finally {
      try {
        codec.stop()
      } catch (_: IllegalStateException) {
      }
      codec.release()
    }
    return peaks.map { min(1.0, it) }
  }
}
