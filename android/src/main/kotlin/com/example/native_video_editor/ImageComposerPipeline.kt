package com.example.native_video_editor

import android.content.Context
import androidx.media3.common.util.UnstableApi
import io.flutter.plugin.common.MethodChannel

/** Legacy API adapter; shares encoding, progress and cancellation with compositions. */
@UnstableApi
internal class ImageComposerPipeline(private val context: Context, channel: MethodChannel) {
    private val pipeline = CompositionPipeline(context, channel)
    fun compose(request: ImageComposeRequest, onSuccess: (String) -> Unit, onFailure: (Throwable) -> Unit) {
        try {
            val full = CompositionPipeline.mediaInfo(context, request.audioPath)["durationMs"] as Long
            val duration = minOf(full, request.audioDurationMs ?: full)
            pipeline.compose(mapOf(
                "outputPath" to request.outputPath,
                "settings" to mapOf("width" to request.targetWidth, "height" to request.targetHeight,
                    "frameRate" to request.frameRate, "videoBitrate" to 4000000, "audioBitrate" to 128000),
                "clips" to listOf(mapOf("path" to request.imagePath, "isImage" to true, "durationMs" to duration, "fit" to "contain")),
                "audioTracks" to listOf(mapOf("path" to request.audioPath))
            )) { error -> if (error == null) onSuccess(request.outputPath) else onFailure(error) }
        } catch (error: Throwable) { onFailure(error) }
    }
    fun cancel() = pipeline.cancel()
}
