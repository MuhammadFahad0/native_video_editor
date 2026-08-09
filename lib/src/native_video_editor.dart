import 'models/audio_merge_request.dart';
import 'models/image_video_compose_request.dart';
import 'native_video_editor_platform_interface.dart';
import 'models/video_edit_request.dart';
import 'models/video_thumbnail_request.dart';

/// Entry point for native video editing operations.
///
/// The plugin performs edits with AndroidX Media3 Transformer on Android and
/// AVFoundation on iOS. All input and output paths must point to files that the
/// host app can access.
class NativeVideoEditor {
  const NativeVideoEditor._();

  /// Processes a video with one or more edits and returns the output path.
  ///
  /// The request can combine trimming, normalized cropping, resizing, rotation,
  /// speed adjustment, and audio muting in a single native export operation.
  /// An optional [onProgress] callback can be provided to receive progress updates (0.0 to 1.0).
  static Future<String> processVideo(
    VideoEditRequest request, {
    void Function(double progress)? onProgress,
  }) async {
    if (onProgress != null) {
      NativeVideoEditorPlatform.instance.progressCallbacks[request.outputPath] =
          onProgress;
    }
    try {
      return await NativeVideoEditorPlatform.instance.processVideo(request);
    } finally {
      NativeVideoEditorPlatform.instance.progressCallbacks.remove(
        request.outputPath,
      );
    }
  }

  /// Cancels an active video processing operation for the given [outputPath].
  static Future<void> cancelProcessVideo(String outputPath) {
    return NativeVideoEditorPlatform.instance.cancelProcessVideo(outputPath);
  }

  /// Extracts a thumbnail image from a video and returns the output path.
  static Future<String> extractThumbnail(VideoThumbnailRequest request) {
    return NativeVideoEditorPlatform.instance.extractThumbnail(request);
  }

  /// Composes a still image and an audio file into an MP4 video.
  ///
  /// The still image is rendered as a static video frame for the full duration
  /// of the audio (capped by [ImageVideoComposeRequest.audioDurationMs] if set).
  ///
  /// An optional [onProgress] callback receives values from 0.0 to 1.0 as the
  /// composition progresses.
  ///
  /// Returns the output path of the composed MP4.
  static Future<String> composeImageWithAudio(
    ImageVideoComposeRequest request, {
    void Function(double progress)? onProgress,
  }) async {
    if (onProgress != null) {
      NativeVideoEditorPlatform.instance.progressCallbacks[request.outputPath] =
          onProgress;
    }
    try {
      return await NativeVideoEditorPlatform.instance.composeImageWithAudio(
        request,
      );
    } finally {
      NativeVideoEditorPlatform.instance.progressCallbacks.remove(
        request.outputPath,
      );
    }
  }

  /// Merges an audio track into an existing video file.
  ///
  /// When [AudioMergeRequest.replaceExistingAudio] is `true` (the default) the
  /// original audio track is removed before the new audio is injected.
  ///
  /// When audio and video durations differ, the shorter of the two determines
  /// the output duration (audio is truncated / video is trimmed accordingly).
  ///
  /// An optional [onProgress] callback receives values from 0.0 to 1.0.
  ///
  /// Returns the output path of the merged MP4.
  static Future<String> mergeAudioIntoVideo(
    AudioMergeRequest request, {
    void Function(double progress)? onProgress,
  }) async {
    if (onProgress != null) {
      NativeVideoEditorPlatform.instance.progressCallbacks[request.outputPath] =
          onProgress;
    }
    try {
      return await NativeVideoEditorPlatform.instance.mergeAudioIntoVideo(
        request,
      );
    } finally {
      NativeVideoEditorPlatform.instance.progressCallbacks.remove(
        request.outputPath,
      );
    }
  }
}

