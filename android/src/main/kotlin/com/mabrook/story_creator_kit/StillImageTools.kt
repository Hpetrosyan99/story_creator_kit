package com.mabrook.story_creator_kit

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
import android.os.Build
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.UUID
import kotlin.math.max
import kotlin.math.roundToInt

/** JPEG encoding and thumbnails. */
internal object StillImageTools {
  fun encodeJpeg(request: JpegEncodeRequest): NativeExportResult {
    val width = request.width.toInt()
    val height = request.height.toInt()
    if (width <= 0 || height <= 0) {
      throw storyError(ErrorCodes.INVALID_INPUT, "Invalid JPEG size ${width}x$height")
    }
    val bytes = request.rgba
    if (bytes.size != width * height * 4) {
      throw storyError(ErrorCodes.INVALID_INPUT, "Expected ${width * height * 4} RGBA bytes, got ${bytes.size}")
    }
    if (request.quality !in 1..100) {
      throw storyError(ErrorCodes.INVALID_INPUT, "JPEG quality must be 1–100, got ${request.quality}")
    }
    val out = prepareOutput(request.outputPath)
    requireFreeSpace(bytes.size / 4L + 1_000_000L, out)
    // The frame is opaque: force alpha so premultiplication is a no-op.
    var i = 3
    while (i < bytes.size) {
      bytes[i] = 0xFF.toByte()
      i += 4
    }
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    try {
      bitmap.copyPixelsFromBuffer(ByteBuffer.wrap(bytes))
      writeJpeg(bitmap, out, request.quality.toInt())
    } finally {
      bitmap.recycle()
    }
    return NativeExportResult(
      path = request.outputPath,
      width = width.toLong(),
      height = height.toLong(),
      fileSizeBytes = out.length(),
    )
  }

  fun writeJpeg(bitmap: Bitmap, out: File, quality: Int) {
    try {
      FileOutputStream(out).use { stream ->
        if (!bitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream)) {
          throw storyError(ErrorCodes.ENCODER, "JPEG compression failed")
        }
        stream.fd.sync()
      }
    } catch (e: Exception) {
      out.delete()
      throw mapError(e, "Writing ${out.name}")
    }
  }

  fun thumbnails(path: String, timesMs: List<Long>, maxWidth: Int, outputDirectory: String): List<String> {
    if (maxWidth <= 0) throw storyError(ErrorCodes.INVALID_INPUT, "maxWidth must be positive")
    val file = requireReadableFile(path, "Media file")
    val dir = File(outputDirectory)
    if (!dir.isDirectory && !dir.mkdirs()) throw storyError(ErrorCodes.IO, "Cannot create $outputDirectory")
    if (timesMs.isEmpty()) return emptyList()
    val stem = "thumb_${UUID.randomUUID().toString().take(8)}"
    if (MediaProber.probeImage(file) != null) {
      val out = File(dir, "${stem}_0.jpg")
      val bitmap = decodeImage(file, maxWidth)
      try {
        writeJpeg(bitmap, out, 85)
      } finally {
        bitmap.recycle()
      }
      return List(timesMs.size) { out.path }
    }
    val retriever = MediaMetadataRetriever()
    try {
      try {
        retriever.setDataSource(file.path)
      } catch (e: RuntimeException) {
        throw storyError(ErrorCodes.UNSUPPORTED_MEDIA, "Cannot read video: ${file.name}", e.message)
      }
      if (retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) != "yes") {
        throw storyError(ErrorCodes.UNSUPPORTED_MEDIA, "No video track: ${file.name}")
      }
      val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0
      val fps = MediaProber.trackInfo(file).frameRate ?: 30.0
      val lastFrameMs = max(0L, durationMs - (1000.0 / fps).roundToInt())
      return timesMs.mapIndexed { index, ms ->
        val timeUs = ms.coerceIn(0, lastFrameMs) * 1000
        val frame = frameAt(retriever, timeUs, maxWidth)
          ?: throw storyError(ErrorCodes.UNSUPPORTED_MEDIA, "Cannot decode a frame at $ms ms")
        val out = File(dir, "${stem}_$index.jpg")
        try {
          writeJpeg(frame, out, 85)
        } finally {
          frame.recycle()
        }
        out.path
      }
    } finally {
      retriever.release()
    }
  }

  /** A display-oriented frame at most [maxWidth] wide. */
  private fun frameAt(retriever: MediaMetadataRetriever, timeUs: Long, maxWidth: Int): Bitmap? {
    val option = MediaMetadataRetriever.OPTION_CLOSEST
    val full = retriever.getFrameAtTime(timeUs, option) ?: return null
    return scaleToWidth(full, maxWidth)
  }

  private fun scaleToWidth(bitmap: Bitmap, maxWidth: Int): Bitmap {
    if (bitmap.width <= maxWidth) return bitmap
    val height = max(1, (bitmap.height * maxWidth.toDouble() / bitmap.width).roundToInt())
    val scaled = Bitmap.createScaledBitmap(bitmap, maxWidth, height, true)
    if (scaled !== bitmap) bitmap.recycle()
    return scaled
  }

  /** Decodes an image at most [maxWidth] wide with its EXIF rotation applied. */
  fun decodeImage(file: File, maxWidth: Int): Bitmap {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(file.path, bounds)
    val rotation = MediaProber.exifRotation(file)
    val displayWidth = if (rotation % 180 == 90) bounds.outHeight else bounds.outWidth
    var sample = 1
    while (displayWidth / (sample * 2) >= maxWidth) sample *= 2
    val options = BitmapFactory.Options().apply {
      inSampleSize = sample
      if (Build.VERSION.SDK_INT >= 26) inPreferredConfig = Bitmap.Config.ARGB_8888
    }
    val decoded = BitmapFactory.decodeFile(file.path, options)
      ?: throw storyError(ErrorCodes.UNSUPPORTED_MEDIA, "Cannot decode image: ${file.name}")
    val rotated = if (rotation != 0) {
      val m = Matrix().apply { postRotate(rotation.toFloat()) }
      Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, m, true).also {
        if (it !== decoded) decoded.recycle()
      }
    } else {
      decoded
    }
    return scaleToWidth(rotated, maxWidth)
  }
}
