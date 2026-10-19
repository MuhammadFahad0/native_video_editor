package com.example.native_video_editor

import android.content.Context
import android.media.MediaMetadataRetriever
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.OverlaySettings
import androidx.media3.common.VideoCompositorSettings
import androidx.media3.common.audio.ChannelMixingAudioProcessor
import androidx.media3.common.audio.ChannelMixingMatrix
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.transformer.*
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.CancellationException

@UnstableApi
internal class CompositionPipeline(private val context: Context, private val channel: MethodChannel) {
    private val handler = Handler(Looper.getMainLooper())
    private var transformer: Transformer? = null
    private var completion: ((Throwable?) -> Unit)? = null
    private var output: File? = null
    private val temporaryFiles = mutableListOf<File>()
    private var finished = false

    fun compose(args: Map<*, *>, done: (Throwable?) -> Unit) {
        completion = done
        try {
            val path = args.string("outputPath")
            val clips = args.maps("clips")
            val overlays = args.maps("overlays")
            val audio = args.maps("audioTracks")
            require(clips.isNotEmpty()) { "At least one clip is required." }
            val destination = File(path).canonicalFile
            for (source in clips + overlays + audio) {
                val sourcePath = source["path"] as? String ?: continue
                require(File(sourcePath).canonicalFile != destination) { "Output must differ from all source files." }
            }
            val settings = args["settings"] as Map<*, *>
            val width = settings.long("width").toInt()
            val height = settings.long("height").toInt()
            val fps = settings.long("frameRate").toInt()
            require(width in 2..8192 && height in 2..8192 && width % 2 == 0 && height % 2 == 0)
            require(fps in 1..120 && settings.long("videoBitrate") > 0 && settings.long("audioBitrate") > 0)

            val main = EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_AUDIO, C.TRACK_TYPE_VIDEO))
            var totalMs = 0L
            for (clip in clips) {
                val duration = sourceDuration(clip)
                main.addItem(item(clip, duration, width, height, fps, false))
                totalMs += duration
            }
            val sequences = mutableListOf<EditedMediaItemSequence>()
            val visibleOverlays = overlays.filter { it.long("startMs") < totalMs }.reversed()
            val overlayEnds = mutableListOf<Long>()
            for (overlay in visibleOverlays) {
                val source = overlay.toMutableMap()
                val bytes = overlay["imageBytes"] as? ByteArray
                if (bytes != null) {
                    val file = File.createTempFile("nve-caption-", ".png", context.cacheDir)
                    temporaryFiles.add(file)
                    file.writeBytes(bytes)
                    source["path"] = file.path
                }
                val isImage = overlay["type"] != "video"
                source["isImage"] = isImage
                source["volume"] = 0.0
                val start = overlay.long("startMs")
                val duration = if (isImage) minOf(overlay.long("durationMs", totalMs - start), totalMs - start)
                    else minOf(sourceDuration(source), totalMs - start)
                require(duration > 0)
                overlayEnds.add(start + duration)
                val rect = overlay["rect"] as Map<*, *>
                val ow = maxOf(2, (width * rect.double("width")).toInt() / 2 * 2)
                val oh = maxOf(2, (height * rect.double("height")).toInt() / 2 * 2)
                val builder = EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_VIDEO))
                if (start > 0) builder.addGap(start * 1000)
                builder.addItem(item(source, duration, ow, oh, fps, true, width, height))
                if (start + duration < totalMs) builder.addGap((totalMs - start - duration) * 1000)
                sequences.add(builder.build())
            }
            sequences.add(main.build())
            for (track in audio) {
                val start = track.long("startMs")
                if (start >= totalMs) continue
                val segment = sourceDuration(track)
                var remaining = totalMs - start
                val builder = EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_AUDIO))
                if (start > 0) builder.addGap(start * 1000)
                do {
                    val duration = minOf(segment, remaining)
                    builder.addItem(audioItem(track, duration))
                    remaining -= duration
                } while (track["loop"] == true && remaining > 0)
                if (remaining > 0) builder.addGap(remaining * 1000)
                sequences.add(builder.build())
            }
            val composition = Composition.Builder(sequences)
                .setVideoCompositorSettings(object : VideoCompositorSettings {
                    override fun getOutputSize(inputSizes: List<Size>): Size = Size(width, height)
                    override fun getOverlaySettings(inputId: Int, presentationTimeUs: Long): OverlaySettings {
                        if (inputId >= visibleOverlays.size) return StaticOverlaySettings.Builder().build()
                        val overlay = visibleOverlays[inputId]
                        val rect = overlay["rect"] as Map<*, *>
                        val time = presentationTimeUs / 1000
                        val alpha = if (time >= overlay.long("startMs") && time < overlayEnds[inputId])
                            overlay.double("opacity", 1.0).toFloat() else 0f
                        return StaticOverlaySettings.Builder().setAlphaScale(alpha)
                            .setScale(rect.double("width").toFloat(), rect.double("height").toFloat())
                            .setOverlayFrameAnchor(0f, 0f)
                            .setBackgroundFrameAnchor(
                                (2 * (rect.double("left") + rect.double("width") / 2) - 1).toFloat(),
                                (1 - 2 * (rect.double("top") + rect.double("height") / 2)).toFloat())
                            .build()
                    }
                }).build()
            destination.parentFile?.mkdirs()
            require(!destination.exists() || destination.delete()) { "Cannot replace output file." }
            output = destination
            transformer = Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264).setAudioMimeType(MimeTypes.AUDIO_AAC)
                .setEncoderFactory(DefaultEncoderFactory.Builder(context)
                    .setEnableFallback(false)
                    .setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder()
                        .setBitrate(settings.long("videoBitrate").toInt()).build())
                    .setRequestedAudioEncoderSettings(AudioEncoderSettings.Builder()
                        .setBitrate(settings.long("audioBitrate").toInt()).build()).build())
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        finish(if (destination.length() > 0) null else IllegalStateException("Empty export."))
                    }
                    override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                        finish(exportException)
                    }
                }).build()
            transformer!!.start(composition, path)
            handler.post(object : Runnable {
                override fun run() {
                    if (finished) return
                    val holder = ProgressHolder()
                    if (transformer?.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                        channel.invokeMethod("onProgress", mapOf("outputPath" to path, "progress" to holder.progress / 100.0))
                    }
                    handler.postDelayed(this, 250)
                }
            })
        } catch (error: Throwable) { finish(error) }
    }

    fun cancel() {
        if (finished) return
        transformer?.cancel()
        finish(CancellationException("Composition cancelled."))
    }

    private fun finish(error: Throwable?) {
        if (finished) return
        finished = true
        transformer = null
        if (error != null) output?.delete()
        temporaryFiles.forEach { it.delete() }
        completion?.invoke(error)
        completion = null
    }

    private fun sourceDuration(source: Map<*, *>): Long {
        if (source["isImage"] == true) return source.long("durationMs").also { require(it > 0) }
        val full = (mediaInfo(context, source.string("path"))["durationMs"] as Long)
        val remaining = full - source.long("trimStartMs")
        require(remaining > 0) { "Source trim start exceeds its duration." }
        return minOf(source.long("durationMs", remaining), remaining).also { require(it > 0) }
    }

    private fun item(source: Map<*, *>, duration: Long, width: Int, height: Int, fps: Int,
                     overlay: Boolean, canvasWidth: Int = width, canvasHeight: Int = height): EditedMediaItem {
        val isImage = source["isImage"] == true
        val media = MediaItem.Builder().setUri(uri(source.string("path")))
        if (isImage) media.setImageDurationMs(duration)
        else media.setClippingConfiguration(clipping(source.long("trimStartMs"), duration))
        val effects = mutableListOf<androidx.media3.common.Effect>()
        if (source["flipHorizontal"] == true || source["flipVertical"] == true) {
            effects.add(ScaleAndRotateTransformation.Builder().setScale(
                if (source["flipHorizontal"] == true) -1f else 1f,
                if (source["flipVertical"] == true) -1f else 1f).build())
        }
        val layout = when (source["fit"]) {
            "cover" -> Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP
            "stretch" -> Presentation.LAYOUT_STRETCH_TO_FIT
            else -> Presentation.LAYOUT_SCALE_TO_FIT
        }
        effects.add(Presentation.createForWidthAndHeight(width, height, layout))
        if (overlay) effects.add(Presentation.createForWidthAndHeight(canvasWidth, canvasHeight, Presentation.LAYOUT_STRETCH_TO_FIT))
        return EditedMediaItem.Builder(media.build()).setDurationUs(duration * 1000).setFrameRate(fps)
            .setRemoveAudio(isImage || overlay || source.double("volume", 1.0) == 0.0)
            .setEffects(Effects(volumeProcessors(source.double("volume", 1.0)), effects)).build()
    }

    private fun audioItem(source: Map<*, *>, duration: Long): EditedMediaItem =
        EditedMediaItem.Builder(MediaItem.Builder().setUri(uri(source.string("path")))
            .setClippingConfiguration(clipping(source.long("trimStartMs"), duration)).build())
            .setRemoveVideo(true).setEffects(Effects(volumeProcessors(source.double("volume", 1.0)), emptyList())).build()

    private fun volumeProcessors(volume: Double): List<androidx.media3.common.audio.AudioProcessor> {
        if (volume == 1.0) return emptyList()
        val processor = ChannelMixingAudioProcessor()
        for (channels in 1..8) processor.putChannelMixingMatrix(ChannelMixingMatrix(channels, channels,
            FloatArray(channels * channels) { if (it / channels == it % channels) volume.toFloat() else 0f }))
        return listOf(processor)
    }

    private fun clipping(start: Long, duration: Long) = MediaItem.ClippingConfiguration.Builder()
        .setStartPositionMs(start).setEndPositionMs(start + duration).build()

    companion object {
        fun mediaInfo(context: Context, path: String): Map<String, Any?> {
            val reader = MediaMetadataRetriever()
            try {
                if (path.startsWith("content://")) reader.setDataSource(context, Uri.parse(path))
                else reader.setDataSource(if (path.startsWith("file://")) Uri.parse(path).path else path)
                fun metadata(key: Int) = reader.extractMetadata(key)
                val info = mutableMapOf<String, Any?>("durationMs" to (metadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLong() ?: 0L),
                    "width" to metadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toInt(),
                    "height" to metadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toInt(),
                    "rotationDegrees" to metadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toInt(),
                    "frameRate" to metadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)?.toDouble(),
                    "bitrate" to metadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toLong(),
                    "hasAudio" to (metadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"))
                val extractor = MediaExtractor()
                val audioTracks = mutableListOf<Map<String, Any?>>()
                try {
                    extractor.setDataSource(context, uri(path), null)
                    for (index in 0 until extractor.trackCount) {
                        val format = extractor.getTrackFormat(index)
                        val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                        if (mime.startsWith("video/")) {
                            info["videoCodec"] = mime
                            if (format.containsKey(MediaFormat.KEY_FRAME_RATE)) info["frameRate"] = format.getInteger(MediaFormat.KEY_FRAME_RATE).toDouble()
                        } else if (mime.startsWith("audio/")) {
                            if (info["audioCodec"] == null) info["audioCodec"] = mime
                            fun optionalInt(key: String) = if (format.containsKey(key)) format.getInteger(key) else null
                            audioTracks.add(mapOf("index" to index, "codec" to mime,
                                "sampleRate" to optionalInt(MediaFormat.KEY_SAMPLE_RATE),
                                "channelCount" to optionalInt(MediaFormat.KEY_CHANNEL_COUNT),
                                "bitrate" to optionalInt(MediaFormat.KEY_BIT_RATE),
                                "language" to if (format.containsKey(MediaFormat.KEY_LANGUAGE)) format.getString(MediaFormat.KEY_LANGUAGE) else null))
                        }
                    }
                } finally { extractor.release() }
                info["audioTracks"] = audioTracks
                return info
            } finally { reader.release() }
        }
        private fun uri(path: String) = if (path.contains("://")) Uri.parse(path) else Uri.fromFile(File(path))
    }
}

private fun Map<*, *>.string(key: String) = (this[key] as? String)?.also { require(it.isNotBlank()) }
    ?: throw IllegalArgumentException("$key is required.")
private fun Map<*, *>.long(key: String, default: Long = 0L) = (this[key] as? Number)?.toLong() ?: default
private fun Map<*, *>.double(key: String, default: Double = 0.0) = (this[key] as? Number)?.toDouble() ?: default
private fun Map<*, *>.maps(key: String) = (this[key] as? List<*>)?.map { it as Map<*, *> } ?: emptyList()
