import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_editor/native_video_editor.dart';
import 'package:native_video_editor/src/native_video_editor_method_channel.dart';
import 'package:native_video_editor/src/native_video_editor_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  const rect = VideoCropRect(left: .6, top: .1, width: .3, height: .3);
  const settings = VideoExportSettings(
    width: 640,
    height: 360,
    frameRate: 24,
    videoBitrate: 900000,
    audioBitrate: 96000,
  );

  setUp(() {
    calls.clear();
    NativeVideoEditorPlatform.instance = MethodChannelNativeVideoEditor();
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      final args = call.arguments as Map;
      if (call.method == 'getMediaInfo') {
        return {
          'durationMs': 5000,
          'width': 1920,
          'height': 1080,
          'rotationDegrees': 90,
          'hasAudio': true,
          'videoCodec': 'avc1',
          'audioCodec': 'aac',
          'audioTracks': [
            {
              'index': 1,
              'codec': 'aac',
              'sampleRate': 44100,
              'channelCount': 2,
              'bitrate': 128000,
              'language': 'eng',
            },
          ],
          'frameRate': 29.97,
          'bitrate': 4000000,
        };
      }
      return args['outputPath'];
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(methodChannel, null));

  test('media metadata decodes optional native values', () async {
    final info = await NativeVideoEditor.getMediaInfo('source.mp4');
    expect(info.duration, const Duration(seconds: 5));
    expect(info.width, 1920);
    expect(info.rotationDegrees, 90);
    expect(info.hasAudio, isTrue);
    expect(info.frameRate, 29.97);
    expect(info.videoCodec, 'avc1');
    expect(info.audioCodec, 'aac');
    expect(info.audioTracks.single.sampleRate, 44100);
    expect(info.audioTracks.single.channelCount, 2);
    expect(info.audioTracks.single.language, 'eng');
    expect(MediaInfo.fromMap({'durationMs': 10}).videoCodec, isNull);
  });

  test('compression sends explicit encoding, fitting and flipping', () async {
    await NativeVideoEditor.compressVideo(
      inputPath: 'source.mp4',
      outputPath: 'out.mp4',
      settings: settings,
      fit: VideoFit.cover,
      flipHorizontal: true,
      flipVertical: true,
    );
    expect(calls.single.method, 'composeVideo');
    final args = calls.single.arguments as Map;
    expect(args['settings'], settings.toMap());
    expect((args['clips'] as List).single, containsPair('fit', 'cover'));
    expect(
      (args['clips'] as List).single,
      containsPair('flipHorizontal', true),
    );
    expect((args['clips'] as List).single, containsPair('flipVertical', true));
  });

  test(
    'join preserves order; slideshow supplies image timing and looping audio',
    () async {
      await NativeVideoEditor.joinVideos(
        inputPaths: ['a.mp4', 'b.mp4'],
        outputPath: 'join.mp4',
      );
      expect(
        ((calls.last.arguments as Map)['clips'] as List).map((c) => c['path']),
        ['a.mp4', 'b.mp4'],
      );
      await NativeVideoEditor.createSlideshow(
        imagePaths: ['a.png', 'b.jpg'],
        outputPath: 'slides.mp4',
        imageDuration: const Duration(seconds: 2),
        audioTracks: [const CompositionAudioTrack('music.mp3', loop: true)],
      );
      final args = calls.last.arguments as Map;
      expect(
        (args['clips'] as List).every(
          (c) => c['isImage'] == true && c['durationMs'] == 2000,
        ),
        isTrue,
      );
      expect((args['audioTracks'] as List).single['loop'], isTrue);
    },
  );

  test(
    'composition preserves watermark/PIP timing and audio controls',
    () async {
      await NativeVideoEditor.composeVideo(
        const VideoCompositionRequest(
          outputPath: 'out.mp4',
          clips: [VideoClip.video('source.mp4', volume: .2)],
          settings: settings,
          overlays: [
            VideoOverlay.image('logo.png', rect: rect, opacity: .5),
            VideoOverlay.video(
              'pip.mp4',
              rect: rect,
              start: Duration(seconds: 1),
              duration: Duration(seconds: 2),
            ),
          ],
          audioTracks: [
            CompositionAudioTrack(
              'music.mp3',
              start: Duration(seconds: 2),
              trimStart: Duration(seconds: 1),
              duration: Duration(seconds: 3),
              volume: .4,
              loop: true,
            ),
          ],
        ),
      );
      final args = calls.single.arguments as Map;
      expect((args['overlays'] as List)[1]['startMs'], 1000);
      expect((args['audioTracks'] as List).single['volume'], .4);
      expect((args['audioTracks'] as List).single['trimStartMs'], 1000);
    },
  );

  test(
    'text becomes an alpha PNG before entering the native pipeline',
    () async {
      await NativeVideoEditor.composeVideo(
        const VideoCompositionRequest(
          outputPath: 'out.mp4',
          clips: [VideoClip.video('source.mp4')],
          settings: settings,
          overlays: [
            VideoOverlay.text('Hello\nWorld', rect: rect, fontSize: 24),
          ],
        ),
      );
      final overlay =
          ((calls.single.arguments as Map)['overlays'] as List).single as Map;
      expect(overlay['type'], 'image');
      expect(overlay['fit'], 'stretch');
      expect((overlay['imageBytes'] as Uint8List).take(8), [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ]);
    },
  );

  test(
    'thumbnail batch preserves order and validates all requests before writing',
    () async {
      final progress = <double>[];
      final paths = await NativeVideoEditor.extractThumbnails(
        inputPath: 'a.mp4',
        positions: [Duration.zero, const Duration(seconds: 2)],
        outputPaths: ['0.jpg', '2.png'],
        onProgress: progress.add,
      );
      expect(paths, ['0.jpg', '2.png']);
      expect(progress, [.5, 1]);
      calls.clear();
      await expectLater(
        NativeVideoEditor.extractThumbnails(
          inputPath: 'a.mp4',
          positions: [Duration.zero, const Duration(seconds: -1)],
          outputPaths: ['0.jpg', 'bad.jpg'],
        ),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    },
  );

  test(
    'composition validates source protection, timing, bounds and settings',
    () {
      for (final request in [
        const VideoCompositionRequest(outputPath: 'out.mp4', clips: []),
        const VideoCompositionRequest(
          outputPath: 'out.mp4',
          clips: [VideoClip.video('out.mp4')],
        ),
        const VideoCompositionRequest(
          outputPath: 'out.mp4',
          clips: [VideoClip.video('a.mp4')],
          overlays: [VideoOverlay.image('out.mp4', rect: rect)],
        ),
        const VideoCompositionRequest(
          outputPath: 'out.mp4',
          clips: [VideoClip.video('a.mp4')],
          audioTracks: [CompositionAudioTrack('out.mp4')],
        ),
        const VideoCompositionRequest(
          outputPath: 'out.mp4',
          clips: [VideoClip.image('a.png', duration: Duration.zero)],
        ),
        const VideoCompositionRequest(
          outputPath: 'out.mp4',
          clips: [VideoClip.video('a.mp4', volume: double.nan)],
        ),
        const VideoCompositionRequest(
          outputPath: 'out.mp4',
          clips: [VideoClip.video('a.mp4')],
          settings: VideoExportSettings(width: 641),
        ),
        const VideoCompositionRequest(
          outputPath: 'out.mp4',
          clips: [VideoClip.video('a.mp4')],
          overlays: [VideoOverlay.text('', rect: rect)],
        ),
        const VideoCompositionRequest(
          outputPath: 'out.mp4',
          clips: [VideoClip.video('a.mp4')],
          audioTracks: [
            CompositionAudioTrack('a.mp3', start: Duration(seconds: -1)),
          ],
        ),
      ]) {
        expect(request.toMap, throwsArgumentError);
      }
    },
  );

  test(
    'composition clears progress callback when native export fails',
    () async {
      messenger.setMockMethodCallHandler(
        methodChannel,
        (_) async => throw PlatformException(code: 'cancelled'),
      );
      await expectLater(
        NativeVideoEditor.composeVideo(
          const VideoCompositionRequest(
            outputPath: 'out.mp4',
            clips: [VideoClip.video('a.mp4')],
          ),
          onProgress: (_) {},
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(NativeVideoEditorPlatform.instance.progressCallbacks, isEmpty);
    },
  );

  test(
    'cancellation during caption preparation never starts a native export',
    () async {
      final operation = NativeVideoEditor.composeVideo(
        const VideoCompositionRequest(
          outputPath: 'out.mp4',
          clips: [VideoClip.video('a.mp4')],
          settings: settings,
          overlays: [VideoOverlay.text('Preparing', rect: rect)],
        ),
      );
      final expectation = expectLater(
        operation,
        throwsA(isA<PlatformException>()),
      );
      await NativeVideoEditor.cancelProcessVideo('out.mp4');
      await expectation;
      expect(calls.where((call) => call.method == 'composeVideo'), isEmpty);
      expect(NativeVideoEditorPlatform.instance.progressCallbacks, isEmpty);
    },
  );

  test('legacy image composition refuses to overwrite either source', () {
    for (final path in ['image.png', 'audio.mp3']) {
      expect(
        () => ImageVideoComposeRequest(
          imagePath: 'image.png',
          audioPath: 'audio.mp3',
          outputPath: path,
          targetWidth: 640,
          targetHeight: 360,
        ).validate(),
        throwsArgumentError,
      );
    }
  });
}
