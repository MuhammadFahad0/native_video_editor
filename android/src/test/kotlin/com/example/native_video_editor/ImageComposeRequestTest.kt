package com.example.native_video_editor

import org.junit.Assert.assertEquals
import org.junit.Test

class ImageComposeRequestTest {
    private fun request(output: String) = mapOf<String, Any>(
        "imagePath" to "/tmp/source.png", "audioPath" to "/tmp/music.wav",
        "outputPath" to output, "targetWidth" to 640, "targetHeight" to 360,
    )

    @Test(expected = IllegalArgumentException::class)
    fun `cannot overwrite source image`() { ImageComposeRequest.fromMap(request("/tmp/source.png")) }

    @Test(expected = IllegalArgumentException::class)
    fun `cannot overwrite audio through a path alias`() { ImageComposeRequest.fromMap(request("/tmp/./music.wav")) }

    @Test
    fun `valid destination preserves defaults`() {
        val parsed = ImageComposeRequest.fromMap(request("/tmp/out.mp4"))
        assertEquals(30, parsed.frameRate)
        assertEquals(640, parsed.targetWidth)
    }
}
