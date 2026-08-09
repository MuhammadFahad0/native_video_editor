import 'package:native_video_editor/src/models/audio_merge_request.dart';
import 'package:native_video_editor/src/models/image_video_compose_request.dart';
import 'package:test/test.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // ImageVideoComposeRequest
  // ─────────────────────────────────────────────────────────────────────────
  group('ImageVideoComposeRequest', () {
    test('serializes all fields', () {
      const request = ImageVideoComposeRequest(
        imagePath: '/tmp/image.png',
        audioPath: '/tmp/audio.mp3',
        outputPath: '/tmp/output.mp4',
        targetWidth: 1080,
        targetHeight: 1920,
        audioDurationMs: 5000,
        frameRate: 30,
      );
      expect(request.toMap(), <String, Object?>{
        'imagePath': '/tmp/image.png',
        'audioPath': '/tmp/audio.mp3',
        'outputPath': '/tmp/output.mp4',
        'targetWidth': 1080,
        'targetHeight': 1920,
        'audioDurationMs': 5000,
        'frameRate': 30,
      });
    });

    test('serializes without optional audioDurationMs', () {
      const request = ImageVideoComposeRequest(
        imagePath: '/tmp/image.png',
        audioPath: '/tmp/audio.mp3',
        outputPath: '/tmp/output.mp4',
        targetWidth: 1080,
        targetHeight: 1920,
      );
      final map = request.toMap();
      expect(map['audioDurationMs'], isNull);
      expect(map['frameRate'], 30);
    });

    test('throws when imagePath is empty', () {
      expect(
        () => const ImageVideoComposeRequest(
          imagePath: '',
          audioPath: '/tmp/audio.mp3',
          outputPath: '/tmp/output.mp4',
          targetWidth: 1080,
          targetHeight: 1920,
        ).validate(),
        throwsArgumentError,
      );
    });

    test('throws when audioPath is empty', () {
      expect(
        () => const ImageVideoComposeRequest(
          imagePath: '/tmp/image.png',
          audioPath: '',
          outputPath: '/tmp/output.mp4',
          targetWidth: 1080,
          targetHeight: 1920,
        ).validate(),
        throwsArgumentError,
      );
    });

    test('throws when targetWidth is odd', () {
      expect(
        () => const ImageVideoComposeRequest(
          imagePath: '/tmp/image.png',
          audioPath: '/tmp/audio.mp3',
          outputPath: '/tmp/output.mp4',
          targetWidth: 1081,
          targetHeight: 1920,
        ).validate(),
        throwsArgumentError,
      );
    });

    test('throws when targetHeight is zero', () {
      expect(
        () => const ImageVideoComposeRequest(
          imagePath: '/tmp/image.png',
          audioPath: '/tmp/audio.mp3',
          outputPath: '/tmp/output.mp4',
          targetWidth: 1080,
          targetHeight: 0,
        ).validate(),
        throwsArgumentError,
      );
    });

    test('throws when audioDurationMs is zero', () {
      expect(
        () => const ImageVideoComposeRequest(
          imagePath: '/tmp/image.png',
          audioPath: '/tmp/audio.mp3',
          outputPath: '/tmp/output.mp4',
          targetWidth: 1080,
          targetHeight: 1920,
          audioDurationMs: 0,
        ).validate(),
        throwsArgumentError,
      );
    });

    test('throws when audioDurationMs is negative', () {
      expect(
        () => const ImageVideoComposeRequest(
          imagePath: '/tmp/image.png',
          audioPath: '/tmp/audio.mp3',
          outputPath: '/tmp/output.mp4',
          targetWidth: 1080,
          targetHeight: 1920,
          audioDurationMs: -1,
        ).validate(),
        throwsArgumentError,
      );
    });

    test('throws when frameRate is out of range', () {
      expect(
        () => const ImageVideoComposeRequest(
          imagePath: '/tmp/image.png',
          audioPath: '/tmp/audio.mp3',
          outputPath: '/tmp/output.mp4',
          targetWidth: 1080,
          targetHeight: 1920,
          frameRate: 0,
        ).validate(),
        throwsArgumentError,
      );
      expect(
        () => const ImageVideoComposeRequest(
          imagePath: '/tmp/image.png',
          audioPath: '/tmp/audio.mp3',
          outputPath: '/tmp/output.mp4',
          targetWidth: 1080,
          targetHeight: 1920,
          frameRate: 121,
        ).validate(),
        throwsArgumentError,
      );
    });

    test('accepts frameRate boundaries', () {
      expect(
        () => const ImageVideoComposeRequest(
          imagePath: '/tmp/image.png',
          audioPath: '/tmp/audio.mp3',
          outputPath: '/tmp/output.mp4',
          targetWidth: 1080,
          targetHeight: 1920,
          frameRate: 1,
        ).validate(),
        returnsNormally,
      );
      expect(
        () => const ImageVideoComposeRequest(
          imagePath: '/tmp/image.png',
          audioPath: '/tmp/audio.mp3',
          outputPath: '/tmp/output.mp4',
          targetWidth: 1080,
          targetHeight: 1920,
          frameRate: 120,
        ).validate(),
        returnsNormally,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // AudioMergeRequest
  // ─────────────────────────────────────────────────────────────────────────
  group('AudioMergeRequest', () {
    test('serializes all fields', () {
      const request = AudioMergeRequest(
        inputVideoPath: '/tmp/video.mp4',
        audioPath: '/tmp/audio.mp3',
        outputPath: '/tmp/output.mp4',
        replaceExistingAudio: true,
      );
      expect(request.toMap(), <String, Object?>{
        'inputVideoPath': '/tmp/video.mp4',
        'audioPath': '/tmp/audio.mp3',
        'outputPath': '/tmp/output.mp4',
        'replaceExistingAudio': true,
      });
    });

    test('defaults replaceExistingAudio to true', () {
      const request = AudioMergeRequest(
        inputVideoPath: '/tmp/video.mp4',
        audioPath: '/tmp/audio.mp3',
        outputPath: '/tmp/output.mp4',
      );
      expect(request.replaceExistingAudio, isTrue);
    });

    test('can set replaceExistingAudio to false', () {
      const request = AudioMergeRequest(
        inputVideoPath: '/tmp/video.mp4',
        audioPath: '/tmp/audio.mp3',
        outputPath: '/tmp/output.mp4',
        replaceExistingAudio: false,
      );
      expect(request.toMap()['replaceExistingAudio'], isFalse);
    });

    test('throws when inputVideoPath is empty', () {
      expect(
        () => const AudioMergeRequest(
          inputVideoPath: '',
          audioPath: '/tmp/audio.mp3',
          outputPath: '/tmp/output.mp4',
        ).validate(),
        throwsArgumentError,
      );
    });

    test('throws when audioPath is empty', () {
      expect(
        () => const AudioMergeRequest(
          inputVideoPath: '/tmp/video.mp4',
          audioPath: '',
          outputPath: '/tmp/output.mp4',
        ).validate(),
        throwsArgumentError,
      );
    });

    test('throws when outputPath is empty', () {
      expect(
        () => const AudioMergeRequest(
          inputVideoPath: '/tmp/video.mp4',
          audioPath: '/tmp/audio.mp3',
          outputPath: '',
        ).validate(),
        throwsArgumentError,
      );
    });

    test('throws when inputVideoPath equals outputPath', () {
      expect(
        () => const AudioMergeRequest(
          inputVideoPath: '/tmp/video.mp4',
          audioPath: '/tmp/audio.mp3',
          outputPath: '/tmp/video.mp4',
        ).validate(),
        throwsArgumentError,
      );
    });

    test('throws when audioPath equals outputPath', () {
      expect(
        () => const AudioMergeRequest(
          inputVideoPath: '/tmp/video.mp4',
          audioPath: '/tmp/audio.mp3',
          outputPath: '/tmp/audio.mp3',
        ).validate(),
        throwsArgumentError,
      );
    });

    test('valid request does not throw', () {
      expect(
        () => const AudioMergeRequest(
          inputVideoPath: '/tmp/video.mp4',
          audioPath: '/tmp/audio.mp3',
          outputPath: '/tmp/output.mp4',
        ).validate(),
        returnsNormally,
      );
    });
  });
}
