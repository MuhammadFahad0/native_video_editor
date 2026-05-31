import 'native_video_editor_platform_interface.dart';
import 'models/video_edit_request.dart';

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
  /// and audio muting in a single native export operation.
  static Future<String> processVideo(VideoEditRequest request) {
    return NativeVideoEditorPlatform.instance.processVideo(request);
  }
}
