import 'video_crop_rect.dart';

class VideoEditRequest {
  const VideoEditRequest({
    required this.inputPath,
    required this.outputPath,
    this.trimStart,
    this.trimEnd,
    this.cropRect,
    this.targetWidth,
    this.targetHeight,
    this.rotationDegrees = 0,
    this.muteAudio = false,
  });

  final String inputPath;
  final String outputPath;
  final Duration? trimStart;
  final Duration? trimEnd;
  final VideoCropRect? cropRect;
  final int? targetWidth;
  final int? targetHeight;
  final int rotationDegrees;
  final bool muteAudio;

  Map<String, Object?> toMap() {
    validate();

    return <String, Object?>{
      'inputPath': inputPath,
      'outputPath': outputPath,
      'trimStartMs': trimStart?.inMilliseconds,
      'trimEndMs': trimEnd?.inMilliseconds,
      'cropRect': cropRect?.toMap(),
      'targetWidth': targetWidth,
      'targetHeight': targetHeight,
      'rotationDegrees': rotationDegrees,
      'muteAudio': muteAudio,
    };
  }

  void validate() {
    if (inputPath.trim().isEmpty) {
      throw ArgumentError.value(inputPath, 'inputPath', 'Must not be empty.');
    }
    if (outputPath.trim().isEmpty) {
      throw ArgumentError.value(outputPath, 'outputPath', 'Must not be empty.');
    }
    if (inputPath.trim() == outputPath.trim()) {
      throw ArgumentError('inputPath and outputPath must be different files.');
    }
    if (trimStart != null && trimStart!.isNegative) {
      throw ArgumentError.value(
        trimStart,
        'trimStart',
        'Must not be negative.',
      );
    }
    if (trimEnd != null && trimEnd!.isNegative) {
      throw ArgumentError.value(trimEnd, 'trimEnd', 'Must not be negative.');
    }
    if (trimStart != null && trimEnd != null && trimStart! >= trimEnd!) {
      throw ArgumentError('trimStart must be earlier than trimEnd.');
    }
    if ((targetWidth == null) != (targetHeight == null)) {
      throw ArgumentError(
        'targetWidth and targetHeight must be provided together.',
      );
    }
    if (targetWidth != null && (targetWidth! <= 0 || targetWidth!.isOdd)) {
      throw ArgumentError.value(
        targetWidth,
        'targetWidth',
        'Must be a positive even number.',
      );
    }
    if (targetHeight != null && (targetHeight! <= 0 || targetHeight!.isOdd)) {
      throw ArgumentError.value(
        targetHeight,
        'targetHeight',
        'Must be a positive even number.',
      );
    }
    if (!const <int>{0, 90, 180, 270}.contains(rotationDegrees)) {
      throw ArgumentError.value(
        rotationDegrees,
        'rotationDegrees',
        'Must be one of 0, 90, 180, or 270.',
      );
    }

    cropRect?.validate();
  }
}
