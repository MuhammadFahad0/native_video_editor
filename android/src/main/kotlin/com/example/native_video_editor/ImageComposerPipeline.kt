package com.example.native_video_editor

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Encodes a still image + audio file into an MP4 video using Media3 Transformer.
 *
 * Strategy:
 *  1. Read the audio duration (or use [ImageComposeRequest.audioDurationMs] if set).
 *  2. Build a [MediaItem] from the image URI with the computed duration.
 *  3. Build a [MediaItem] from the audio URI.
 *  4. Compose them via [Transformer] using a [Composition] of two [EditedMediaItem] sequences.
 *
 * Media3 1.3+ supports still-image inputs natively when you set
 * [MediaItem.Builder.setImageDurationMs]. The transformer renders the image for
 * that duration and muxes the audio alongside it.
 */
@UnstableApi
internal class ImageComposerPipeline(
    private val context: Context,
    private val channel: MethodChannel,
) {
    private val handler = Handler(Looper.getMainLooper())
    private var progressRunnable: Runnable? = null
    private var transformer: Transformer? = null

    @Volatile
    private var isRunning = false

    fun compose(
        request: ImageComposeRequest,
        onSuccess: (String) -> Unit,
        onFailure: (Throwable) -> Unit,
    ) {
        val outputFile = File(request.outputPath)
        outputFile.parentFile?.mkdirs()
        if (outputFile.exists() && !outputFile.delete()) {
            onFailure(IllegalStateException("Unable to replace existing output file."))
            return
        }

        // Validate that the image is readable and decodable.
        val imageFile = File(request.imagePath)
        if (!imageFile.exists()) {
            onFailure(IllegalArgumentException("imagePath does not exist: ${request.imagePath}"))
            return
        }
        // Quick dimension check — BitmapFactory.Options with inJustDecodeBounds avoids full decode.
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(request.imagePath, opts)
        if (opts.outWidth <= 0 || opts.outHeight <= 0) {
            onFailure(IllegalArgumentException("imagePath is not a valid image: ${request.imagePath}"))
            return
        }

        // Determine the audio duration if not explicitly provided.
        val audioDurationMs: Long = if (request.audioDurationMs != null) {
            request.audioDurationMs
        } else {
            resolveAudioDurationMs(request.audioPath) ?: run {
                onFailure(IllegalStateException("Unable to determine audio duration for: ${request.audioPath}"))
                return
            }
        }

        val imageUri = Uri.fromFile(imageFile)
        val audioUri = parseUri(request.audioPath)

        // Image sequence: a single still image rendered for audioDurationMs.
        val imageMediaItem = MediaItem.Builder()
            .setUri(imageUri)
            .setMimeType(MimeTypes.IMAGE_JPEG) // Transformer accepts JPEG/PNG via this hint.
            .setImageDurationMs(audioDurationMs)
            .build()
        val imageEditedItem = EditedMediaItem.Builder(imageMediaItem)
            .setRemoveAudio(true)          // Image items have no audio track.
            .setFrameRate(request.frameRate)
            .setDurationUs(audioDurationMs * 1_000L)
            .setEffects(Effects(emptyList(), emptyList()))
            .build()

        // Audio sequence: the audio file with its own duration.
        val audioMediaItem = MediaItem.Builder()
            .setUri(audioUri)
            .apply {
                // Trim audio to audioDurationMs to keep it in sync.
                setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder()
                        .setEndPositionMs(audioDurationMs)
                        .build()
                )
            }
            .build()
        val audioEditedItem = EditedMediaItem.Builder(audioMediaItem)
            .setRemoveVideo(true)          // Audio-only sequence.
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
                        onFailure(IllegalStateException("Compose failed: output file is empty or missing."))
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
                androidx.media3.transformer.EditedMediaItemSequence(listOf(imageEditedItem)),
                androidx.media3.transformer.EditedMediaItemSequence(listOf(audioEditedItem)),
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

    /**
     * Uses [android.media.MediaMetadataRetriever] to read the audio duration.
     * Returns `null` if the duration cannot be determined.
     */
    private fun resolveAudioDurationMs(path: String): Long? {
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
