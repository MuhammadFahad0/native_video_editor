import AVFoundation
import Foundation

#if canImport(FlutterMacOS)
import FlutterMacOS
#else
import Flutter
#endif

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class VideoAVPipeline {
  private let channel: FlutterMethodChannel
  private var exportSession: AVAssetExportSession?
  private var timer: Timer?
  private var isRunning = false
  private let lock = NSLock()

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  func process(
    _ request: VideoEditRequest,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try self.export(request, completion: completion)
      } catch {
        completion(.failure(error))
      }
    }
  }

  private func export(
    _ request: VideoEditRequest,
    completion: @escaping (Result<String, Error>) -> Void
  ) throws {
    let inputURL = URL(fileURLWithPath: request.inputPath)
    let outputURL = URL(fileURLWithPath: request.outputPath)
    let asset = AVURLAsset(url: inputURL)
    let composition = AVMutableComposition()

    guard let sourceVideoTrack = asset.tracks(withMediaType: .video).first else {
      throw VideoAVPipelineError.missingVideoTrack
    }

    let sourceRange = try makeSourceRange(asset: asset, request: request)
    guard let compositionVideoTrack = composition.addMutableTrack(
      withMediaType: .video,
      preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
      throw VideoAVPipelineError.unableToCreateTrack
    }

    try compositionVideoTrack.insertTimeRange(
      sourceRange,
      of: sourceVideoTrack,
      at: .zero
    )

    if !request.muteAudio,
      let sourceAudioTrack = asset.tracks(withMediaType: .audio).first,
      let compositionAudioTrack = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid
      ) {
      try compositionAudioTrack.insertTimeRange(sourceRange, of: sourceAudioTrack, at: .zero)
    }

    let exportDuration = scaledDuration(sourceRange.duration, speedMultiplier: request.speedMultiplier)
    if request.speedMultiplier != 1.0 {
      composition.scaleTimeRange(
        CMTimeRange(start: .zero, duration: sourceRange.duration),
        toDuration: exportDuration
      )
    }

    let videoComposition = makeVideoComposition(
      sourceTrack: sourceVideoTrack,
      compositionTrack: compositionVideoTrack,
      duration: exportDuration,
      request: request
    )

    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }

    guard let exportSession = AVAssetExportSession(
      asset: composition,
      presetName: AVAssetExportPresetHighestQuality
    ) else {
      throw VideoAVPipelineError.unableToCreateExportSession
    }

    lock.lock()
    self.exportSession = exportSession
    self.isRunning = true
    lock.unlock()

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.shouldOptimizeForNetworkUse = true
    exportSession.videoComposition = videoComposition

    DispatchQueue.main.async { [weak self, weak exportSession] in
      guard let self = self else { return }
      self.timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self, weak exportSession] timer in
        guard let self = self, let exportSession = exportSession else {
          timer.invalidate()
          return
        }
        self.lock.lock()
        let running = self.isRunning
        self.lock.unlock()
        if !running {
          timer.invalidate()
          return
        }

        let progress = Double(exportSession.progress)
        self.channel.invokeMethod("onProgress", arguments: [
          "outputPath": request.outputPath,
          "progress": progress
        ])

        if exportSession.status == .completed || exportSession.status == .failed || exportSession.status == .cancelled {
          timer.invalidate()
        }
      }
    }

    exportSession.exportAsynchronously { [weak self] in
      guard let self = self else { return }
      self.lock.lock()
      self.isRunning = false
      self.timer?.invalidate()
      self.timer = nil
      self.exportSession = nil
      self.lock.unlock()

      switch exportSession.status {
      case .completed:
        completion(.success(request.outputPath))
      case .failed, .cancelled:
        completion(.failure(exportSession.error ?? VideoAVPipelineError.exportFailed))
      default:
        completion(.failure(VideoAVPipelineError.exportFailed))
      }
    }
  }

  func cancel() {
    lock.lock()
    isRunning = false
    timer?.invalidate()
    timer = nil
    if let session = exportSession {
      session.cancelExport()
    }
    exportSession = nil
    lock.unlock()
  }

  func extractThumbnail(
    _ request: VideoThumbnailRequest,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let outputURL = URL(fileURLWithPath: request.outputPath)
        try FileManager.default.createDirectory(
          at: outputURL.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: outputURL.path) {
          try FileManager.default.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: URL(fileURLWithPath: request.inputPath))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(value: request.positionMs, timescale: 1000)
        let image = try generator.copyCGImage(at: time, actualTime: nil)
        let data: Data?
        #if canImport(UIKit)
        let uiImage = UIImage(cgImage: image)
        if outputURL.pathExtension.lowercased() == "png" {
          data = uiImage.pngData()
        } else {
          data = uiImage.jpegData(compressionQuality: CGFloat(request.quality) / 100.0)
        }
        #elseif canImport(AppKit)
        let rep = NSBitmapImageRep(cgImage: image)
        if outputURL.pathExtension.lowercased() == "png" {
          data = rep.representation(using: .png, properties: [:])
        } else {
          data = rep.representation(using: .jpeg, properties: [.compressionFactor: NSNumber(value: Float(request.quality) / 100.0)])
        }
        #else
        data = nil
        #endif

        guard let data = data else {
          throw VideoAVPipelineError.thumbnailEncodingFailed
        }

        try data.write(to: outputURL, options: .atomic)
        completion(.success(request.outputPath))
      } catch {
        completion(.failure(error))
      }
    }
  }

  private func makeSourceRange(asset: AVAsset, request: VideoEditRequest) throws -> CMTimeRange {
    let requestedStart = request.trimStartMs.map { millisecondsToTime($0) } ?? .zero
    let start = minTime(requestedStart, asset.duration)
    let requestedEnd = request.trimEndMs.map { millisecondsToTime($0) } ?? asset.duration
    let end = minTime(requestedEnd, asset.duration)

    guard CMTimeCompare(start, end) < 0 else {
      throw VideoAVPipelineError.invalidTrimRange
    }

    return CMTimeRange(start: start, end: end)
  }

  private func makeVideoComposition(
    sourceTrack: AVAssetTrack,
    compositionTrack: AVCompositionTrack,
    duration: CMTime,
    request: VideoEditRequest
  ) -> AVMutableVideoComposition {
    let sourceSize = orientedSize(for: sourceTrack)
    let cropFrame = makeCropFrame(sourceSize: sourceSize, cropRect: request.cropRect)
    let outputSize = makeOutputSize(cropFrame: cropFrame, request: request)

    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
    let transform = makeTransform(
      sourceTrack: sourceTrack,
      cropFrame: cropFrame,
      outputSize: outputSize,
      rotationDegrees: request.rotationDegrees
    )
    layerInstruction.setTransform(transform, at: .zero)
    instruction.layerInstructions = [layerInstruction]

    let videoComposition = AVMutableVideoComposition()
    videoComposition.instructions = [instruction]
    videoComposition.renderSize = outputSize
    videoComposition.frameDuration = CMTime(value: 1, timescale: max(1, Int32(sourceTrack.nominalFrameRate.rounded())))

    return videoComposition
  }

  private func makeTransform(
    sourceTrack: AVAssetTrack,
    cropFrame: CGRect,
    outputSize: CGSize,
    rotationDegrees: Int
  ) -> CGAffineTransform {
    let rotatedCropSize = rotationDegrees == 90 || rotationDegrees == 270
      ? CGSize(width: cropFrame.height, height: cropFrame.width)
      : cropFrame.size
    let scale = min(outputSize.width / rotatedCropSize.width, outputSize.height / rotatedCropSize.height)

    var transform = sourceTrack.preferredTransform
    let displayedRect = CGRect(origin: .zero, size: sourceTrack.naturalSize).applying(transform)

    // Ordered stages: source pixels -> upright display pixels -> cropped origin -> rotated crop -> scaled output.
    transform = transform.concatenating(
      CGAffineTransform(translationX: -displayedRect.minX - cropFrame.minX, y: -displayedRect.minY - cropFrame.minY)
    )

    let rotationTransform: CGAffineTransform
    switch rotationDegrees {
    case 90:
      rotationTransform = CGAffineTransform(rotationAngle: .pi / 2)
    case 180:
      rotationTransform = CGAffineTransform(rotationAngle: .pi)
    case 270:
      rotationTransform = CGAffineTransform(rotationAngle: -.pi / 2)
    default:
      rotationTransform = .identity
    }

    let cropBounds = CGRect(origin: .zero, size: cropFrame.size)
    let rotatedBounds = cropBounds.applying(rotationTransform)
    transform = transform.concatenating(rotationTransform)
    transform = transform.concatenating(
      CGAffineTransform(translationX: -rotatedBounds.minX, y: -rotatedBounds.minY)
    )

    transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))

    let scaledSize = CGSize(width: rotatedCropSize.width * scale, height: rotatedCropSize.height * scale)
    transform = transform.concatenating(
      CGAffineTransform(
        translationX: max(0, (outputSize.width - scaledSize.width) / 2),
        y: max(0, (outputSize.height - scaledSize.height) / 2)
      )
    )

    return transform
  }

  private func orientedSize(for track: AVAssetTrack) -> CGSize {
    let rect = CGRect(origin: .zero, size: track.naturalSize).applying(track.preferredTransform)
    return CGSize(width: abs(rect.width), height: abs(rect.height))
  }

  private func makeCropFrame(sourceSize: CGSize, cropRect: VideoCropRect?) -> CGRect {
    guard let cropRect = cropRect else {
      return CGRect(origin: .zero, size: sourceSize)
    }

    let rawFrame = CGRect(
      x: sourceSize.width * cropRect.left,
      y: sourceSize.height * cropRect.top,
      width: sourceSize.width * cropRect.width,
      height: sourceSize.height * cropRect.height
    )

    return CGRect(
      x: rawFrame.minX.rounded(.down),
      y: rawFrame.minY.rounded(.down),
      width: max(2, rawFrame.width.rounded(.down)),
      height: max(2, rawFrame.height.rounded(.down))
    )
  }

  private func makeOutputSize(cropFrame: CGRect, request: VideoEditRequest) -> CGSize {
    if let targetWidth = request.targetWidth, let targetHeight = request.targetHeight {
      return evenSize(width: CGFloat(targetWidth), height: CGFloat(targetHeight))
    }

    if request.rotationDegrees == 90 || request.rotationDegrees == 270 {
      return evenSize(width: cropFrame.height, height: cropFrame.width)
    }

    return evenSize(width: cropFrame.width, height: cropFrame.height)
  }

  private func evenSize(width: CGFloat, height: CGFloat) -> CGSize {
    CGSize(width: evenDimension(width), height: evenDimension(height))
  }

  private func evenDimension(_ value: CGFloat) -> CGFloat {
    max(2, (floor(value / 2) * 2))
  }

  private func scaledDuration(_ duration: CMTime, speedMultiplier: Double) -> CMTime {
    CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / speedMultiplier)
  }

  private func millisecondsToTime(_ milliseconds: Int64) -> CMTime {
    CMTime(value: milliseconds, timescale: 1000)
  }

  private func minTime(_ left: CMTime, _ right: CMTime) -> CMTime {
    CMTimeCompare(left, right) <= 0 ? left : right
  }
}

enum VideoAVPipelineError: LocalizedError {
  case missingVideoTrack
  case unableToCreateTrack
  case unableToCreateExportSession
  case invalidTrimRange
  case thumbnailEncodingFailed
  case exportFailed

  var errorDescription: String? {
    switch self {
    case .missingVideoTrack:
      return "The input asset does not contain a video track."
    case .unableToCreateTrack:
      return "Unable to create an AVFoundation composition track."
    case .unableToCreateExportSession:
      return "Unable to create an AVFoundation export session."
    case .invalidTrimRange:
      return "The requested trim range does not overlap the input asset duration."
    case .thumbnailEncodingFailed:
      return "Unable to encode the thumbnail image."
    case .exportFailed:
      return "The AVFoundation export failed."
    }
  }
}

// Shared by iOS and macOS through the existing macOS source symlink.
import CoreImage
import ImageIO

private func nveError(_ message: String) -> NSError {
  NSError(domain: "native_video_editor", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
private func nveNumber(_ map: [String: Any], _ key: String, _ fallback: Double = 0) -> Double {
  (map[key] as? NSNumber)?.doubleValue ?? fallback
}
private func nveTime(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 60000) }

private struct NVELayer {
  var trackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
  var image: CIImage?
  var transform = CGAffineTransform.identity
  var rect: CGRect
  var fit: String
  var flipX: Bool = false
  var flipY: Bool = false
  var opacity: Double = 1
  var start: Double
  var end: Double
}

private final class NVEInstruction: NSObject, AVVideoCompositionInstructionProtocol {
  let timeRange: CMTimeRange
  let enablePostProcessing = false
  let containsTweening = true
  let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
  let requiredSourceTrackIDs: [NSValue]?
  let layers: [NVELayer]
  init(range: CMTimeRange, layers: [NVELayer]) {
    self.timeRange = range; self.layers = layers
    self.requiredSourceTrackIDs = layers.filter { $0.image == nil }.map { NSNumber(value: $0.trackID) }
    super.init()
  }
}

/// Composites static alpha images and decoded video frames without losing alpha
/// in an intermediate movie. Every frame is rendered into an opaque black canvas.
private final class NVECompositor: NSObject, AVVideoCompositing {
  var sourcePixelBufferAttributes: [String: Any]? {
    [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
  }
  var requiredPixelBufferAttributesForRenderContext: [String: Any] {
    [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
     kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
  }
  private let context = CIContext(options: [.cacheIntermediates: false])
  func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}
  func cancelAllPendingVideoCompositionRequests() {}
  func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
    autoreleasepool {
      guard let instruction = request.videoCompositionInstruction as? NVEInstruction,
            let buffer = request.renderContext.newPixelBuffer() else {
        request.finish(with: nveError("Cannot allocate composition frame.")); return
      }
      let bounds = CGRect(origin: .zero, size: request.renderContext.size)
      var frame = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: bounds)
      let time = CMTimeGetSeconds(request.compositionTime)
      for layer in instruction.layers where time >= layer.start && time < layer.end {
        var image: CIImage
        if let still = layer.image { image = still }
        else if let source = request.sourceFrame(byTrackID: layer.trackID) {
          image = CIImage(cvPixelBuffer: source).transformed(by: layer.transform)
        } else { request.finish(with: nveError("Missing decoded video frame.")); return }
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let sourceSize = image.extent.size
        if layer.flipX || layer.flipY {
          image = image.transformed(by: CGAffineTransform(
            a: layer.flipX ? -1 : 1, b: 0, c: 0, d: layer.flipY ? -1 : 1,
            tx: layer.flipX ? sourceSize.width : 0, ty: layer.flipY ? sourceSize.height : 0))
        }
        let sx = layer.rect.width / sourceSize.width, sy = layer.rect.height / sourceSize.height
        let scaleX: CGFloat, scaleY: CGFloat
        if layer.fit == "stretch" { scaleX = sx; scaleY = sy }
        else { let scale = layer.fit == "cover" ? max(sx, sy) : min(sx, sy); scaleX = scale; scaleY = scale }
        image = image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        image = image.transformed(by: CGAffineTransform(
          translationX: layer.rect.minX + (layer.rect.width - sourceSize.width * scaleX) / 2,
          y: layer.rect.minY + (layer.rect.height - sourceSize.height * scaleY) / 2)).cropped(to: layer.rect)
        image = image.applyingFilter("CIColorMatrix", parameters: [
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(layer.opacity))])
        frame = image.composited(over: frame)
      }
      context.render(frame, to: buffer, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
      request.finish(withComposedVideoFrame: buffer)
    }
  }
}

final class CompositionAVPipeline {
  private let channel: FlutterMethodChannel
  private let lock = NSLock()
  private var cancelled = false
  private var temporaryURLs: [URL] = []
  init(channel: FlutterMethodChannel) { self.channel = channel }
  func cancel() { lock.lock(); cancelled = true; lock.unlock() }
  private func checkCancellation() throws {
    lock.lock(); let stopped = cancelled; lock.unlock()
    if stopped { throw nveError("Composition cancelled.") }
  }

  static func mediaInfo(_ path: String) throws -> [String: Any] {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let duration = CMTimeGetSeconds(asset.duration)
    guard duration.isFinite && duration > 0 else { throw nveError("Cannot read media duration.") }
    let video = asset.tracks(withMediaType: .video).first
    let audio = asset.tracks(withMediaType: .audio).first
    var rotation = 0
    if let transform = video?.preferredTransform {
      rotation = (Int((atan2(transform.b, transform.a) * 180 / .pi).rounded()) + 360) % 360
    }
    func codec(_ track: AVAssetTrack?) -> String? {
      guard let description = track?.formatDescriptions.first else { return nil }
      let value = CMFormatDescriptionGetMediaSubType(description as! CMFormatDescription)
      return String(bytes: [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255),
        UInt8((value >> 8) & 255), UInt8(value & 255)], encoding: .ascii)
    }
    var result: [String: Any] = ["durationMs": Int64(duration * 1000),
      "width": Int(video?.naturalSize.width ?? 0), "height": Int(video?.naturalSize.height ?? 0),
      "hasAudio": audio != nil, "rotationDegrees": rotation]
    if let video = video { result["frameRate"] = Double(video.nominalFrameRate); result["bitrate"] = Int(video.estimatedDataRate) }
    result["videoCodec"] = codec(video); result["audioCodec"] = codec(audio)
    result["audioTracks"] = asset.tracks(withMediaType: .audio).enumerated().map { index, track -> [String: Any] in
      var item: [String: Any] = ["index": index, "bitrate": Int(track.estimatedDataRate)]
      item["codec"] = codec(track); item["language"] = track.languageCode
      if let description = track.formatDescriptions.first,
         let format = CMAudioFormatDescriptionGetStreamBasicDescription(description as! CMAudioFormatDescription) {
        item["sampleRate"] = Int(format.pointee.mSampleRate)
        item["channelCount"] = Int(format.pointee.mChannelsPerFrame)
      }
      return item
    }
    return result
  }

  func compose(_ args: [String: Any], completion: @escaping (Result<String, Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      var createdOutput: URL?
      do {
        let output = try self.run(args, createdOutput: &createdOutput)
        completion(.success(output))
      } catch {
        if let output = createdOutput { try? FileManager.default.removeItem(at: output) }
        completion(.failure(error))
      }
      self.temporaryURLs.forEach { try? FileManager.default.removeItem(at: $0) }
      self.temporaryURLs.removeAll()
    }
  }

  private func run(_ args: [String: Any], createdOutput: inout URL?) throws -> String {
    guard let path = args["outputPath"] as? String,
          let clips = args["clips"] as? [[String: Any]], !clips.isEmpty,
          let settings = args["settings"] as? [String: Any] else { throw nveError("Invalid composition request.") }
    let overlays = args["overlays"] as? [[String: Any]] ?? []
    let audio = args["audioTracks"] as? [[String: Any]] ?? []
    let output = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    for source in clips + overlays + audio {
      if let input = source["path"] as? String,
         URL(fileURLWithPath: input).standardizedFileURL.resolvingSymlinksInPath() == output {
        throw nveError("Output must differ from every source file.")
      }
    }
    let width = Int(nveNumber(settings, "width")), height = Int(nveNumber(settings, "height"))
    let fps = Int(nveNumber(settings, "frameRate"))
    guard width >= 2 && height >= 2 && width <= 8192 && height <= 8192 && width % 2 == 0 && height % 2 == 0 && fps > 0 && fps <= 120 else {
      throw nveError("Invalid output size or frame rate.")
    }
    let size = CGSize(width: width, height: height)
    let fullRect = CGRect(origin: .zero, size: size)
    let composition = AVMutableComposition()
    var layers: [NVELayer] = []
    var audioParameters: [AVAudioMixInputParameters] = []
    var cursor = 0.0
    for clip in clips {
      try checkCancellation()
      guard let input = clip["path"] as? String else { throw nveError("Missing clip path.") }
      let isImage = clip["isImage"] as? Bool ?? false
      let start = nveNumber(clip, "trimStartMs") / 1000
      let asset: AVURLAsset
      let duration: Double
      if isImage {
        duration = nveNumber(clip, "durationMs") / 1000
        guard duration > 0, let image = CIImage(contentsOf: URL(fileURLWithPath: input), options: [.applyOrientationProperty: true]) else { throw nveError("Invalid image or image duration.") }
        let url = try makeImageMovie(image: image, duration: duration, size: size, fps: fps, clip: clip)
        asset = AVURLAsset(url: url)
      } else {
        asset = AVURLAsset(url: URL(fileURLWithPath: input))
        duration = try segmentDuration(asset, source: clip)
      }
      guard let source = asset.tracks(withMediaType: .video).first,
            let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw nveError("Missing video track.") }
      let range = CMTimeRange(start: nveTime(isImage ? 0 : start), duration: nveTime(duration))
      try track.insertTimeRange(range, of: source, at: nveTime(cursor))
      layers.append(NVELayer(trackID: track.trackID, transform: source.preferredTransform,
        rect: fullRect, fit: isImage ? "stretch" : (clip["fit"] as? String ?? "contain"),
        flipX: !isImage && (clip["flipHorizontal"] as? Bool ?? false),
        flipY: !isImage && (clip["flipVertical"] as? Bool ?? false), start: cursor, end: cursor + duration))
      if !isImage, nveNumber(clip, "volume", 1) > 0,
         let sourceAudio = asset.tracks(withMediaType: .audio).first {
        let available = max(0, min(duration, CMTimeGetSeconds(sourceAudio.timeRange.end) - start))
        if available > 0 { try addAudio(composition, source: sourceAudio, start: start, duration: available,
          at: cursor, volume: nveNumber(clip, "volume", 1), parameters: &audioParameters) }
      }
      cursor += duration
    }
    for overlay in overlays {
      let start = nveNumber(overlay, "startMs") / 1000
      if start >= cursor { continue }
      guard let rect = overlay["rect"] as? [String: Any] else { throw nveError("Missing overlay rectangle.") }
      let destination = CGRect(x: nveNumber(rect, "left") * size.width,
        y: (1 - nveNumber(rect, "top") - nveNumber(rect, "height")) * size.height,
        width: nveNumber(rect, "width") * size.width, height: nveNumber(rect, "height") * size.height)
      let requested = nveNumber(overlay, "durationMs", (cursor - start) * 1000) / 1000
      var layer = NVELayer(rect: destination, fit: overlay["fit"] as? String ?? "contain",
        opacity: nveNumber(overlay, "opacity", 1), start: start, end: min(cursor, start + requested))
      if overlay["type"] as? String == "video" {
        guard let path = overlay["path"] as? String else { throw nveError("Missing overlay path.") }
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let duration = min(try segmentDuration(asset, source: overlay), cursor - start)
        guard let source = asset.tracks(withMediaType: .video).first,
              let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw nveError("Missing overlay video track.") }
        try track.insertTimeRange(CMTimeRange(start: nveTime(nveNumber(overlay, "trimStartMs") / 1000), duration: nveTime(duration)), of: source, at: nveTime(start))
        layer.trackID = track.trackID; layer.transform = source.preferredTransform; layer.end = start + duration
      } else if let data = overlay["imageBytes"] as? FlutterStandardTypedData {
        layer.image = CIImage(data: data.data)
      } else if let path = overlay["path"] as? String {
        layer.image = CIImage(contentsOf: URL(fileURLWithPath: path), options: [.applyOrientationProperty: true])
      }
      guard layer.trackID != kCMPersistentTrackID_Invalid || layer.image != nil else { throw nveError("Cannot decode overlay image.") }
      layers.append(layer)
    }
    for audio in audio {
      guard let path = audio["path"] as? String else { throw nveError("Missing audio path.") }
      let asset = AVURLAsset(url: URL(fileURLWithPath: path))
      guard let source = asset.tracks(withMediaType: .audio).first else { throw nveError("Missing audio track.") }
      var at = nveNumber(audio, "startMs") / 1000
      let segment = try segmentDuration(asset, source: audio)
      guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw nveError("Cannot create audio track.") }
      let parameter = AVMutableAudioMixInputParameters(track: track)
      parameter.setVolume(Float(nveNumber(audio, "volume", 1)), at: .zero)
      audioParameters.append(parameter)
      while at < cursor {
        try checkCancellation()
        let duration = min(segment, cursor - at)
        try track.insertTimeRange(CMTimeRange(start: nveTime(nveNumber(audio, "trimStartMs") / 1000),
          duration: nveTime(duration)), of: source, at: nveTime(at))
        at += duration
        if audio["loop"] as? Bool != true { break }
      }
    }
    let cuts = Array(Set(([0, cursor] + layers.flatMap { [$0.start, $0.end] }).filter { $0 >= 0 && $0 <= cursor })).sorted()
    let videoComposition = AVMutableVideoComposition()
    videoComposition.customVideoCompositorClass = NVECompositor.self
    videoComposition.renderSize = size
    videoComposition.frameDuration = CMTime(value: 1, timescale: Int32(fps))
    videoComposition.instructions = (0..<(cuts.count - 1)).map { index in
      let start = cuts[index], end = cuts[index + 1]
      return NVEInstruction(range: CMTimeRange(start: nveTime(start), end: nveTime(end)),
        layers: layers.filter { $0.start < end && $0.end > start })
    }
    let mix = AVMutableAudioMix(); mix.inputParameters = audioParameters
    try checkCancellation()
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
    createdOutput = output
    try encode(composition, videoComposition: videoComposition, mix: mix, output: output,
      settings: settings, duration: cursor)
    return path
  }

  private func segmentDuration(_ asset: AVAsset, source: [String: Any]) throws -> Double {
    let remaining = CMTimeGetSeconds(asset.duration) - nveNumber(source, "trimStartMs") / 1000
    let duration = min(remaining, nveNumber(source, "durationMs", remaining * 1000) / 1000)
    guard duration.isFinite && duration > 0 else { throw nveError("Invalid source duration or trim range.") }
    return duration
  }

  private func addAudio(_ composition: AVMutableComposition, source: AVAssetTrack, start: Double,
    duration: Double, at: Double, volume: Double, parameters: inout [AVAudioMixInputParameters]) throws {
    guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw nveError("Cannot create audio track.") }
    try track.insertTimeRange(CMTimeRange(start: nveTime(start), duration: nveTime(duration)), of: source, at: nveTime(at))
    let parameter = AVMutableAudioMixInputParameters(track: track)
    parameter.setVolume(Float(volume), at: .zero); parameters.append(parameter)
  }

  private func encode(_ asset: AVAsset, videoComposition: AVVideoComposition, mix: AVAudioMix,
    output: URL, settings: [String: Any], duration: Double) throws {
    let reader = try AVAssetReader(asset: asset)
    let video = AVAssetReaderVideoCompositionOutput(videoTracks: asset.tracks(withMediaType: .video),
      videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    video.videoComposition = videoComposition
    guard reader.canAdd(video) else { throw nveError("Cannot create video reader.") }; reader.add(video)
    let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(nveNumber(settings, "width")),
      AVVideoHeightKey: Int(nveNumber(settings, "height")), AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: Int(nveNumber(settings, "videoBitrate")),
        AVVideoExpectedSourceFrameRateKey: Int(nveNumber(settings, "frameRate"))]])
    guard writer.canAdd(input) else { throw nveError("Cannot create video encoder.") }; writer.add(input)
    var streams: [(AVAssetReaderOutput, AVAssetWriterInput)] = [(video, input)]
    let audioTracks = asset.tracks(withMediaType: .audio)
    if !audioTracks.isEmpty {
      let audio = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsNonInterleaved: false])
      audio.audioMix = mix
      let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: Int(nveNumber(settings, "audioBitrate"))])
      guard reader.canAdd(audio) && writer.canAdd(input) else { throw nveError("Cannot configure audio encoder.") }
      reader.add(audio); writer.add(input); streams.append((audio, input))
    }
    guard writer.startWriting() else { throw writer.error ?? nveError("Cannot start writer.") }
    writer.startSession(atSourceTime: .zero)
    guard reader.startReading() else { throw reader.error ?? nveError("Cannot start reader.") }
    let group = DispatchGroup()
    let failureLock = NSLock(); var failure: Error?
    for (index, stream) in streams.enumerated() {
      let (source, destination) = stream
      group.enter()
      let queue = DispatchQueue(label: "native_video_editor.encode.\(index)")
      var ended = false
      var lastProgress = Date.distantPast
      destination.requestMediaDataWhenReady(on: queue) {
        if ended { return }
        while destination.isReadyForMoreMediaData {
          do {
            try self.checkCancellation()
            guard let sample = source.copyNextSampleBuffer() else {
              ended = true; destination.markAsFinished(); group.leave(); return
            }
            guard destination.append(sample) else { throw writer.error ?? nveError("Failed to append encoded sample.") }
            if index == 0 && Date().timeIntervalSince(lastProgress) > 0.25 {
              lastProgress = Date()
              let progress = min(0.99, CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)) / duration)
              DispatchQueue.main.async { self.channel.invokeMethod("onProgress", arguments: ["outputPath": output.path, "progress": progress]) }
            }
          } catch {
            failureLock.lock(); failure = error; failureLock.unlock()
            reader.cancelReading(); ended = true; destination.markAsFinished(); group.leave(); return
          }
        }
        if reader.status == .failed || writer.status == .failed {
          failureLock.lock(); failure = reader.error ?? writer.error; failureLock.unlock()
          ended = true; destination.markAsFinished(); group.leave()
        }
      }
    }
    // Poll cancellation even when an encoder stalls with backpressure.
    while group.wait(timeout: .now() + 0.1) == .timedOut {
      do { try checkCancellation() } catch { reader.cancelReading(); writer.cancelWriting(); throw error }
      failureLock.lock(); let processingError = failure; failureLock.unlock()
      if let error = processingError { reader.cancelReading(); writer.cancelWriting(); throw error }
      if reader.status == .failed || reader.status == .cancelled || writer.status == .failed || writer.status == .cancelled {
        let error = reader.error ?? writer.error ?? nveError("Encoding stopped before completion.")
        reader.cancelReading(); writer.cancelWriting(); throw error
      }
    }
    failureLock.lock(); let error = failure; failureLock.unlock()
    if let error = error { writer.cancelWriting(); throw error }
    guard reader.status == .completed else { writer.cancelWriting(); throw reader.error ?? nveError("Reader did not complete.") }
    writer.endSession(atSourceTime: nveTime(duration))
    let finished = DispatchSemaphore(value: 0)
    writer.finishWriting { finished.signal() }
    while finished.wait(timeout: .now() + 0.1) == .timedOut {
      do { try checkCancellation() } catch { writer.cancelWriting(); throw error }
    }
    guard writer.status == .completed else { throw writer.error ?? nveError("Export failed.") }
    DispatchQueue.main.async { self.channel.invokeMethod("onProgress", arguments: ["outputPath": output.path, "progress": 1.0]) }
  }

  private func makeImageMovie(image: CIImage, duration: Double, size: CGSize, fps: Int,
    clip: [String: Any]) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
    temporaryURLs.append(url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
      sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height)])
    guard writer.canAdd(input) else { throw nveError("Cannot configure image encoder.") }
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? nveError("Cannot encode image clip.") }
    writer.startSession(atSourceTime: .zero)
    var pixel: CVPixelBuffer?
    guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixel) == kCVReturnSuccess,
      let buffer = pixel else { writer.cancelWriting(); throw nveError("Cannot allocate image frame.") }
    var source = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    let original = source.extent.size
    if clip["flipHorizontal"] as? Bool == true || clip["flipVertical"] as? Bool == true {
      let x: CGFloat = clip["flipHorizontal"] as? Bool == true ? -1 : 1
      let y: CGFloat = clip["flipVertical"] as? Bool == true ? -1 : 1
      source = source.transformed(by: CGAffineTransform(a: x, b: 0, c: 0, d: y,
        tx: x < 0 ? original.width : 0, ty: y < 0 ? original.height : 0))
    }
    let fit = clip["fit"] as? String ?? "contain"
    let sx = size.width / original.width, sy = size.height / original.height
    let uniform = fit == "cover" ? max(sx, sy) : min(sx, sy)
    source = source.transformed(by: CGAffineTransform(scaleX: fit == "stretch" ? sx : uniform,
      y: fit == "stretch" ? sy : uniform))
    source = source.transformed(by: CGAffineTransform(translationX: (size.width - source.extent.width) / 2,
      y: (size.height - source.extent.height) / 2))
    let bounds = CGRect(origin: .zero, size: size)
    let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: bounds)
    CIContext().render(source.composited(over: black).cropped(to: bounds), to: buffer)
    do {
      for frame in 0..<Int(ceil(duration * Double(fps))) {
        while !input.isReadyForMoreMediaData {
          try checkCancellation()
          if writer.status == .failed { throw writer.error ?? nveError("Image encoding failed.") }
          Thread.sleep(forTimeInterval: 0.005)
        }
        try checkCancellation()
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: Int32(fps))) else { throw writer.error ?? nveError("Image frame append failed.") }
      }
      input.markAsFinished(); writer.endSession(atSourceTime: nveTime(duration))
      let done = DispatchSemaphore(value: 0); writer.finishWriting { done.signal() }
      while done.wait(timeout: .now() + 0.1) == .timedOut { try checkCancellation() }
      guard writer.status == .completed else { throw writer.error ?? nveError("Image encoding failed.") }
      return url
    } catch { writer.cancelWriting(); throw error }
  }
}
