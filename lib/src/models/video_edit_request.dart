import 'video_crop_rect.dart';

/// Describes a native video export request.
///
/// All configured edits are applied in a single native processing operation.
/// At least [inputPath] and [outputPath] are required.
class VideoEditRequest {
  /// Creates a video edit request.
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

  /// Path to the source video file.
  ///
  /// The file must be readable by the host app.
  final String inputPath;

  /// Path where the processed video should be written.
  ///
  /// This path must be different from [inputPath]. Existing files are replaced
  /// by the native exporter.
  final String outputPath;

  /// Optional inclusive trim start time.
  final Duration? trimStart;

  /// Optional exclusive trim end time.
  final Duration? trimEnd;

  /// Optional normalized crop rectangle.
  final VideoCropRect? cropRect;

  /// Optional target output width in pixels.
  ///
  /// Must be provided together with [targetHeight] and must be an even number.
  final int? targetWidth;

  /// Optional target output height in pixels.
  ///
  /// Must be provided together with [targetWidth] and must be an even number.
  final int? targetHeight;

  /// Clockwise rotation to apply, in degrees.
  ///
  /// Supported values are `0`, `90`, `180`, and `270`.
  final int rotationDegrees;

  /// Whether to omit audio from the exported video.
  final bool muteAudio;

  /// Converts this request to the method-channel payload.
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

  /// Throws an [ArgumentError] if this request is not valid.
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
