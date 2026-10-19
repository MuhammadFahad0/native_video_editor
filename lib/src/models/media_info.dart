/// Metadata reported by the native backend. Unsupported fields are null.
class MediaInfo {
  const MediaInfo({
    required this.duration,
    required this.width,
    required this.height,
    required this.hasAudio,
    this.rotationDegrees = 0,
    this.frameRate,
    this.bitrate,
    this.videoCodec,
    this.audioCodec,
    this.audioTracks = const [],
  });

  factory MediaInfo.fromMap(Map<Object?, Object?> map) => MediaInfo(
    duration: Duration(milliseconds: (map['durationMs'] as num).round()),
    width: (map['width'] as num?)?.toInt() ?? 0,
    height: (map['height'] as num?)?.toInt() ?? 0,
    hasAudio: map['hasAudio'] as bool? ?? false,
    rotationDegrees: (map['rotationDegrees'] as num?)?.toInt() ?? 0,
    frameRate: (map['frameRate'] as num?)?.toDouble(),
    bitrate: (map['bitrate'] as num?)?.toInt(),
    videoCodec: map['videoCodec'] as String?,
    audioCodec: map['audioCodec'] as String?,
    audioTracks:
        (map['audioTracks'] as List?)
            ?.map(
              (track) => AudioTrackInfo.fromMap(
                Map<Object?, Object?>.from(track as Map),
              ),
            )
            .toList() ??
        const [],
  );

  final Duration duration;

  /// Encoded dimensions, before applying rotation metadata.
  final int width;
  final int height;
  final bool hasAudio;
  final int rotationDegrees;
  final double? frameRate;
  final int? bitrate;

  /// Codec identifiers use each platform's native naming.
  final String? videoCodec;
  final String? audioCodec;
  final List<AudioTrackInfo> audioTracks;
}

/// One audio stream in a source file. Index follows native source track order.
class AudioTrackInfo {
  const AudioTrackInfo({
    required this.index,
    this.codec,
    this.sampleRate,
    this.channelCount,
    this.bitrate,
    this.language,
  });
  factory AudioTrackInfo.fromMap(Map<Object?, Object?> map) => AudioTrackInfo(
    index: (map['index'] as num).toInt(),
    codec: map['codec'] as String?,
    sampleRate: (map['sampleRate'] as num?)?.toInt(),
    channelCount: (map['channelCount'] as num?)?.toInt(),
    bitrate: (map['bitrate'] as num?)?.toInt(),
    language: map['language'] as String?,
  );
  final int index;
  final String? codec;
  final int? sampleRate;
  final int? channelCount;
  final int? bitrate;
  final String? language;
}
