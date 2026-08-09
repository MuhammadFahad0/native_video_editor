/// Describes a request to merge an audio track into an existing video file.
///
/// The output MP4 at [outputPath] will contain the video stream from
/// [inputVideoPath] and the audio stream from [audioPath].
///
/// When the audio is longer than the video, it is truncated to the video
/// duration. When it is shorter, the video is trimmed to the audio duration.
class AudioMergeRequest {
  /// Creates an audio-merge request.
  const AudioMergeRequest({
    required this.inputVideoPath,
    required this.audioPath,
    required this.outputPath,
    this.replaceExistingAudio = true,
  });

  /// Path to the source video file (MP4, MOV, etc.).
  ///
  /// The file must be readable by the host app.
  final String inputVideoPath;

  /// Path to the audio file to inject (MP3, AAC, WAV, M4A, etc.).
  ///
  /// The file must be readable by the host app.
  final String audioPath;

  /// Path where the merged MP4 should be written.
  ///
  /// Must differ from both [inputVideoPath] and [audioPath].
  final String outputPath;

  /// Whether to strip any existing audio from [inputVideoPath] before merging.
  ///
  /// Defaults to `true`. Set to `false` to keep the original audio track in
  /// addition to the injected one (mixing is not guaranteed on all platforms;
  /// behaviour is implementation-defined when `false`).
  final bool replaceExistingAudio;

  /// Converts this request to the method-channel payload.
  Map<String, Object?> toMap() {
    validate();

    return <String, Object?>{
      'inputVideoPath': inputVideoPath,
      'audioPath': audioPath,
      'outputPath': outputPath,
      'replaceExistingAudio': replaceExistingAudio,
    };
  }

  /// Throws an [ArgumentError] if this request is not valid.
  void validate() {
    if (inputVideoPath.trim().isEmpty) {
      throw ArgumentError.value(
        inputVideoPath,
        'inputVideoPath',
        'Must not be empty.',
      );
    }
    if (audioPath.trim().isEmpty) {
      throw ArgumentError.value(audioPath, 'audioPath', 'Must not be empty.');
    }
    if (outputPath.trim().isEmpty) {
      throw ArgumentError.value(
        outputPath,
        'outputPath',
        'Must not be empty.',
      );
    }
    if (inputVideoPath.trim() == outputPath.trim()) {
      throw ArgumentError(
        'inputVideoPath and outputPath must be different files.',
      );
    }
    if (audioPath.trim() == outputPath.trim()) {
      throw ArgumentError('audioPath and outputPath must be different files.');
    }
  }
}
