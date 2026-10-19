import AVFoundation
#if canImport(FlutterMacOS)
import FlutterMacOS
#else
import Flutter
#endif

/// Compatibility adapter for the original image/audio API.
final class ImageComposerPipeline {
  private let pipeline: CompositionAVPipeline
  init(channel: FlutterMethodChannel) { pipeline = CompositionAVPipeline(channel: channel) }
  func cancel() { pipeline.cancel() }
  func compose(_ request: ImageComposeRequest, completion: @escaping (Result<String, Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let info = try CompositionAVPipeline.mediaInfo(request.audioPath)
        let duration = min((info["durationMs"] as? Int64 ?? 0), request.audioDurationMs ?? Int64.max)
        let args: [String: Any] = [
          "outputPath": request.outputPath,
          "settings": ["width": request.targetWidth, "height": request.targetHeight,
            "frameRate": request.frameRate, "videoBitrate": 4000000, "audioBitrate": 128000],
          "clips": [["path": request.imagePath, "isImage": true, "durationMs": duration, "fit": "contain"]],
          "audioTracks": [["path": request.audioPath]]]
        self.pipeline.compose(args, completion: completion)
      } catch { completion(.failure(error)) }
    }
  }
}
