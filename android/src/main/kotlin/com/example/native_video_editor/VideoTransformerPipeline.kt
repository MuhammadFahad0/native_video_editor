package com.example.native_video_editor

import android.content.Context
import android.net.Uri
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Crop
import androidx.media3.effect.Presentation
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import java.io.File

@UnstableApi
internal class VideoTransformerPipeline(private val context: Context) {
    fun process(
        request: VideoEditRequest,
        onSuccess: (String) -> Unit,
        onFailure: (Throwable) -> Unit,
    ) {
        val outputFile = File(request.outputPath)
        outputFile.parentFile?.mkdirs()
        if (outputFile.exists() && !outputFile.delete()) {
            onFailure(IllegalStateException("Unable to replace existing output file."))
            return
        }

        val mediaItem = MediaItem.Builder()
            .setUri(Uri.fromFile(File(request.inputPath)))
            .apply {
                if (request.trimStartMs != null || request.trimEndMs != null) {
                    setClippingConfiguration(
                        MediaItem.ClippingConfiguration.Builder()
                            .apply {
                                request.trimStartMs?.let(::setStartPositionMs)
                                request.trimEndMs?.let(::setEndPositionMs)
                            }
                            .build(),
                    )
                }
            }
            .build()

        val videoEffects = buildVideoEffects(request)
        val editedMediaItem = EditedMediaItem.Builder(mediaItem)
            .setRemoveAudio(request.muteAudio)
            .setEffects(Effects(listOf(), videoEffects))
            .build()

        val transformer = Transformer.Builder(context)
            .addListener(
                object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        onSuccess(request.outputPath)
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException,
                    ) {
                        onFailure(exportException)
                    }
                },
            )
            .build()

        transformer.start(editedMediaItem, request.outputPath)
    }

    private fun buildVideoEffects(request: VideoEditRequest): List<Effect> {
        val effects = mutableListOf<Effect>()

        request.cropRect?.let { rect ->
            val left = rect.left * 2f - 1f
            val right = (rect.left + rect.width) * 2f - 1f
            val top = 1f - rect.top * 2f
            val bottom = 1f - (rect.top + rect.height) * 2f
            effects += Crop(left, right, bottom, top)
        }

        if (request.rotationDegrees != 0) {
            effects += ScaleAndRotateTransformation.Builder()
                .setRotationDegrees(request.rotationDegrees.toFloat())
                .build()
        }

        if (request.targetWidth != null && request.targetHeight != null) {
            effects += Presentation.createForWidthAndHeight(
                request.targetWidth,
                request.targetHeight,
                Presentation.LAYOUT_SCALE_TO_FIT,
            )
        }

        return effects
    }
}
