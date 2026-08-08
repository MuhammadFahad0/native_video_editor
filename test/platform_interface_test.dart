import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_editor/src/native_video_editor_method_channel.dart';
import 'package:native_video_editor/src/native_video_editor_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePlatform extends NativeVideoEditorPlatform with MockPlatformInterfaceMixin {}

class _UnverifiedPlatform extends NativeVideoEditorPlatform {
  _UnverifiedPlatform() : super();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NativeVideoEditorPlatform', () {
    tearDown(() {
      NativeVideoEditorPlatform.instance = MethodChannelNativeVideoEditor();
    });

    test('default instance is MethodChannelNativeVideoEditor', () {
      expect(NativeVideoEditorPlatform.instance, isA<MethodChannelNativeVideoEditor>());
    });

    test('setting a valid mock instance succeeds', () {
      final fake = _FakePlatform();
      expect(() => NativeVideoEditorPlatform.instance = fake, returnsNormally);
    });

    test('instance can be replaced with a mock that passes token check', () {
      final fake = _FakePlatform();
      NativeVideoEditorPlatform.instance = fake;
      expect(NativeVideoEditorPlatform.instance, same(fake));
    });


    test('progressCallbacks map is independent per instance', () {
      final a = _FakePlatform();
      final b = _FakePlatform();
      a.progressCallbacks['key'] = (_) {};
      expect(b.progressCallbacks.containsKey('key'), isFalse);
    });
  });

  group('NativeVideoEditorException', () {
    test('toString contains the message', () {
      const ex = NativeVideoEditorException('something went wrong');
      expect(ex.toString(), contains('something went wrong'));
    });

    test('toString starts with the class prefix', () {
      const ex = NativeVideoEditorException('oops');
      expect(ex.toString(), startsWith('NativeVideoEditorException'));
    });
  });
}
