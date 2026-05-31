package com.example.native_video_editor

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class NativeVideoEditorPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "native_video_editor")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "processVideo" -> processVideo(call, result)
            "extractThumbnail" -> extractThumbnail(call, result)
            else -> result.notImplemented()
        }
    }

    private fun processVideo(call: MethodCall, result: Result) {
        val arguments = call.arguments as? Map<*, *>
        if (arguments == null) {
            result.error("invalid_arguments", "Expected a request map.", null)
            return
        }

        val request = try {
            VideoEditRequest.fromMap(arguments)
        } catch (error: IllegalArgumentException) {
            result.error("invalid_arguments", error.message, null)
            return
        }

        VideoTransformerPipeline(applicationContext).process(
            request = request,
            onSuccess = { outputPath -> result.success(outputPath) },
            onFailure = { error ->
                result.error("processing_failed", error.message, error.stackTraceToString())
            },
        )
    }

    private fun extractThumbnail(call: MethodCall, result: Result) {
        val arguments = call.arguments as? Map<*, *>
        if (arguments == null) {
            result.error("invalid_arguments", "Expected a request map.", null)
            return
        }

        try {
            val request = VideoThumbnailRequest.fromMap(arguments)
            val outputPath = VideoTransformerPipeline(applicationContext).extractThumbnail(request)
            result.success(outputPath)
        } catch (error: IllegalArgumentException) {
            result.error("invalid_arguments", error.message, null)
        } catch (error: Throwable) {
            result.error("thumbnail_failed", error.message, error.stackTraceToString())
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
