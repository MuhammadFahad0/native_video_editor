package com.example.native_video_editor

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Merges an audio track into an existing video file using Media3 Transformer.
 *
 * Strategy:
 *  - Video sequence: the source video with audio optionally stripped.
 *  - Audio sequence: the new audio file, clipped to match the video duration.
 *  - Media3 [Composition] muxes both sequences into a single MP4.
 *
 * Duration policy: the shorter of video / audio determines the output length
 * (audio is clipped if it is longer; the video is not extended).
 */
@UnstableApi
internal class AudioMergerPipeline(
    private val context: Context,
    private val channel: MethodChannel,
) {
    private val handler = Handler(Looper.getMainLooper())
    private var progressRunnable: Runnable? = null
    private var transformer: Transformer? = null

    @Volatile
    private var isRunning = false

    fun merge(
        request: AudioMergeRequest,
        onSuccess: (String) -> Unit,
        onFailure: (Throwable) -> Unit,
    ) {
        val outputFile = File(request.outputPath)
        outputFile.parentFile?.mkdirs()
        if (outputFile.exists() && !outputFile.delete()) {
            onFailure(IllegalStateException("Unable to replace existing output file."))
            return
        }

        // Determine the video duration so we can clip the audio to it.
        val videoDurationMs = resolveMediaDurationMs(request.inputVideoPath) ?: run {
            onFailure(IllegalStateException("Unable to determine video duration for: ${request.inputVideoPath}"))
            return
        }

        val videoUri = parseUri(request.inputVideoPath)
        val audioUri = parseUri(request.audioPath)

        // Video sequence – strip existing audio if requested.
        val videoMediaItem = MediaItem.Builder()
            .setUri(videoUri)
            .build()
        val videoEditedItem = EditedMediaItem.Builder(videoMediaItem)
            .setRemoveAudio(request.replaceExistingAudio)
            .setEffects(Effects(emptyList(), emptyList()))
            .build()

        // Audio sequence – clip to the video duration so it doesn't exceed it.
        val audioMediaItem = MediaItem.Builder()
            .setUri(audioUri)
            .setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setEndPositionMs(videoDurationMs)
                    .build()
            )
            .build()
        val audioEditedItem = EditedMediaItem.Builder(audioMediaItem)
            .setRemoveVideo(true)
            .setEffects(Effects(emptyList(), emptyList()))
            .build()

        isRunning = true

        val transformerInstance = Transformer.Builder(context)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    cleanup()
                    val exported = File(request.outputPath)
                    if (!exported.exists() || exported.length() == 0L) {
                        exported.delete()
                        onFailure(IllegalStateException("Merge failed: output file is empty or missing."))
                    } else {
                        onSuccess(request.outputPath)
                    }
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    cleanup()
                    File(request.outputPath).delete()
                    onFailure(exportException)
                }
            })
            .build()
        this.transformer = transformerInstance

        val composition = Composition.Builder(
            listOf(
                EditedMediaItemSequence(listOf(videoEditedItem)),
                EditedMediaItemSequence(listOf(audioEditedItem)),
            )
        ).build()

        transformerInstance.start(composition, request.outputPath)

        // Progress reporting loop.
        val runnable = object : Runnable {
            override fun run() {
                if (!isRunning) return
                val progressHolder = ProgressHolder()
                val state = transformerInstance.getProgress(progressHolder)
                if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
                    val progress = progressHolder.progress / 100.0
                    channel.invokeMethod(
                        "onProgress",
                        mapOf("outputPath" to request.outputPath, "progress" to progress)
                    )
                }
                if (state != Transformer.PROGRESS_STATE_UNAVAILABLE && isRunning) {
                    handler.postDelayed(this, 250)
                }
            }
        }
        progressRunnable = runnable
        handler.post(runnable)
    }

    fun cancel() {
        if (!isRunning) return
        isRunning = false
        cleanup()
        try {
            transformer?.cancel()
        } catch (_: Exception) { /* ignore */ }
    }

    private fun cleanup() {
        isRunning = false
        progressRunnable?.let { handler.removeCallbacks(it) }
        progressRunnable = null
        transformer = null
    }

    private fun resolveMediaDurationMs(path: String): Long? {
        val retriever = android.media.MediaMetadataRetriever()
        return try {
            if (path.startsWith("content://")) {
                retriever.setDataSource(context, parseUri(path))
            } else {
                retriever.setDataSource(path)
            }
            retriever
                .extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull()
        } catch (_: Exception) {
            null
        } finally {
            retriever.release()
        }
    }

    private fun parseUri(path: String): Uri =
        if (path.startsWith("content://") || path.startsWith("file://")) Uri.parse(path)
        else Uri.fromFile(File(path))
}
