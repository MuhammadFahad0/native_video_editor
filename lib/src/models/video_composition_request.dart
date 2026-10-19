import 'video_crop_rect.dart';

/// How a source fits its destination rectangle. Empty space is black.
enum VideoFit { contain, cover, stretch }

/// H.264/AAC MP4 encoding settings. Encoders may reject unsupported sizes/rates.
class VideoExportSettings {
  const VideoExportSettings.low()
    : this(
        width: 640,
        height: 360,
        frameRate: 24,
        videoBitrate: 800000,
        audioBitrate: 96000,
      );
  const VideoExportSettings.medium() : this(videoBitrate: 2000000);
  const VideoExportSettings.high()
    : this(
        width: 1920,
        height: 1080,
        videoBitrate: 8000000,
        audioBitrate: 192000,
      );

  const VideoExportSettings({
    this.width = 1280,
    this.height = 720,
    this.frameRate = 30,
    this.videoBitrate = 4000000,
    this.audioBitrate = 128000,
  });

  final int width;
  final int height;
  final int frameRate;
  final int videoBitrate;
  final int audioBitrate;

  Map<String, Object?> toMap() {
    if (width < 2 ||
        height < 2 ||
        width.isOdd ||
        height.isOdd ||
        width > 8192 ||
        height > 8192) {
      throw ArgumentError('Output dimensions must be even and from 2 to 8192.');
    }
    if (frameRate < 1 ||
        frameRate > 120 ||
        videoBitrate <= 0 ||
        audioBitrate <= 0 ||
        videoBitrate > 2147483647 ||
        audioBitrate > 2147483647) {
      throw ArgumentError('Use 1–120 FPS and bitrates from 1 to 2147483647.');
    }
    return {
      'width': width,
      'height': height,
      'frameRate': frameRate,
      'videoBitrate': videoBitrate,
      'audioBitrate': audioBitrate,
    };
  }
}

/// A video segment or still image in the main sequential timeline.
class VideoClip {
  const VideoClip.video(
    this.path, {
    this.trimStart = Duration.zero,
    this.duration,
    this.volume = 1,
    this.fit = VideoFit.contain,
    this.flipHorizontal = false,
    this.flipVertical = false,
  }) : isImage = false;

  const VideoClip.image(
    this.path, {
    required Duration this.duration,
    this.fit = VideoFit.contain,
    this.flipHorizontal = false,
    this.flipVertical = false,
  }) : isImage = true,
       trimStart = Duration.zero,
       volume = 0;

  final String path;
  final bool isImage;
  final Duration trimStart;
  final Duration? duration;
  final double volume;
  final VideoFit fit;
  final bool flipHorizontal;
  final bool flipVertical;

  Map<String, Object?> toMap() {
    _path(path);
    _time(trimStart, 'trimStart');
    _duration(duration);
    _unit(volume, 'volume');
    if (isImage && duration == null) {
      throw ArgumentError('Image clips require a duration.');
    }
    return {
      'path': path,
      'isImage': isImage,
      'trimStartMs': trimStart.inMilliseconds,
      'durationMs': duration?.inMilliseconds,
      'volume': volume,
      'fit': fit.name,
      'flipHorizontal': flipHorizontal,
      'flipVertical': flipVertical,
    };
  }
}

/// Background audio, delayed on the timeline and optionally repeated to its end.
class CompositionAudioTrack {
  const CompositionAudioTrack(
    this.path, {
    this.start = Duration.zero,
    this.trimStart = Duration.zero,
    this.duration,
    this.volume = 1,
    this.loop = false,
  });

  final String path;
  final Duration start;
  final Duration trimStart;

  /// Limits the source segment before repeating it when [loop] is true.
  final Duration? duration;
  final double volume;
  final bool loop;

  Map<String, Object?> toMap() {
    _path(path);
    _time(start, 'start');
    _time(trimStart, 'trimStart');
    _duration(duration);
    _unit(volume, 'volume');
    return {
      'path': path,
      'startMs': start.inMilliseconds,
      'trimStartMs': trimStart.inMilliseconds,
      'durationMs': duration?.inMilliseconds,
      'volume': volume,
      'loop': loop,
    };
  }
}

/// An image watermark, text caption, or silent picture-in-picture video.
///
/// Rectangles use normalized top-left coordinates in the final output canvas.
/// Later overlays are drawn above earlier overlays. A null duration extends an
/// image/text overlay to the end; video overlays stop at their source's end.
class VideoOverlay {
  const VideoOverlay.image(
    String this.path, {
    required this.rect,
    this.start = Duration.zero,
    this.duration,
    this.opacity = 1,
    this.fit = VideoFit.contain,
  }) : text = null,
       type = 'image',
       trimStart = Duration.zero,
       fontSize = 32,
       color = 0xFFFFFFFF,
       backgroundColor = 0x00000000;

  const VideoOverlay.video(
    String this.path, {
    required this.rect,
    this.start = Duration.zero,
    this.duration,
    this.trimStart = Duration.zero,
    this.opacity = 1,
    this.fit = VideoFit.contain,
  }) : text = null,
       type = 'video',
       fontSize = 32,
       color = 0xFFFFFFFF,
       backgroundColor = 0x00000000;

  const VideoOverlay.text(
    String this.text, {
    required this.rect,
    this.start = Duration.zero,
    this.duration,
    this.opacity = 1,
    this.fontSize = 32,
    this.color = 0xFFFFFFFF,
    this.backgroundColor = 0x00000000,
  }) : path = null,
       type = 'text',
       trimStart = Duration.zero,
       fit = VideoFit.contain;

  final String type;
  final String? path;
  final String? text;
  final VideoCropRect rect;
  final Duration start;
  final Duration? duration;
  final Duration trimStart;
  final double opacity;
  final VideoFit fit;

  /// Text size in pixels of the output canvas; text wraps and clips to [rect].
  final double fontSize;

  /// ARGB colors, including alpha.
  final int color;
  final int backgroundColor;

  Map<String, Object?> toMap() {
    rect.validate();
    _time(start, 'start');
    _time(trimStart, 'trimStart');
    _duration(duration);
    _unit(opacity, 'opacity');
    if (type == 'text') {
      if (text == null ||
          text!.trim().isEmpty ||
          !fontSize.isFinite ||
          fontSize <= 0) {
        throw ArgumentError(
          'Text must not be empty and fontSize must be positive.',
        );
      }
      if (color < 0 ||
          color > 0xFFFFFFFF ||
          backgroundColor < 0 ||
          backgroundColor > 0xFFFFFFFF) {
        throw ArgumentError('Colors must be 32-bit ARGB values.');
      }
    } else {
      _path(path!);
    }
    return {
      'type': type,
      'path': path,
      'text': text,
      'rect': rect.toMap(),
      'startMs': start.inMilliseconds,
      'durationMs': duration?.inMilliseconds,
      'trimStartMs': trimStart.inMilliseconds,
      'opacity': opacity,
      'fit': fit.name,
      'fontSize': fontSize,
      'color': color,
      'backgroundColor': backgroundColor,
    };
  }
}

/// A sequential main timeline with independently timed overlays/audio tracks.
class VideoCompositionRequest {
  const VideoCompositionRequest({
    required this.clips,
    required this.outputPath,
    this.settings = const VideoExportSettings(),
    this.overlays = const [],
    this.audioTracks = const [],
  });

  final List<VideoClip> clips;
  final String outputPath;
  final VideoExportSettings settings;
  final List<VideoOverlay> overlays;
  final List<CompositionAudioTrack> audioTracks;

  Map<String, Object?> toMap() {
    _path(outputPath);
    if (clips.isEmpty) throw ArgumentError('At least one clip is required.');
    if (!outputPath.toLowerCase().endsWith('.mp4')) {
      throw ArgumentError('Composition output must use the .mp4 extension.');
    }
    final sources = [
      ...clips.map((c) => c.path),
      ...overlays.where((o) => o.path != null).map((o) => o.path!),
      ...audioTracks.map((a) => a.path),
    ];
    if (sources.any((p) => p.trim() == outputPath.trim())) {
      throw ArgumentError('Output must differ from every source file.');
    }
    return {
      'clips': clips.map((c) => c.toMap()).toList(),
      'outputPath': outputPath,
      'settings': settings.toMap(),
      'overlays': overlays.map((o) => o.toMap()).toList(),
      'audioTracks': audioTracks.map((a) => a.toMap()).toList(),
    };
  }
}

void _path(String value) {
  if (value.trim().isEmpty) throw ArgumentError('Paths must not be empty.');
}

void _time(Duration value, String name) {
  if (value.isNegative || value.inMilliseconds > 2147483647) {
    throw ArgumentError('$name must be nonnegative and at most 2147483647 ms.');
  }
}

void _duration(Duration? value) {
  if (value != null) {
    _time(value, 'duration');
    if (value.inMilliseconds == 0) {
      throw ArgumentError('Duration must be at least 1 ms.');
    }
  }
}

void _unit(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError('$name must be finite and between 0 and 1.');
  }
}
