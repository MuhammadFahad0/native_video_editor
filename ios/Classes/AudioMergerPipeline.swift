import AVFoundation
#if canImport(FlutterMacOS)
import FlutterMacOS
#else
import Flutter
#endif

/// Compatibility adapter preserving the shorter-of-video/audio duration policy.
final class AudioMergerPipeline {
  private let pipeline: CompositionAVPipeline
  init(channel: FlutterMethodChannel) { pipeline = CompositionAVPipeline(channel: channel) }
  func cancel() { pipeline.cancel() }
  func merge(_ request: AudioMergeRequest, completion: @escaping (Result<String, Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let video = try CompositionAVPipeline.mediaInfo(request.inputVideoPath)
        let audio = try CompositionAVPipeline.mediaInfo(request.audioPath)
        let duration = min(video["durationMs"] as? Int64 ?? 0, audio["durationMs"] as? Int64 ?? 0)
        var width = video["width"] as? Int ?? 1280, height = video["height"] as? Int ?? 720
        let rotation = video["rotationDegrees"] as? Int ?? 0
        if rotation == 90 || rotation == 270 { swap(&width, &height) }
        let args: [String: Any] = [
          "outputPath": request.outputPath,
          "settings": ["width": width / 2 * 2, "height": height / 2 * 2,
            "frameRate": 30, "videoBitrate": 4000000, "audioBitrate": 128000],
          "clips": [["path": request.inputVideoPath, "durationMs": duration,
            "volume": request.replaceExistingAudio ? 0.0 : 1.0]],
          "audioTracks": [["path": request.audioPath]]]
        self.pipeline.compose(args, completion: completion)
      } catch { completion(.failure(error)) }
    }
  }
}
