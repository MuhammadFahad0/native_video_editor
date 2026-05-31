import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models/video_edit_request.dart';
import 'native_video_editor_platform_interface.dart';

@visibleForTesting
const methodChannel = MethodChannel('native_video_editor');

class MethodChannelNativeVideoEditor extends NativeVideoEditorPlatform {
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
}
