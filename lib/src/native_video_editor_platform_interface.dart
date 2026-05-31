import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'models/video_edit_request.dart';
import 'native_video_editor_method_channel.dart';

abstract class NativeVideoEditorPlatform extends PlatformInterface {
  NativeVideoEditorPlatform() : super(token: _token);

  static final Object _token = Object();

  static NativeVideoEditorPlatform _instance = MethodChannelNativeVideoEditor();

  static NativeVideoEditorPlatform get instance => _instance;

  static set instance(NativeVideoEditorPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String> processVideo(VideoEditRequest request) {
    throw UnimplementedError('processVideo() has not been implemented.');
  }
}

class NativeVideoEditorException implements Exception {
  const NativeVideoEditorException(this.message);

  final String message;

  @override
  String toString() => 'NativeVideoEditorException: $message';
}
