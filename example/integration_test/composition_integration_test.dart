import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:native_video_editor/native_video_editor.dart';
import 'package:path_provider/path_provider.dart';

/// Run on a real native target: `flutter test integration_test -d <device-id>`.
/// Generates its own fixtures; verifies encoded media, not mocked channels.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native composition exports the complete feature set',
    (tester) async {
      final root = await Directory(
        (await getTemporaryDirectory()).path,
      ).createTemp('nve-integration-');
      String path(String name) => '${root.path}${Platform.pathSeparator}$name';
      Future<void> image(String name, int color) async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawColor(ui.Color(color), ui.BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(160, 120);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(path(name)).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      }

      const settings = VideoExportSettings(
        width: 320,
        height: 240,
        frameRate: 24,
        videoBitrate: 500000,
      );
      try {
        await image('red.png', 0xFFFF0000);
        await image('blue.png', 0xFF0000FF);
        await image('logo.png', 0xFF00FF00);
        await File(path('tone.wav')).writeAsBytes(_tone());
        await NativeVideoEditor.createSlideshow(
          imagePaths: [path('red.png'), path('blue.png')],
          outputPath: path('base.mp4'),
          imageDuration: const Duration(seconds: 1),
          settings: settings,
          audioTracks: [
            CompositionAudioTrack(path('tone.wav'), loop: true, volume: .3),
          ],
        ).timeout(const Duration(minutes: 2));
        final info = await NativeVideoEditor.getMediaInfo(path('base.mp4'));
        expect(info.width, 320);
        expect(info.height, 240);
        expect(info.hasAudio, isTrue);
        expect(info.audioTracks, isNotEmpty);
        expect(info.audioTracks.first.channelCount, greaterThan(0));
        expect(info.duration.inMilliseconds, closeTo(2000, 150));

        await NativeVideoEditor.processVideo(
          VideoEditRequest(
            inputPath: path('base.mp4'),
            outputPath: path('edited.mp4'),
            cropRect: const VideoCropRect(
              left: .1,
              top: .1,
              width: .8,
              height: .8,
            ),
            rotationDegrees: 90,
            targetWidth: 320,
            targetHeight: 240,
            muteAudio: true,
          ),
        );
        expect(
          (await NativeVideoEditor.getMediaInfo(path('edited.mp4'))).hasAudio,
          isFalse,
        );

        final compressionErrors = <String>[];
        for (final variant in [
          (VideoFit.contain, false, false),
          (VideoFit.cover, false, false),
          (VideoFit.stretch, true, false),
          (VideoFit.contain, false, true),
          (VideoFit.cover, true, true),
        ]) {
          try {
            await NativeVideoEditor.compressVideo(
              inputPath: path('base.mp4'),
              outputPath: path('compressed.mp4'),
              settings: const VideoExportSettings(
                width: 160,
                height: 160,
                videoBitrate: 200000,
              ),
              fit: variant.$1,
              flipHorizontal: variant.$2,
              flipVertical: variant.$3,
            );
          } catch (error) {
            final message = 'Compression $variant: $error';
            debugPrint(message);
            compressionErrors.add(message);
          }
        }
        expect(compressionErrors, isEmpty);
        expect(
          (await NativeVideoEditor.getMediaInfo(path('compressed.mp4'))).width,
          160,
        );
        await NativeVideoEditor.joinVideos(
          inputPaths: [path('compressed.mp4'), path('compressed.mp4')],
          outputPath: path('joined.mp4'),
          settings: settings,
        );
        expect(
          (await NativeVideoEditor.getMediaInfo(
            path('joined.mp4'),
          )).duration.inMilliseconds,
          closeTo(4000, 300),
        );

        final progress = <double>[];
        await NativeVideoEditor.composeVideo(
          VideoCompositionRequest(
            outputPath: path('layered.mp4'),
            settings: settings,
            clips: [
              VideoClip.video(
                path('base.mp4'),
                volume: .2,
                fit: VideoFit.stretch,
              ),
            ],
            overlays: [
              VideoOverlay.image(
                path('logo.png'),
                rect: const VideoCropRect(
                  left: 0,
                  top: 0,
                  width: .25,
                  height: .25,
                ),
              ),
              const VideoOverlay.text(
                'Caption',
                rect: VideoCropRect(left: 0, top: .7, width: .8, height: .2),
                fontSize: 20,
              ),
              VideoOverlay.video(
                path('compressed.mp4'),
                rect: const VideoCropRect(
                  left: .6,
                  top: .1,
                  width: .3,
                  height: .3,
                ),
                start: const Duration(milliseconds: 500),
                duration: const Duration(seconds: 1),
              ),
            ],
            audioTracks: [
              CompositionAudioTrack(
                path('tone.wav'),
                volume: .1,
                loop: true,
                start: const Duration(milliseconds: 200),
                trimStart: const Duration(milliseconds: 100),
              ),
            ],
          ),
          onProgress: progress.add,
        );
        expect(
          (await NativeVideoEditor.getMediaInfo(
            path('layered.mp4'),
          )).duration.inMilliseconds,
          closeTo(2000, 150),
        );
        final thumbs = await NativeVideoEditor.extractThumbnails(
          inputPath: path('layered.mp4'),
          positions: [
            const Duration(milliseconds: 100),
            const Duration(milliseconds: 1200),
          ],
          outputPaths: [path('first.png'), path('second.png')],
        );
        for (final thumb in thumbs) {
          expect(await File(thumb).length(), greaterThan(100));
        }
        final codec = await ui.instantiateImageCodec(
          await File(thumbs.first).readAsBytes(),
        );
        final frame = await codec.getNextFrame();
        final pixels = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        // Top-left watermark should be green; uncovered main canvas should be red.
        final logoPixel = (10 * frame.image.width + 10) * 4;
        final basePixel =
            (frame.image.height ~/ 2 * frame.image.width +
                frame.image.width ~/ 2) *
            4;
        expect(pixels!.getUint8(logoPixel + 1), greaterThan(150));
        expect(pixels.getUint8(basePixel), greaterThan(150));
        final transparentCaptionPixel = (200 * frame.image.width + 240) * 4;
        expect(pixels.getUint8(transparentCaptionPixel), greaterThan(150));
        frame.image.dispose();
        codec.dispose();
        final pipCodec = await ui.instantiateImageCodec(
          await File(thumbs[1]).readAsBytes(),
        );
        final pipFrame = await pipCodec.getNextFrame();
        final pipPixels = await pipFrame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final pipCenter = (60 * pipFrame.image.width + 240) * 4;
        final outsidePip = (120 * pipFrame.image.width + 160) * 4;
        expect(pipPixels!.getUint8(pipCenter), greaterThan(150));
        expect(pipPixels.getUint8(outsidePip + 2), greaterThan(150));
        pipFrame.image.dispose();
        pipCodec.dispose();
        expect(progress, isNotEmpty);
        // Native path protection must reject aliases as well as exact Dart matches.
        await expectLater(
          NativeVideoEditor.composeVideo(
            VideoCompositionRequest(
              clips: [VideoClip.video(path('base.mp4'))],
              outputPath: path('.${Platform.pathSeparator}base.mp4'),
              settings: settings,
            ),
          ),
          throwsA(isA<PlatformException>()),
        );
        expect(await File(path('base.mp4')).length(), greaterThan(100));
      } finally {
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Uint8List _tone() {
  const samples = 22050, sampleRate = 44100;
  final data = ByteData(44 + samples * 2);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, data.lengthInBytes - 8, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    data.setInt16(
      44 + i * 2,
      (4000 * math.sin(2 * math.pi * 440 * i / sampleRate)).round(),
      Endian.little,
    );
  }
  return data.buffer.asUint8List();
}
