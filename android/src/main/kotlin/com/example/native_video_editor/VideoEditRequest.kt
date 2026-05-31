package com.example.native_video_editor

import java.io.File

internal data class VideoEditRequest(
    val inputPath: String,
    val outputPath: String,
    val trimStartMs: Long?,
    val trimEndMs: Long?,
    val cropRect: VideoCropRect?,
    val targetWidth: Int?,
    val targetHeight: Int?,
    val rotationDegrees: Int,
    val muteAudio: Boolean,
) {
    companion object {
        fun fromMap(map: Map<*, *>): VideoEditRequest {
            val inputPath = map["inputPath"] as? String
            val outputPath = map["outputPath"] as? String
            require(!inputPath.isNullOrBlank()) { "inputPath is required." }
            require(!outputPath.isNullOrBlank()) { "outputPath is required." }

            val trimStartMs = (map["trimStartMs"] as? Number)?.toLong()
            val trimEndMs = (map["trimEndMs"] as? Number)?.toLong()
            val targetWidth = (map["targetWidth"] as? Number)?.toInt()
            val targetHeight = (map["targetHeight"] as? Number)?.toInt()
            val rotationDegrees = (map["rotationDegrees"] as? Number)?.toInt() ?: 0
            val cropMap = map["cropRect"] as? Map<*, *>

            require(File(inputPath).canonicalPath != File(outputPath).canonicalPath) {
                "inputPath and outputPath must be different files."
            }
            require(trimStartMs == null || trimStartMs >= 0) { "trimStartMs must not be negative." }
            require(trimEndMs == null || trimEndMs >= 0) { "trimEndMs must not be negative." }
            require(trimStartMs == null || trimEndMs == null || trimStartMs < trimEndMs) {
                "trimStartMs must be earlier than trimEndMs."
            }
            require((targetWidth == null) == (targetHeight == null)) {
                "targetWidth and targetHeight must be provided together."
            }
            require(targetWidth == null || (targetWidth > 0 && targetWidth % 2 == 0)) {
                "targetWidth must be a positive even number."
            }
            require(targetHeight == null || (targetHeight > 0 && targetHeight % 2 == 0)) {
                "targetHeight must be a positive even number."
            }
            require(rotationDegrees in setOf(0, 90, 180, 270)) {
                "rotationDegrees must be one of 0, 90, 180, or 270."
            }

            return VideoEditRequest(
                inputPath = inputPath,
                outputPath = outputPath,
                trimStartMs = trimStartMs,
                trimEndMs = trimEndMs,
                cropRect = cropMap?.let(VideoCropRect::fromMap),
                targetWidth = targetWidth,
                targetHeight = targetHeight,
                rotationDegrees = rotationDegrees,
                muteAudio = map["muteAudio"] as? Boolean ?: false,
            )
        }
    }
}

internal data class VideoCropRect(
    val left: Float,
    val top: Float,
    val width: Float,
    val height: Float,
) {
    companion object {
        fun fromMap(map: Map<*, *>): VideoCropRect {
            val rect = VideoCropRect(
                left = (map["left"] as? Number)?.toFloat()
                    ?: throw IllegalArgumentException("cropRect.left is required."),
                top = (map["top"] as? Number)?.toFloat()
                    ?: throw IllegalArgumentException("cropRect.top is required."),
                width = (map["width"] as? Number)?.toFloat()
                    ?: throw IllegalArgumentException("cropRect.width is required."),
                height = (map["height"] as? Number)?.toFloat()
                    ?: throw IllegalArgumentException("cropRect.height is required."),
            )

            require(rect.left >= 0f && rect.top >= 0f && rect.width > 0f && rect.height > 0f) {
                "cropRect must use positive normalized values."
            }
            require(rect.left + rect.width <= 1f && rect.top + rect.height <= 1f) {
                "cropRect must stay inside the normalized frame."
            }

            return rect
        }
    }
}
