import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'models/video_edit_request.dart';
import 'native_video_editor_method_channel.dart';

/// Platform interface for native video editor implementations.
abstract class NativeVideoEditorPlatform extends PlatformInterface {
  /// Creates a platform interface instance.
  NativeVideoEditorPlatform() : super(token: _token);

  static final Object _token = Object();

  static NativeVideoEditorPlatform _instance = MethodChannelNativeVideoEditor();

  /// The active platform implementation.
  static NativeVideoEditorPlatform get instance => _instance;

  /// Sets the active platform implementation.
  static set instance(NativeVideoEditorPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Processes a video and returns the native output path.
  Future<String> processVideo(VideoEditRequest request) {
    throw UnimplementedError('processVideo() has not been implemented.');
  }
}

/// Exception thrown by the Dart wrapper when native processing fails.
class NativeVideoEditorException implements Exception {
  /// Creates an exception with a human-readable [message].
  const NativeVideoEditorException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => 'NativeVideoEditorException: $message';
}
