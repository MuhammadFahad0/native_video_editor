import 'package:native_video_editor/src/models/video_crop_rect.dart';
import 'package:native_video_editor/src/models/video_edit_request.dart';
import 'package:native_video_editor/src/models/video_thumbnail_request.dart';
import 'package:test/test.dart';

void main() {
  group('VideoEditRequest', () {
    test('serializes all supported options', () {
      final request = VideoEditRequest(
        inputPath: '/tmp/input.mp4',
        outputPath: '/tmp/output.mp4',
        trimStart: const Duration(seconds: 1),
        trimEnd: const Duration(seconds: 5),
        cropRect: const VideoCropRect(
          left: 0.1,
          top: 0.2,
          width: 0.7,
          height: 0.6,
        ),
        targetWidth: 1280,
        targetHeight: 720,
        rotationDegrees: 90,
        speedMultiplier: 1.5,
        muteAudio: true,
      );

      expect(request.toMap(), <String, Object?>{
        'inputPath': '/tmp/input.mp4',
        'outputPath': '/tmp/output.mp4',
        'trimStartMs': 1000,
        'trimEndMs': 5000,
        'cropRect': <String, Object?>{
          'left': 0.1,
          'top': 0.2,
          'width': 0.7,
          'height': 0.6,
        },
        'targetWidth': 1280,
        'targetHeight': 720,
        'rotationDegrees': 90,
        'speedMultiplier': 1.5,
        'muteAudio': true,
      });
    });

    test('rejects same input and output path', () {
      final request = VideoEditRequest(
        inputPath: '/tmp/video.mp4',
        outputPath: '/tmp/video.mp4',
      );

      expect(request.toMap, throwsArgumentError);
    });

    test('rejects invalid trim range', () {
      final request = VideoEditRequest(
        inputPath: '/tmp/input.mp4',
        outputPath: '/tmp/output.mp4',
        trimStart: const Duration(seconds: 5),
        trimEnd: const Duration(seconds: 1),
      );

      expect(request.toMap, throwsArgumentError);
    });

    test('rejects odd target dimensions', () {
      final request = VideoEditRequest(
        inputPath: '/tmp/input.mp4',
        outputPath: '/tmp/output.mp4',
        targetWidth: 721,
        targetHeight: 1280,
      );

      expect(request.toMap, throwsArgumentError);
    });

    test('rejects invalid rotation', () {
      final request = VideoEditRequest(
        inputPath: '/tmp/input.mp4',
        outputPath: '/tmp/output.mp4',
        rotationDegrees: 45,
      );

      expect(request.toMap, throwsArgumentError);
    });

    test('rejects invalid speed multiplier', () {
      final request = VideoEditRequest(
        inputPath: '/tmp/input.mp4',
        outputPath: '/tmp/output.mp4',
        speedMultiplier: 0.1,
      );

      expect(request.toMap, throwsArgumentError);
    });
  });

  group('VideoCropRect', () {
    test('rejects non-finite values', () {
      const rect = VideoCropRect(left: double.nan, top: 0, width: 1, height: 1);

      expect(rect.validate, throwsArgumentError);
    });

    test('rejects rectangles outside the source frame', () {
      const rect = VideoCropRect(left: 0.5, top: 0.5, width: 0.6, height: 0.6);

      expect(rect.validate, throwsArgumentError);
    });
  });

  group('VideoThumbnailRequest', () {
    test('serializes thumbnail options', () {
      final request = VideoThumbnailRequest(
        inputPath: '/tmp/input.mp4',
        outputPath: '/tmp/thumb.jpg',
        position: const Duration(seconds: 2),
        quality: 80,
      );

      expect(request.toMap(), <String, Object?>{
        'inputPath': '/tmp/input.mp4',
        'outputPath': '/tmp/thumb.jpg',
        'positionMs': 2000,
        'quality': 80,
      });
    });

    test('rejects invalid quality', () {
      const request = VideoThumbnailRequest(
        inputPath: '/tmp/input.mp4',
        outputPath: '/tmp/thumb.jpg',
        quality: 0,
      );

      expect(request.toMap, throwsArgumentError);
    });

    test('rejects negative position', () {
      const request = VideoThumbnailRequest(
        inputPath: '/tmp/input.mp4',
        outputPath: '/tmp/thumb.jpg',
        position: Duration(milliseconds: -1),
      );

      expect(request.toMap, throwsArgumentError);
    });

    test('rejects same input and output path', () {
      const request = VideoThumbnailRequest(
        inputPath: '/tmp/thumb.jpg',
        outputPath: '/tmp/thumb.jpg',
      );

      expect(request.toMap, throwsArgumentError);
    });
  });
}
