package com.mabrook.story_creator_kit

import android.graphics.BitmapFactory
import android.media.ExifInterface
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import java.io.File

/** Reads dimensions, duration, rotation and tracks of images and videos. */
internal object MediaProber {
  fun probe(path: String): NativeMediaProbe {
    val file = requireReadableFile(path, "Media file")
    probeImage(file)?.let { return it }
    return probeMedia(file)
  }

  /** Image facts, or null when [file] is not a decodable image. */
  fun probeImage(file: File): NativeMediaProbe? {
    val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(file.path, options)
    if (options.outWidth <= 0 || options.outHeight <= 0) return null
    val rotation = exifRotation(file)
    val swaps = rotation == 90 || rotation == 270
    return NativeMediaProbe(
      width = (if (swaps) options.outHeight else options.outWidth).toLong(),
      height = (if (swaps) options.outWidth else options.outHeight).toLong(),
      fileSizeBytes = file.length(),
      rotationDegrees = rotation.toLong(),
      hasVideo = false,
      hasAudio = false,
    )
  }

  fun exifRotation(file: File): Int = try {
    when (ExifInterface(file.path).getAttributeInt(
      ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL,
    )) {
      ExifInterface.ORIENTATION_ROTATE_180, ExifInterface.ORIENTATION_FLIP_VERTICAL -> 180
      ExifInterface.ORIENTATION_ROTATE_90, ExifInterface.ORIENTATION_TRANSPOSE -> 90
      ExifInterface.ORIENTATION_ROTATE_270, ExifInterface.ORIENTATION_TRANSVERSE -> 270
      else -> 0
    }
  } catch (_: Exception) {
    0
  }

  private fun probeMedia(file: File): NativeMediaProbe {
    val retriever = MediaMetadataRetriever()
    try {
      try {
        retriever.setDataSource(file.path)
      } catch (e: RuntimeException) {
        throw storyError(ErrorCodes.UNSUPPORTED_MEDIA, "Cannot read media: ${file.name}", e.message)
      }
      val hasVideo = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes"
      val hasAudio = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"
      if (!hasVideo && !hasAudio) {
        throw storyError(ErrorCodes.UNSUPPORTED_MEDIA, "No audio or video track: ${file.name}")
      }
      val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
      var width = 0L
      var height = 0L
      var rotation = 0
      if (hasVideo) {
        width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toLongOrNull() ?: 0
        height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toLongOrNull() ?: 0
        rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
        rotation = ((rotation % 360) + 360) % 360
        if (rotation == 90 || rotation == 270) {
          val w = width
          width = height
          height = w
        }
      }
      val tracks = trackInfo(file)
      return NativeMediaProbe(
        width = width,
        height = height,
        fileSizeBytes = file.length(),
        rotationDegrees = rotation.toLong(),
        hasVideo = hasVideo,
        hasAudio = hasAudio,
        durationMs = duration,
        videoCodec = tracks.videoMime,
        audioCodec = tracks.audioMime,
        frameRate = tracks.frameRate,
      )
    } finally {
      retriever.release()
    }
  }

  data class TrackInfo(
    val videoMime: String?,
    val audioMime: String?,
    val frameRate: Double?,
    val audioChannels: Int?,
    val audioSampleRate: Int?,
  )

  fun trackInfo(file: File): TrackInfo {
    val extractor = MediaExtractor()
    return try {
      extractor.setDataSource(file.path)
      var videoMime: String? = null
      var audioMime: String? = null
      var frameRate: Double? = null
      var channels: Int? = null
      var sampleRate: Int? = null
      for (i in 0 until extractor.trackCount) {
        val format = extractor.getTrackFormat(i)
        val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
        if (mime.startsWith("video/") && videoMime == null) {
          videoMime = mime
          if (format.containsKey(MediaFormat.KEY_FRAME_RATE)) {
            frameRate = try {
              format.getInteger(MediaFormat.KEY_FRAME_RATE).toDouble()
            } catch (_: ClassCastException) {
              format.getFloat(MediaFormat.KEY_FRAME_RATE).toDouble()
            }
          }
        } else if (mime.startsWith("audio/") && audioMime == null) {
          audioMime = mime
          if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
          if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        }
      }
      TrackInfo(videoMime, audioMime, frameRate, channels, sampleRate)
    } catch (_: Exception) {
      TrackInfo(null, null, null, null, null)
    } finally {
      extractor.release()
    }
  }
}
