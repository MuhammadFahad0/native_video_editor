import 'native_video_editor_platform_interface.dart';
import 'models/video_edit_request.dart';

class NativeVideoEditor {
  const NativeVideoEditor._();

  static Future<String> processVideo(VideoEditRequest request) {
    return NativeVideoEditorPlatform.instance.processVideo(request);
  }
}
