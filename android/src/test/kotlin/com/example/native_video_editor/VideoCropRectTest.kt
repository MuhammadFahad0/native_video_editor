package com.example.native_video_editor

import org.junit.Assert.*
import org.junit.Test

class VideoCropRectTest {

    private fun validMap() = mapOf<String, Any>(
        "left" to 0.1f,
        "top" to 0.2f,
        "width" to 0.5f,
        "height" to 0.6f,
    )

    // -- Happy path --------------------------------------------------------
    @Test
    fun `fromMap succeeds with valid values`() {
        val rect = VideoCropRect.fromMap(validMap())
        assertEquals(0.1f, rect.left)
        assertEquals(0.2f, rect.top)
        assertEquals(0.5f, rect.width)
        assertEquals(0.6f, rect.height)
    }

    @Test
    fun `fromMap accepts exact 1_0 boundary (full frame)`() {
        val rect = VideoCropRect.fromMap(
            mapOf("left" to 0f, "top" to 0f, "width" to 1f, "height" to 1f)
        )
        assertEquals(1f, rect.width)
        assertEquals(1f, rect.height)
    }

    // -- Missing key validation --------------------------------------------
    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on missing left key`() {
        VideoCropRect.fromMap(mapOf("top" to 0.2f, "width" to 0.5f, "height" to 0.6f))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on missing top key`() {
        VideoCropRect.fromMap(mapOf("left" to 0.1f, "width" to 0.5f, "height" to 0.6f))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on missing width key`() {
        VideoCropRect.fromMap(mapOf("left" to 0.1f, "top" to 0.2f, "height" to 0.6f))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on missing height key`() {
        VideoCropRect.fromMap(mapOf("left" to 0.1f, "top" to 0.2f, "width" to 0.5f))
    }

    // -- Range validation --------------------------------------------------
    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on negative left`() {
        VideoCropRect.fromMap(validMap() + mapOf("left" to -0.1f))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on negative top`() {
        VideoCropRect.fromMap(validMap() + mapOf("top" to -0.1f))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on zero width`() {
        VideoCropRect.fromMap(validMap() + mapOf("width" to 0f))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on right edge overflow`() {
        VideoCropRect.fromMap(mapOf("left" to 0.6f, "top" to 0f, "width" to 0.5f, "height" to 0.5f))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on bottom edge overflow`() {
        VideoCropRect.fromMap(mapOf("left" to 0f, "top" to 0.6f, "width" to 0.5f, "height" to 0.5f))
    }
}
