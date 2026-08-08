package com.example.native_video_editor

import org.junit.Assert.*
import org.junit.Test

class VideoThumbnailRequestTest {

    private fun validBase() = mapOf<String, Any>(
        "inputPath" to "/tmp/input.mp4",
        "outputPath" to "/tmp/thumb.jpg",
    )

    // -- Happy path --------------------------------------------------------
    @Test
    fun `fromMap succeeds with all fields`() {
        val map = validBase() + mapOf("positionMs" to 2000L, "quality" to 80)
        val req = VideoThumbnailRequest.fromMap(map)
        assertEquals("/tmp/input.mp4", req.inputPath)
        assertEquals("/tmp/thumb.jpg", req.outputPath)
        assertEquals(2000L, req.positionMs)
        assertEquals(80, req.quality)
    }

    @Test
    fun `fromMap uses default positionMs 0`() {
        val req = VideoThumbnailRequest.fromMap(validBase())
        assertEquals(0L, req.positionMs)
    }

    @Test
    fun `fromMap uses default quality 90`() {
        val req = VideoThumbnailRequest.fromMap(validBase())
        assertEquals(90, req.quality)
    }

    // -- Path validation ---------------------------------------------------
    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on null inputPath`() {
        VideoThumbnailRequest.fromMap(mapOf("outputPath" to "/tmp/thumb.jpg"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on blank inputPath`() {
        VideoThumbnailRequest.fromMap(mapOf("inputPath" to "   ", "outputPath" to "/tmp/thumb.jpg"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on same path`() {
        VideoThumbnailRequest.fromMap(mapOf("inputPath" to "/tmp/thumb.jpg", "outputPath" to "/tmp/thumb.jpg"))
    }

    // -- Position validation -----------------------------------------------
    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on negative positionMs`() {
        VideoThumbnailRequest.fromMap(validBase() + mapOf("positionMs" to -1L))
    }

    // -- Quality validation ------------------------------------------------
    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on quality 0`() {
        VideoThumbnailRequest.fromMap(validBase() + mapOf("quality" to 0))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on quality 101`() {
        VideoThumbnailRequest.fromMap(validBase() + mapOf("quality" to 101))
    }

    @Test
    fun `fromMap accepts quality boundary values`() {
        val low = VideoThumbnailRequest.fromMap(validBase() + mapOf("quality" to 1))
        assertEquals(1, low.quality)
        val high = VideoThumbnailRequest.fromMap(validBase() + mapOf("quality" to 100))
        assertEquals(100, high.quality)
    }
}
