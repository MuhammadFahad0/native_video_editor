/// Describes a request to compose a still image and an audio file into an MP4
/// video.
///
/// The encoder will render the [imagePath] as a static video frame for the full
/// duration of the [audioPath] audio (or [audioDurationMs] if provided), and
/// mux the two streams into a single MP4 at [outputPath].
class ImageVideoComposeRequest {
  /// Creates an image-to-video composition request.
  ///
  /// [imagePath], [audioPath], and [outputPath] are required.
  /// [targetWidth] and [targetHeight] must be provided together as positive
  /// even numbers.
  const ImageVideoComposeRequest({
    required this.imagePath,
    required this.audioPath,
    required this.outputPath,
    required this.targetWidth,
    required this.targetHeight,
    this.audioDurationMs,
    this.frameRate = 30,
  });

  /// Path to the source still image (PNG or JPEG).
  ///
  /// The file must be readable by the host app.
  final String imagePath;

  /// Path to the source audio file (MP3, AAC, WAV, M4A, etc.).
  ///
  /// The file must be readable by the host app.
  final String audioPath;

  /// Path where the composed MP4 should be written.
  ///
  /// Must differ from both [imagePath] and [audioPath].
  final String outputPath;

  /// Target output width in pixels.
  ///
  /// Must be a positive even number. Provided together with [targetHeight].
  final int targetWidth;

  /// Target output height in pixels.
  ///
  /// Must be a positive even number. Provided together with [targetWidth].
  final int targetHeight;

  /// Optional cap on the audio duration used, in milliseconds.
  ///
  /// When `null` the full audio duration is used. When set, the output video
  /// will be at most this many milliseconds long.
  final int? audioDurationMs;

  /// Frames per second for the output video. Defaults to `30`.
  ///
  /// Must be a positive integer between 1 and 120.
  final int frameRate;

  /// Converts this request to the method-channel payload.
  Map<String, Object?> toMap() {
    validate();

    return <String, Object?>{
      'imagePath': imagePath,
      'audioPath': audioPath,
      'outputPath': outputPath,
      'targetWidth': targetWidth,
      'targetHeight': targetHeight,
      'audioDurationMs': audioDurationMs,
      'frameRate': frameRate,
    };
  }

  /// Throws an [ArgumentError] if this request is not valid.
  void validate() {
    if (imagePath.trim().isEmpty) {
      throw ArgumentError.value(imagePath, 'imagePath', 'Must not be empty.');
    }
    if (audioPath.trim().isEmpty) {
      throw ArgumentError.value(audioPath, 'audioPath', 'Must not be empty.');
    }
    if (outputPath.trim().isEmpty) {
      throw ArgumentError.value(outputPath, 'outputPath', 'Must not be empty.');
    }
    if (targetWidth <= 0 || targetWidth.isOdd) {
      throw ArgumentError.value(
        targetWidth,
        'targetWidth',
        'Must be a positive even number.',
      );
    }
    if (targetHeight <= 0 || targetHeight.isOdd) {
      throw ArgumentError.value(
        targetHeight,
        'targetHeight',
        'Must be a positive even number.',
      );
    }
    if (audioDurationMs != null && audioDurationMs! <= 0) {
      throw ArgumentError.value(
        audioDurationMs,
        'audioDurationMs',
        'Must be a positive integer.',
      );
    }
    if (frameRate < 1 || frameRate > 120) {
      throw ArgumentError.value(
        frameRate,
        'frameRate',
        'Must be between 1 and 120.',
      );
    }
  }
}
