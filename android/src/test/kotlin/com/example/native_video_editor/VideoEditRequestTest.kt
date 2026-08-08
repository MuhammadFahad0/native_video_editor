package com.example.native_video_editor

import org.junit.Assert.*
import org.junit.Test

class VideoEditRequestTest {

    private fun validBase() = mapOf<String, Any>(
        "inputPath" to "/tmp/input.mp4",
        "outputPath" to "/tmp/output.mp4",
    )

    // -- Happy path --------------------------------------------------------
    @Test
    fun `fromMap succeeds with all fields`() {
        val map = mapOf<String, Any>(
            "inputPath" to "/tmp/input.mp4",
            "outputPath" to "/tmp/output.mp4",
            "trimStartMs" to 1000L,
            "trimEndMs" to 5000L,
            "targetWidth" to 1280,
            "targetHeight" to 720,
            "rotationDegrees" to 90,
            "speedMultiplier" to 1.5f,
            "muteAudio" to true,
        )
        val req = VideoEditRequest.fromMap(map)
        assertEquals("/tmp/input.mp4", req.inputPath)
        assertEquals("/tmp/output.mp4", req.outputPath)
        assertEquals(1000L, req.trimStartMs)
        assertEquals(5000L, req.trimEndMs)
        assertEquals(1280, req.targetWidth)
        assertEquals(720, req.targetHeight)
        assertEquals(90, req.rotationDegrees)
        assertEquals(1.5f, req.speedMultiplier)
        assertTrue(req.muteAudio)
    }

    @Test
    fun `fromMap succeeds with minimal fields and applies defaults`() {
        val req = VideoEditRequest.fromMap(validBase())
        assertNull(req.trimStartMs)
        assertNull(req.trimEndMs)
        assertNull(req.cropRect)
        assertNull(req.targetWidth)
        assertNull(req.targetHeight)
        assertEquals(0, req.rotationDegrees)
        assertEquals(1.0f, req.speedMultiplier)
        assertFalse(req.muteAudio)
    }

    // -- Path validation ---------------------------------------------------
    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on null inputPath`() {
        VideoEditRequest.fromMap(mapOf("outputPath" to "/tmp/output.mp4"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on blank inputPath`() {
        VideoEditRequest.fromMap(mapOf("inputPath" to "   ", "outputPath" to "/tmp/output.mp4"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on null outputPath`() {
        VideoEditRequest.fromMap(mapOf("inputPath" to "/tmp/input.mp4"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on same canonical path`() {
        VideoEditRequest.fromMap(mapOf("inputPath" to "/tmp/video.mp4", "outputPath" to "/tmp/video.mp4"))
    }

    // -- Trim validation ---------------------------------------------------
    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on negative trimStartMs`() {
        VideoEditRequest.fromMap(validBase() + mapOf("trimStartMs" to -1L))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on negative trimEndMs`() {
        VideoEditRequest.fromMap(validBase() + mapOf("trimEndMs" to -1L))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on trimStart equal to trimEnd`() {
        VideoEditRequest.fromMap(validBase() + mapOf("trimStartMs" to 3000L, "trimEndMs" to 3000L))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on trimStart greater than trimEnd`() {
        VideoEditRequest.fromMap(validBase() + mapOf("trimStartMs" to 5000L, "trimEndMs" to 1000L))
    }

    // -- Dimension validation ----------------------------------------------
    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws when only targetWidth is provided`() {
        VideoEditRequest.fromMap(validBase() + mapOf("targetWidth" to 1280))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws when only targetHeight is provided`() {
        VideoEditRequest.fromMap(validBase() + mapOf("targetHeight" to 720))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on odd targetWidth`() {
        VideoEditRequest.fromMap(validBase() + mapOf("targetWidth" to 721, "targetHeight" to 720))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on odd targetHeight`() {
        VideoEditRequest.fromMap(validBase() + mapOf("targetWidth" to 1280, "targetHeight" to 721))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on zero targetWidth`() {
        VideoEditRequest.fromMap(validBase() + mapOf("targetWidth" to 0, "targetHeight" to 720))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on zero targetHeight`() {
        VideoEditRequest.fromMap(validBase() + mapOf("targetWidth" to 1280, "targetHeight" to 0))
    }

    // -- Rotation validation -----------------------------------------------
    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on invalid rotation 45`() {
        VideoEditRequest.fromMap(validBase() + mapOf("rotationDegrees" to 45))
    }

    @Test
    fun `fromMap accepts all valid rotations`() {
        for (deg in listOf(0, 90, 180, 270)) {
            val req = VideoEditRequest.fromMap(validBase() + mapOf("rotationDegrees" to deg))
            assertEquals(deg, req.rotationDegrees)
        }
    }

    // -- Speed validation --------------------------------------------------
    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on speed below 0_25`() {
        VideoEditRequest.fromMap(validBase() + mapOf("speedMultiplier" to 0.1f))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `fromMap throws on speed above 4_0`() {
        VideoEditRequest.fromMap(validBase() + mapOf("speedMultiplier" to 4.1f))
    }

    @Test
    fun `fromMap accepts boundary speeds`() {
        val low = VideoEditRequest.fromMap(validBase() + mapOf("speedMultiplier" to 0.25f))
        assertEquals(0.25f, low.speedMultiplier)
        val high = VideoEditRequest.fromMap(validBase() + mapOf("speedMultiplier" to 4.0f))
        assertEquals(4.0f, high.speedMultiplier)
    }

    @Test
    fun `fromMap parses nested cropRect sub-map`() {
        val map = validBase() + mapOf(
            "cropRect" to mapOf(
                "left" to 0.1f, "top" to 0.2f, "width" to 0.5f, "height" to 0.6f,
            )
        )
        val req = VideoEditRequest.fromMap(map)
        assertNotNull(req.cropRect)
        assertEquals(0.1f, req.cropRect!!.left)
    }
}
