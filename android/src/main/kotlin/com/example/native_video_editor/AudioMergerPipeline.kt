package com.example.native_video_editor

import android.content.Context
import androidx.media3.common.util.UnstableApi
import io.flutter.plugin.common.MethodChannel

@UnstableApi
internal class AudioMergerPipeline(private val context: Context, channel: MethodChannel) {
    private val pipeline = CompositionPipeline(context, channel)
    fun merge(request: AudioMergeRequest, onSuccess: (String) -> Unit, onFailure: (Throwable) -> Unit) {
        try {
            val video = CompositionPipeline.mediaInfo(context, request.inputVideoPath)
            val audio = CompositionPipeline.mediaInfo(context, request.audioPath)
            val duration = minOf(video["durationMs"] as Long, audio["durationMs"] as Long)
            var width = (video["width"] as? Int) ?: 1280
            var height = (video["height"] as? Int) ?: 720
            if (video["rotationDegrees"] == 90 || video["rotationDegrees"] == 270) { val tmp = width; width = height; height = tmp }
            pipeline.compose(mapOf(
                "outputPath" to request.outputPath,
                "settings" to mapOf("width" to (width / 2 * 2), "height" to (height / 2 * 2),
                    "frameRate" to 30, "videoBitrate" to 4000000, "audioBitrate" to 128000),
                "clips" to listOf(mapOf("path" to request.inputVideoPath, "durationMs" to duration,
                    "volume" to if (request.replaceExistingAudio) 0.0 else 1.0)),
                "audioTracks" to listOf(mapOf("path" to request.audioPath))
            )) { error -> if (error == null) onSuccess(request.outputPath) else onFailure(error) }
        } catch (error: Throwable) { onFailure(error) }
    }
    fun cancel() = pipeline.cancel()
}
