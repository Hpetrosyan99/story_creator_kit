package com.mabrook.story_creator_kit

import kotlin.test.Test
import kotlin.test.assertEquals

class MediaExporterTest {
  private fun apply(m: FloatArray, r: Float, g: Float, b: Float): FloatArray {
    // Column-major 4x4 times (r, g, b, 1).
    val v = floatArrayOf(r, g, b, 1f)
    return FloatArray(4) { row -> (0 until 4).sumOf { col -> (m[col * 4 + row] * v[col]).toDouble() }.toFloat() }
  }

  @Test
  fun colorMatrixMatchesFlutterSemantics() {
    val warm = listOf(
      1.10, 0.0, 0.0, 0.0, 10.0,
      0.0, 1.02, 0.0, 0.0, 4.0,
      0.0, 0.0, 0.88, 0.0, -6.0,
      0.0, 0.0, 0.0, 1.0, 0.0,
    )
    val out = apply(MediaExporter.glColorMatrix(warm), 0.5f, 0.5f, 0.5f)
    assertEquals(0.5f * 1.10f + 10f / 255f, out[0], 1e-4f)
    assertEquals(0.5f * 1.02f + 4f / 255f, out[1], 1e-4f)
    assertEquals(0.5f * 0.88f - 6f / 255f, out[2], 1e-4f)
    assertEquals(1f, out[3], 1e-6f)
  }

  @Test
  fun placementMapsInputCornersToTheRect() {
    val t = PlacementTransformation(1080, 1920, NativeRect(0.0, 656.25, 1080.0, 607.5), mirror = false)
    val m = t.getGlMatrixArray(0)
    // Input NDC (-1, 1) = top-left of the frame -> output pixel (0, 656.25).
    val x = m[0] * -1f + m[12]
    val y = m[5] * 1f + m[13]
    assertEquals(-1f, x, 1e-5f)
    assertEquals(1f - 2f * 656.25f / 1920f, y, 1e-5f)
    assertEquals(1080, t.configure(640, 360).width)
    assertEquals(1920, t.configure(640, 360).height)
  }

  @Test
  fun mirrorFlipsHorizontally() {
    val m = PlacementTransformation(1080, 1920, NativeRect(0.0, 0.0, 1080.0, 1920.0), mirror = true)
      .getGlMatrixArray(0)
    assertEquals(-1f, m[0], 1e-6f)
    assertEquals(1f, m[5], 1e-6f)
  }
}
