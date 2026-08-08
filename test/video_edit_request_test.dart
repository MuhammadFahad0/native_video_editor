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
        cropRect: const VideoCropRect(left: 0.1, top: 0.2, width: 0.7, height: 0.6),
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
        'cropRect': <String, Object?>{'left': 0.1, 'top': 0.2, 'width': 0.7, 'height': 0.6},
        'targetWidth': 1280,
        'targetHeight': 720,
        'rotationDegrees': 90,
        'speedMultiplier': 1.5,
        'muteAudio': true,
      });
    });

    test('rejects same input and output path', () {
      final request = VideoEditRequest(inputPath: '/tmp/v.mp4', outputPath: '/tmp/v.mp4');
      expect(request.toMap, throwsArgumentError);
    });

    test('rejects invalid trim range', () {
      final request = VideoEditRequest(
        inputPath: '/tmp/input.mp4', outputPath: '/tmp/output.mp4',
        trimStart: const Duration(seconds: 5), trimEnd: const Duration(seconds: 1),
      );
      expect(request.toMap, throwsArgumentError);
    });

    test('rejects odd target dimensions', () {
      final request = VideoEditRequest(
        inputPath: '/tmp/input.mp4', outputPath: '/tmp/output.mp4',
        targetWidth: 721, targetHeight: 1280,
      );
      expect(request.toMap, throwsArgumentError);
    });

    test('rejects invalid rotation', () {
      final request = VideoEditRequest(
        inputPath: '/tmp/input.mp4', outputPath: '/tmp/output.mp4', rotationDegrees: 45,
      );
      expect(request.toMap, throwsArgumentError);
    });

    test('rejects invalid speed multiplier', () {
      final request = VideoEditRequest(
        inputPath: '/tmp/input.mp4', outputPath: '/tmp/output.mp4', speedMultiplier: 0.1,
      );
      expect(request.toMap, throwsArgumentError);
    });

    test('omits null optional fields from map', () {
      final map = VideoEditRequest(inputPath: '/tmp/input.mp4', outputPath: '/tmp/output.mp4').toMap();
      expect(map['trimStartMs'], isNull);
      expect(map['trimEndMs'], isNull);
      expect(map['cropRect'], isNull);
      expect(map['targetWidth'], isNull);
      expect(map['targetHeight'], isNull);
    });

    test('serializes zero trimStart as 0 ms', () {
      final request = VideoEditRequest(
        inputPath: '/tmp/input.mp4', outputPath: '/tmp/output.mp4',
        trimStart: Duration.zero, trimEnd: const Duration(seconds: 3),
      );
      expect(request.toMap()['trimStartMs'], equals(0));
    });

    test('muteAudio defaults to false in serialized map', () {
      expect(VideoEditRequest(inputPath: '/tmp/i.mp4', outputPath: '/tmp/o.mp4').toMap()['muteAudio'], isFalse);
    });

    test('rotationDegrees defaults to 0 in serialized map', () {
      expect(VideoEditRequest(inputPath: '/tmp/i.mp4', outputPath: '/tmp/o.mp4').toMap()['rotationDegrees'], equals(0));
    });

    test('rejects empty inputPath', () {
      expect(VideoEditRequest(inputPath: '', outputPath: '/tmp/o.mp4').toMap, throwsArgumentError);
    });

    test('rejects blank whitespace inputPath', () {
      expect(VideoEditRequest(inputPath: '   ', outputPath: '/tmp/o.mp4').toMap, throwsArgumentError);
    });

    test('rejects empty outputPath', () {
      expect(VideoEditRequest(inputPath: '/tmp/i.mp4', outputPath: '').toMap, throwsArgumentError);
    });

    test('rejects blank whitespace outputPath', () {
      expect(VideoEditRequest(inputPath: '/tmp/i.mp4', outputPath: '   ').toMap, throwsArgumentError);
    });

    test('rejects negative trimStart', () {
      final request = VideoEditRequest(
        inputPath: '/tmp/input.mp4', outputPath: '/tmp/output.mp4',
        trimStart: const Duration(milliseconds: -1),
      );
      expect(request.toMap, throwsArgumentError);
    });

    test('rejects negative trimEnd', () {
      final request = VideoEditRequest(
        inputPath: '/tmp/input.mp4', outputPath: '/tmp/output.mp4',
        trimEnd: const Duration(milliseconds: -1),
      );
      expect(request.toMap, throwsArgumentError);
    });

    test('rejects trimStart equal to trimEnd', () {
      final request = VideoEditRequest(
        inputPath: '/tmp/input.mp4', outputPath: '/tmp/output.mp4',
        trimStart: const Duration(seconds: 3), trimEnd: const Duration(seconds: 3),
      );
      expect(request.toMap, throwsArgumentError);
    });

    test('rejects targetWidth without targetHeight', () {
      expect(VideoEditRequest(inputPath: '/tmp/i.mp4', outputPath: '/tmp/o.mp4', targetWidth: 1280).toMap, throwsArgumentError);
    });

    test('rejects targetHeight without targetWidth', () {
      expect(VideoEditRequest(inputPath: '/tmp/i.mp4', outputPath: '/tmp/o.mp4', targetHeight: 720).toMap, throwsArgumentError);
    });

    test('rejects zero targetWidth', () {
      expect(VideoEditRequest(inputPath: '/tmp/i.mp4', outputPath: '/tmp/o.mp4', targetWidth: 0, targetHeight: 720).toMap, throwsArgumentError);
    });

    test('rejects zero targetHeight', () {
      expect(VideoEditRequest(inputPath: '/tmp/i.mp4', outputPath: '/tmp/o.mp4', targetWidth: 1280, targetHeight: 0).toMap, throwsArgumentError);
    });

    test('rejects odd targetHeight', () {
      expect(VideoEditRequest(inputPath: '/tmp/i.mp4', outputPath: '/tmp/o.mp4', targetWidth: 1280, targetHeight: 721).toMap, throwsArgumentError);
    });

    test('accepts all valid rotations', () {
      for (final deg in [0, 90, 180, 270]) {
        expect(
          () => VideoEditRequest(inputPath: '/tmp/i.mp4', outputPath: '/tmp/o.mp4', rotationDegrees: deg).toMap(),
          returnsNormally, reason: 'rotation should be valid',
        );
      }
    });

    test('accepts lower boundary speed (0.25)', () {
      expect(() => VideoEditRequest(inputPath: '/tmp/i.mp4', outputPath: '/tmp/o.mp4', speedMultiplier: 0.25).toMap(), returnsNormally);
    });

    test('accepts upper boundary speed (4.0)', () {
      expect(() => VideoEditRequest(inputPath: '/tmp/i.mp4', outputPath: '/tmp/o.mp4', speedMultiplier: 4.0).toMap(), returnsNormally);
    });

    test('rejects speed just below lower bound (0.249)', () {
      expect(VideoEditRequest(inputPath: '/tmp/i.mp4', outputPath: '/tmp/o.mp4', speedMultiplier: 0.249).toMap, throwsArgumentError);
    });

    test('rejects speed just above upper bound (4.001)', () {
      expect(VideoEditRequest(inputPath: '/tmp/i.mp4', outputPath: '/tmp/o.mp4', speedMultiplier: 4.001).toMap, throwsArgumentError);
    });

    test('rejects NaN speed multiplier', () {
      expect(VideoEditRequest(inputPath: '/tmp/i.mp4', outputPath: '/tmp/o.mp4', speedMultiplier: double.nan).toMap, throwsArgumentError);
    });

    test('rejects infinite speed multiplier', () {
      expect(VideoEditRequest(inputPath: '/tmp/i.mp4', outputPath: '/tmp/o.mp4', speedMultiplier: double.infinity).toMap, throwsArgumentError);
    });
  });

  group('VideoCropRect', () {
    test('rejects non-finite values', () {
      expect(const VideoCropRect(left: double.nan, top: 0, width: 1, height: 1).validate, throwsArgumentError);
    });

    test('rejects rectangles outside the source frame', () {
      expect(const VideoCropRect(left: 0.5, top: 0.5, width: 0.6, height: 0.6).validate, throwsArgumentError);
    });

    test('serializes valid crop rect to correct map', () {
      expect(const VideoCropRect(left: 0.1, top: 0.2, width: 0.5, height: 0.6).toMap(), <String, Object?>{'left': 0.1, 'top': 0.2, 'width': 0.5, 'height': 0.6});
    });

    test('rejects negative left', () {
      expect(const VideoCropRect(left: -0.1, top: 0, width: 0.5, height: 0.5).validate, throwsArgumentError);
    });

    test('rejects negative top', () {
      expect(const VideoCropRect(left: 0, top: -0.1, width: 0.5, height: 0.5).validate, throwsArgumentError);
    });

    test('rejects zero width', () {
      expect(const VideoCropRect(left: 0, top: 0, width: 0.0, height: 0.5).validate, throwsArgumentError);
    });

    test('rejects zero height', () {
      expect(const VideoCropRect(left: 0, top: 0, width: 0.5, height: 0.0).validate, throwsArgumentError);
    });

    test('rejects right-edge overflow', () {
      expect(const VideoCropRect(left: 0.6, top: 0, width: 0.5, height: 0.5).validate, throwsArgumentError);
    });

    test('rejects bottom-edge overflow', () {
      expect(const VideoCropRect(left: 0, top: 0.6, width: 0.5, height: 0.5).validate, throwsArgumentError);
    });

    test('accepts exact 1.0 boundary (full frame)', () {
      expect(const VideoCropRect(left: 0, top: 0, width: 1.0, height: 1.0).validate, returnsNormally);
    });

    test('rejects infinity in top', () {
      expect(const VideoCropRect(left: 0, top: double.infinity, width: 0.5, height: 0.5).validate, throwsArgumentError);
    });
  });

  group('VideoThumbnailRequest', () {
    test('serializes thumbnail options', () {
      final request = VideoThumbnailRequest(
        inputPath: '/tmp/input.mp4', outputPath: '/tmp/thumb.jpg',
        position: const Duration(seconds: 2), quality: 80,
      );
      expect(request.toMap(), <String, Object?>{
        'inputPath': '/tmp/input.mp4', 'outputPath': '/tmp/thumb.jpg', 'positionMs': 2000, 'quality': 80,
      });
    });

    test('rejects invalid quality', () {
      expect(const VideoThumbnailRequest(inputPath: '/tmp/i.mp4', outputPath: '/tmp/t.jpg', quality: 0).toMap, throwsArgumentError);
    });

    test('rejects negative position', () {
      expect(const VideoThumbnailRequest(inputPath: '/tmp/i.mp4', outputPath: '/tmp/t.jpg', position: Duration(milliseconds: -1)).toMap, throwsArgumentError);
    });

    test('rejects same input and output path', () {
      expect(const VideoThumbnailRequest(inputPath: '/tmp/t.jpg', outputPath: '/tmp/t.jpg').toMap, throwsArgumentError);
    });

    test('position defaults to zero ms in map', () {
      expect(const VideoThumbnailRequest(inputPath: '/tmp/i.mp4', outputPath: '/tmp/t.jpg').toMap()['positionMs'], equals(0));
    });

    test('quality defaults to 90 in map', () {
      expect(const VideoThumbnailRequest(inputPath: '/tmp/i.mp4', outputPath: '/tmp/t.jpg').toMap()['quality'], equals(90));
    });

    test('rejects empty inputPath', () {
      expect(const VideoThumbnailRequest(inputPath: '', outputPath: '/tmp/t.jpg').toMap, throwsArgumentError);
    });

    test('rejects blank whitespace inputPath', () {
      expect(const VideoThumbnailRequest(inputPath: '   ', outputPath: '/tmp/t.jpg').toMap, throwsArgumentError);
    });

    test('rejects empty outputPath', () {
      expect(const VideoThumbnailRequest(inputPath: '/tmp/i.mp4', outputPath: '').toMap, throwsArgumentError);
    });

    test('rejects blank whitespace outputPath', () {
      expect(const VideoThumbnailRequest(inputPath: '/tmp/i.mp4', outputPath: '   ').toMap, throwsArgumentError);
    });

    test('accepts quality lower boundary (1)', () {
      expect(() => const VideoThumbnailRequest(inputPath: '/tmp/i.mp4', outputPath: '/tmp/t.jpg', quality: 1).toMap(), returnsNormally);
    });

    test('accepts quality upper boundary (100)', () {
      expect(() => const VideoThumbnailRequest(inputPath: '/tmp/i.mp4', outputPath: '/tmp/t.jpg', quality: 100).toMap(), returnsNormally);
    });

    test('rejects quality above upper bound (101)', () {
      expect(const VideoThumbnailRequest(inputPath: '/tmp/i.mp4', outputPath: '/tmp/t.jpg', quality: 101).toMap, throwsArgumentError);
    });
  });
}
