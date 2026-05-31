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
      NativeVideoEditorPlatform.instance.progressCallbacks[request.outputPath] = onProgress;
    }
    try {
      return await NativeVideoEditorPlatform.instance.processVideo(request);
    } finally {
      NativeVideoEditorPlatform.instance.progressCallbacks.remove(request.outputPath);
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
}
