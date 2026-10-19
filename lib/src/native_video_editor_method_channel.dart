import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models/audio_merge_request.dart';
import 'models/media_info.dart';
import 'models/video_composition_request.dart';
import 'text_overlay_renderer.dart';
import 'models/image_video_compose_request.dart';
import 'models/video_edit_request.dart';
import 'models/video_thumbnail_request.dart';
import 'native_video_editor_platform_interface.dart';

@visibleForTesting
const methodChannel = MethodChannel('native_video_editor');

class MethodChannelNativeVideoEditor extends NativeVideoEditorPlatform {
  final Set<String> _preparingCompositions = {};
  final Set<String> _cancelledPreparations = {};
  @override
  Future<MediaInfo> getMediaInfo(String inputPath) async {
    if (inputPath.trim().isEmpty) {
      throw ArgumentError('inputPath must not be empty.');
    }
    final result = await methodChannel.invokeMapMethod<Object?, Object?>(
      'getMediaInfo',
      {'inputPath': inputPath},
    );
    if (result == null) {
      throw const NativeVideoEditorException('Native metadata is missing.');
    }
    return MediaInfo.fromMap(result);
  }

  @override
  Future<String> composeVideo(VideoCompositionRequest request) async {
    final payload = request.toMap();
    _preparingCompositions.add(request.outputPath);
    try {
      await renderTextOverlays(payload);
      if (_cancelledPreparations.contains(request.outputPath)) {
        throw PlatformException(
          code: 'cancelled',
          message: 'Composition cancelled.',
        );
      }
    } finally {
      _preparingCompositions.remove(request.outputPath);
      _cancelledPreparations.remove(request.outputPath);
    }
    final result = await methodChannel.invokeMethod<String>(
      'composeVideo',
      payload,
    );
    if (result == null || result.isEmpty) {
      throw const NativeVideoEditorException(
        'Native composition returned no output path.',
      );
    }
    return result;
  }

  MethodChannelNativeVideoEditor() {
    methodChannel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onProgress') {
      final args = Map<String, Object?>.from(call.arguments as Map);
      final outputPath = args['outputPath'] as String;
      final progress = args['progress'] as double;
      final callback = progressCallbacks[outputPath];
      if (callback != null) {
        callback(progress);
      }
    }
  }

  @override
  Future<String> processVideo(VideoEditRequest request) async {
    final result = await methodChannel.invokeMethod<String>(
      'processVideo',
      request.toMap(),
    );

    if (result == null || result.isEmpty) {
      throw const NativeVideoEditorException(
        'Native processing completed without an output path.',
      );
    }

    return result;
  }

  @override
  Future<void> cancelProcessVideo(String outputPath) async {
    if (_preparingCompositions.contains(outputPath)) {
      _cancelledPreparations.add(outputPath);
      return;
    }
    await methodChannel.invokeMethod<void>(
      'cancelProcessVideo',
      <String, Object?>{'outputPath': outputPath},
    );
  }

  @override
  Future<String> extractThumbnail(VideoThumbnailRequest request) async {
    final result = await methodChannel.invokeMethod<String>(
      'extractThumbnail',
      request.toMap(),
    );

    if (result == null || result.isEmpty) {
      throw const NativeVideoEditorException(
        'Native thumbnail extraction completed without an output path.',
      );
    }

    return result;
  }

  @override
  Future<String> composeImageWithAudio(ImageVideoComposeRequest request) async {
    final result = await methodChannel.invokeMethod<String>(
      'composeImageWithAudio',
      request.toMap(),
    );

    if (result == null || result.isEmpty) {
      throw const NativeVideoEditorException(
        'Native image composition completed without an output path.',
      );
    }

    return result;
  }

  @override
  Future<String> mergeAudioIntoVideo(AudioMergeRequest request) async {
    final result = await methodChannel.invokeMethod<String>(
      'mergeAudioIntoVideo',
      request.toMap(),
    );

    if (result == null || result.isEmpty) {
      throw const NativeVideoEditorException(
        'Native audio merge completed without an output path.',
      );
    }

    return result;
  }
}
