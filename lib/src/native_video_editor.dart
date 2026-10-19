import 'models/audio_merge_request.dart';
import 'models/media_info.dart';
import 'models/video_composition_request.dart';
import 'models/image_video_compose_request.dart';
import 'native_video_editor_platform_interface.dart';
import 'models/video_edit_request.dart';
import 'models/video_thumbnail_request.dart';

/// Entry point for native video editing operations.
///
/// The plugin performs edits with AndroidX Media3 Transformer on Android and
/// AVFoundation on iOS. All input and output paths must point to files that the
/// host app can access.
class NativeVideoEditor {
  const NativeVideoEditor._();

  static Future<MediaInfo> getMediaInfo(String inputPath) =>
      NativeVideoEditorPlatform.instance.getMediaInfo(inputPath);

  /// Exports a timeline with audio, watermarks, captions and picture-in-picture.
  /// Cancel with [cancelProcessVideo], using the composition's output path.
  static Future<String> composeVideo(
    VideoCompositionRequest request, {
    void Function(double progress)? onProgress,
  }) async {
    request.toMap();
    final platform = NativeVideoEditorPlatform.instance;
    if (platform.progressCallbacks.containsKey(request.outputPath)) {
      throw StateError('An export is already active for this output path.');
    }
    platform.progressCallbacks[request.outputPath] = onProgress ?? (_) {};
    try {
      return await platform.composeVideo(request);
    } finally {
      platform.progressCallbacks.remove(request.outputPath);
    }
  }

  /// Re-encodes a video to H.264/AAC with explicit resolution and bitrates.
  static Future<String> compressVideo({
    required String inputPath,
    required String outputPath,
    VideoExportSettings settings = const VideoExportSettings(),
    VideoFit fit = VideoFit.contain,
    bool flipHorizontal = false,
    bool flipVertical = false,
    void Function(double progress)? onProgress,
  }) => composeVideo(
    VideoCompositionRequest(
      outputPath: outputPath,
      settings: settings,
      clips: [
        VideoClip.video(
          inputPath,
          fit: fit,
          flipHorizontal: flipHorizontal,
          flipVertical: flipVertical,
        ),
      ],
    ),
    onProgress: onProgress,
  );

  /// Joins clips in order; sources are fitted to the requested output canvas.
  static Future<String> joinVideos({
    required List<String> inputPaths,
    required String outputPath,
    VideoExportSettings settings = const VideoExportSettings(),
    VideoFit fit = VideoFit.contain,
    void Function(double progress)? onProgress,
  }) => composeVideo(
    VideoCompositionRequest(
      outputPath: outputPath,
      settings: settings,
      clips: inputPaths.map((p) => VideoClip.video(p, fit: fit)).toList(),
    ),
    onProgress: onProgress,
  );

  /// Creates a slideshow with a fixed duration per image and optional music.
  static Future<String> createSlideshow({
    required List<String> imagePaths,
    required String outputPath,
    Duration imageDuration = const Duration(seconds: 3),
    VideoExportSettings settings = const VideoExportSettings(),
    VideoFit fit = VideoFit.contain,
    List<CompositionAudioTrack> audioTracks = const [],
    void Function(double progress)? onProgress,
  }) => composeVideo(
    VideoCompositionRequest(
      outputPath: outputPath,
      settings: settings,
      clips: imagePaths
          .map((p) => VideoClip.image(p, duration: imageDuration, fit: fit))
          .toList(),
      audioTracks: audioTracks,
    ),
    onProgress: onProgress,
  );

  /// Extracts frames sequentially in request order using the native extractor.
  /// [outputPaths] must contain one unique path per position. Existing files are replaced.
  static Future<List<String>> extractThumbnails({
    required String inputPath,
    required List<Duration> positions,
    required List<String> outputPaths,
    int quality = 90,
    void Function(double progress)? onProgress,
  }) async {
    if (positions.isEmpty ||
        positions.length != outputPaths.length ||
        outputPaths.toSet().length != outputPaths.length) {
      throw ArgumentError(
        'Provide nonempty positions and matching unique output paths.',
      );
    }
    final requests = List.generate(
      positions.length,
      (i) => VideoThumbnailRequest(
        inputPath: inputPath,
        outputPath: outputPaths[i],
        position: positions[i],
        quality: quality,
      ),
    );
    for (final request in requests) {
      request.toMap();
    }
    final outputs = <String>[];
    for (final request in requests) {
      outputs.add(await extractThumbnail(request));
      onProgress?.call(outputs.length / requests.length);
    }
    return outputs;
  }

  /// Processes a video with one or more edits and returns the output path.
  ///
  /// The request can combine trimming, normalized cropping, resizing, rotation,
  /// speed adjustment, and audio muting in a single native export operation.
  /// An optional [onProgress] callback can be provided to receive progress updates (0.0 to 1.0).
  static Future<String> processVideo(
    VideoEditRequest request, {
    void Function(double progress)? onProgress,
  }) async {
    if (onProgress != null) {
      NativeVideoEditorPlatform.instance.progressCallbacks[request.outputPath] =
          onProgress;
    }
    try {
      return await NativeVideoEditorPlatform.instance.processVideo(request);
    } finally {
      NativeVideoEditorPlatform.instance.progressCallbacks.remove(
        request.outputPath,
      );
    }
  }

  /// Cancels an active video processing operation for the given [outputPath].
  static Future<void> cancelProcessVideo(String outputPath) {
    return NativeVideoEditorPlatform.instance.cancelProcessVideo(outputPath);
  }

  /// Extracts a thumbnail image from a video and returns the output path.
  static Future<String> extractThumbnail(VideoThumbnailRequest request) {
    return NativeVideoEditorPlatform.instance.extractThumbnail(request);
  }

  /// Composes a still image and an audio file into an MP4 video.
  ///
  /// The still image is rendered as a static video frame for the full duration
  /// of the audio (capped by [ImageVideoComposeRequest.audioDurationMs] if set).
  ///
  /// An optional [onProgress] callback receives values from 0.0 to 1.0 as the
  /// composition progresses.
  ///
  /// Returns the output path of the composed MP4.
  static Future<String> composeImageWithAudio(
    ImageVideoComposeRequest request, {
    void Function(double progress)? onProgress,
  }) async {
    if (onProgress != null) {
      NativeVideoEditorPlatform.instance.progressCallbacks[request.outputPath] =
          onProgress;
    }
    try {
      return await NativeVideoEditorPlatform.instance.composeImageWithAudio(
        request,
      );
    } finally {
      NativeVideoEditorPlatform.instance.progressCallbacks.remove(
        request.outputPath,
      );
    }
  }

  /// Merges an audio track into an existing video file.
  ///
  /// When [AudioMergeRequest.replaceExistingAudio] is `true` (the default) the
  /// original audio track is removed before the new audio is injected.
  ///
  /// When audio and video durations differ, the shorter of the two determines
  /// the output duration (audio is truncated / video is trimmed accordingly).
  ///
  /// An optional [onProgress] callback receives values from 0.0 to 1.0.
  ///
  /// Returns the output path of the merged MP4.
  static Future<String> mergeAudioIntoVideo(
    AudioMergeRequest request, {
    void Function(double progress)? onProgress,
  }) async {
    if (onProgress != null) {
      NativeVideoEditorPlatform.instance.progressCallbacks[request.outputPath] =
          onProgress;
    }
    try {
      return await NativeVideoEditorPlatform.instance.mergeAudioIntoVideo(
        request,
      );
    } finally {
      NativeVideoEditorPlatform.instance.progressCallbacks.remove(
        request.outputPath,
      );
    }
  }
}
