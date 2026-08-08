import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_editor/src/models/video_edit_request.dart';
import 'package:native_video_editor/src/models/video_thumbnail_request.dart';
import 'package:native_video_editor/src/native_video_editor.dart';
import 'package:native_video_editor/src/native_video_editor_method_channel.dart';
import 'package:native_video_editor/src/native_video_editor_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> log;

  setUp(() {
    log = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (MethodCall call) async {
          log.add(call);
          switch (call.method) {
            case 'processVideo':
              return '/tmp/output.mp4';
            case 'extractThumbnail':
              return '/tmp/thumb.jpg';
            case 'cancelProcessVideo':
              return null;
            default:
              return null;
          }
        });
    NativeVideoEditorPlatform.instance = MethodChannelNativeVideoEditor();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  group('processVideo', () {
    test('returns output path on success', () async {
      final result = await NativeVideoEditor.processVideo(
        VideoEditRequest(
          inputPath: '/tmp/in.mp4',
          outputPath: '/tmp/output.mp4',
        ),
      );
      expect(result, '/tmp/output.mp4');
    });

    test('sends correct map to method channel', () async {
      await NativeVideoEditor.processVideo(
        VideoEditRequest(
          inputPath: '/tmp/in.mp4',
          outputPath: '/tmp/output.mp4',
          rotationDegrees: 90,
          muteAudio: true,
        ),
      );
      expect(log, hasLength(1));
      expect(log.first.method, 'processVideo');
      final args = Map<String, Object?>.from(log.first.arguments as Map);
      expect(args['inputPath'], '/tmp/in.mp4');
      expect(args['outputPath'], '/tmp/output.mp4');
      expect(args['rotationDegrees'], 90);
      expect(args['muteAudio'], true);
    });

    test(
      'throws NativeVideoEditorException when channel returns null',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (_) async => null);
        NativeVideoEditorPlatform.instance = MethodChannelNativeVideoEditor();

        await expectLater(
          NativeVideoEditor.processVideo(
            VideoEditRequest(
              inputPath: '/tmp/in.mp4',
              outputPath: '/tmp/output.mp4',
            ),
          ),
          throwsA(isA<NativeVideoEditorException>()),
        );
      },
    );

    test(
      'throws NativeVideoEditorException when channel returns empty string',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (_) async => '');
        NativeVideoEditorPlatform.instance = MethodChannelNativeVideoEditor();

        await expectLater(
          NativeVideoEditor.processVideo(
            VideoEditRequest(
              inputPath: '/tmp/in.mp4',
              outputPath: '/tmp/output.mp4',
            ),
          ),
          throwsA(isA<NativeVideoEditorException>()),
        );
      },
    );

    test(
      'onProgress callback is invoked when native fires onProgress',
      () async {
        final progressValues = <double>[];
        final future = NativeVideoEditor.processVideo(
          VideoEditRequest(
            inputPath: '/tmp/in.mp4',
            outputPath: '/tmp/output.mp4',
          ),
          onProgress: progressValues.add,
        );

        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              'native_video_editor',
              methodChannel.codec.encodeMethodCall(
                const MethodCall('onProgress', {
                  'outputPath': '/tmp/output.mp4',
                  'progress': 0.5,
                }),
              ),
              (_) {},
            );

        await future;
        expect(progressValues, contains(0.5));
      },
    );

    test('onProgress callback is cleaned up after success', () async {
      await NativeVideoEditor.processVideo(
        VideoEditRequest(
          inputPath: '/tmp/in.mp4',
          outputPath: '/tmp/output.mp4',
        ),
        onProgress: (_) {},
      );
      expect(
        NativeVideoEditorPlatform.instance.progressCallbacks.containsKey(
          '/tmp/output.mp4',
        ),
        isFalse,
      );
    });

    test('onProgress callback is cleaned up after failure', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (_) async => null);
      NativeVideoEditorPlatform.instance = MethodChannelNativeVideoEditor();

      try {
        await NativeVideoEditor.processVideo(
          VideoEditRequest(
            inputPath: '/tmp/in.mp4',
            outputPath: '/tmp/output.mp4',
          ),
          onProgress: (_) {},
        );
      } catch (_) {}

      expect(
        NativeVideoEditorPlatform.instance.progressCallbacks.containsKey(
          '/tmp/output.mp4',
        ),
        isFalse,
      );
    });

    test(
      'unhandled onProgress with unknown outputPath does not throw',
      () async {
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              'native_video_editor',
              methodChannel.codec.encodeMethodCall(
                const MethodCall('onProgress', {
                  'outputPath': '/unknown/path.mp4',
                  'progress': 0.9,
                }),
              ),
              (_) {},
            );
      },
    );
  });

  group('cancelProcessVideo', () {
    test('delegates to channel with correct outputPath', () async {
      await NativeVideoEditor.cancelProcessVideo('/tmp/output.mp4');
      expect(log, hasLength(1));
      expect(log.first.method, 'cancelProcessVideo');
      final args = Map<String, Object?>.from(log.first.arguments as Map);
      expect(args['outputPath'], '/tmp/output.mp4');
    });
  });

  group('extractThumbnail', () {
    test('returns output path on success', () async {
      final result = await NativeVideoEditor.extractThumbnail(
        const VideoThumbnailRequest(
          inputPath: '/tmp/in.mp4',
          outputPath: '/tmp/thumb.jpg',
        ),
      );
      expect(result, '/tmp/thumb.jpg');
    });

    test('sends correct map to method channel', () async {
      await NativeVideoEditor.extractThumbnail(
        const VideoThumbnailRequest(
          inputPath: '/tmp/in.mp4',
          outputPath: '/tmp/thumb.jpg',
          quality: 75,
        ),
      );
      expect(log, hasLength(1));
      expect(log.first.method, 'extractThumbnail');
      final args = Map<String, Object?>.from(log.first.arguments as Map);
      expect(args['inputPath'], '/tmp/in.mp4');
      expect(args['outputPath'], '/tmp/thumb.jpg');
      expect(args['quality'], 75);
    });

    test(
      'throws NativeVideoEditorException when channel returns null',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (_) async => null);
        NativeVideoEditorPlatform.instance = MethodChannelNativeVideoEditor();

        await expectLater(
          NativeVideoEditor.extractThumbnail(
            const VideoThumbnailRequest(
              inputPath: '/tmp/in.mp4',
              outputPath: '/tmp/thumb.jpg',
            ),
          ),
          throwsA(isA<NativeVideoEditorException>()),
        );
      },
    );

    test(
      'throws NativeVideoEditorException when channel returns empty string',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (_) async => '');
        NativeVideoEditorPlatform.instance = MethodChannelNativeVideoEditor();

        await expectLater(
          NativeVideoEditor.extractThumbnail(
            const VideoThumbnailRequest(
              inputPath: '/tmp/in.mp4',
              outputPath: '/tmp/thumb.jpg',
            ),
          ),
          throwsA(isA<NativeVideoEditorException>()),
        );
      },
    );
  });
}
