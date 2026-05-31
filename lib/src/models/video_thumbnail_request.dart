/// Describes a native thumbnail extraction request.
class VideoThumbnailRequest {
  /// Creates a thumbnail extraction request.
  const VideoThumbnailRequest({
    required this.inputPath,
    required this.outputPath,
    this.position = Duration.zero,
    this.quality = 90,
  });

  /// Path to the source video file.
  final String inputPath;

  /// Path where the extracted image should be written.
  ///
  /// Use a `.jpg`, `.jpeg`, or `.png` extension to select the output format.
  final String outputPath;

  /// Position in the source video to extract.
  final Duration position;

  /// JPEG quality from `1` to `100`.
  ///
  /// Ignored when [outputPath] ends with `.png`.
  final int quality;

  /// Converts this request to the method-channel payload.
  Map<String, Object?> toMap() {
    validate();

    return <String, Object?>{
      'inputPath': inputPath,
      'outputPath': outputPath,
      'positionMs': position.inMilliseconds,
      'quality': quality,
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
    if (inputPath == outputPath) {
      throw ArgumentError.value(
        outputPath,
        'outputPath',
        'Must be different from inputPath.',
      );
    }
    if (position.isNegative) {
      throw ArgumentError.value(position, 'position', 'Must not be negative.');
    }
    if (quality < 1 || quality > 100) {
      throw ArgumentError.value(quality, 'quality', 'Must be from 1 to 100.');
    }
  }
}
