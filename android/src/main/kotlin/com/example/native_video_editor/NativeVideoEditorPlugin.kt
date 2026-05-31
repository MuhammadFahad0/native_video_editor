package com.example.native_video_editor

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.ConcurrentHashMap

class NativeVideoEditorPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: Context
    private val activePipelines = ConcurrentHashMap<String, VideoTransformerPipeline>()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "native_video_editor")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "processVideo" -> processVideo(call, result)
            "cancelProcessVideo" -> cancelProcessVideo(call, result)
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

        val pipeline = VideoTransformerPipeline(applicationContext, channel)
        activePipelines[request.outputPath] = pipeline

        pipeline.process(
            request = request,
            onSuccess = { outputPath ->
                activePipelines.remove(outputPath)
                result.success(outputPath)
            },
            onFailure = { error ->
                activePipelines.remove(request.outputPath)
                result.error("processing_failed", error.message, error.stackTraceToString())
            },
        )
    }

    private fun cancelProcessVideo(call: MethodCall, result: Result) {
        val arguments = call.arguments as? Map<*, *>
        val outputPath = arguments?.get("outputPath") as? String
        if (outputPath == null) {
            result.error("invalid_arguments", "Expected outputPath.", null)
            return
        }
        val pipeline = activePipelines.remove(outputPath)
        if (pipeline != null) {
            pipeline.cancel()
        }
        result.success(null)
    }

    private fun extractThumbnail(call: MethodCall, result: Result) {
        val arguments = call.arguments as? Map<*, *>
        if (arguments == null) {
            result.error("invalid_arguments", "Expected a request map.", null)
            return
        }

        try {
            val request = VideoThumbnailRequest.fromMap(arguments)
            val outputPath = VideoTransformerPipeline(applicationContext, channel).extractThumbnail(request)
            result.success(outputPath)
        } catch (error: IllegalArgumentException) {
            result.error("invalid_arguments", error.message, null)
        } catch (error: Throwable) {
            result.error("thumbnail_failed", error.message, error.stackTraceToString())
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        for (pipeline in activePipelines.values) {
            pipeline.cancel()
        }
        activePipelines.clear()
    }
}
