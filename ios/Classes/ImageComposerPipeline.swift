import AVFoundation
import CoreVideo

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

/// Encodes a still image + audio file into an MP4 video using AVFoundation.
///
/// Strategy:
///  1. Load the still image with UIImage / CGImage.
///  2. Determine the composition duration from the audio asset (or audioDurationMs).
///  3. Use AVAssetWriter with a video track (pixel-buffer adaptor) and an audio
///     track (AVAssetReader → AVAssetWriterInput) writing them interleaved.
///  4. The video track writes the same pixel buffer at [frameRate] FPS for the
///     full duration.  The audio track copies compressed samples directly from
///     the source asset.
///  5. Progress is reported via the Flutter method channel on the main queue.
final class ImageComposerPipeline {
  private let channel: FlutterMethodChannel
  private let lock = NSLock()
  private var isCancelled = false

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  // MARK: – Public

  func compose(
    _ request: ImageComposeRequest,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try self.run(request, completion: completion)
      } catch {
        completion(.failure(error))
      }
    }
  }

  func cancel() {
    lock.lock()
    isCancelled = true
    lock.unlock()
  }

  // MARK: – Implementation

  private func run(
    _ request: ImageComposeRequest,
    completion: @escaping (Result<String, Error>) -> Void
  ) throws {
    // ── 1. Load image ──────────────────────────────────────────────────────
    let cgImage: CGImage?
    #if canImport(UIKit)
    cgImage = UIImage(contentsOfFile: request.imagePath)?.cgImage
    #elseif canImport(AppKit)
    if let nsImage = NSImage(contentsOfFile: request.imagePath) {
      var rect = CGRect(origin: .zero, size: nsImage.size)
      cgImage = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    } else {
      cgImage = nil
    }
    #else
    cgImage = nil
    #endif

    guard let loadedCGImage = cgImage else {
      throw ImageComposerError.invalidImage
    }


    // ── 2. Resolve the audio asset and duration ────────────────────────────
    let audioURL = URL(fileURLWithPath: request.audioPath)
    let audioAsset = AVURLAsset(url: audioURL)
    let audioDuration: CMTime
    if let ms = request.audioDurationMs {
      audioDuration = CMTime(value: ms, timescale: 1000)
    } else {
      // AVURLAsset duration may be .indefinite until loaded; use a sync load.
      let loaded = audioAsset.duration
      guard loaded.isNumeric && loaded > .zero else {
        throw ImageComposerError.unresolvableAudioDuration
      }
      audioDuration = loaded
    }

    // ── 3. Prepare output ──────────────────────────────────────────────────
    let outputURL = URL(fileURLWithPath: request.outputPath)
    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }

    // ── 4. Create AVAssetWriter ────────────────────────────────────────────
    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

    // Video settings.
    let width = request.targetWidth
    let height = request.targetHeight
    let videoSettings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: width * height * 2,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
      ],
    ]
    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    videoInput.expectsMediaDataInRealTime = false

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: videoInput,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
      ]
    )

    guard writer.canAdd(videoInput) else { throw ImageComposerError.cannotAddVideoInput }
    writer.add(videoInput)

    // Audio pass-through: read compressed audio samples directly.
    guard let sourceAudioTrack = audioAsset.tracks(withMediaType: .audio).first else {
      throw ImageComposerError.missingAudioTrack
    }
    let audioOutputSettings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: 44100,
      AVNumberOfChannelsKey: 2,
      AVEncoderBitRateKey: 128_000,
    ]
    let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioOutputSettings)
    audioInput.expectsMediaDataInRealTime = false
    guard writer.canAdd(audioInput) else { throw ImageComposerError.cannotAddAudioInput }
    writer.add(audioInput)

    // ── 5. AVAssetReader for audio ─────────────────────────────────────────
    let reader = try AVAssetReader(asset: audioAsset)
    let audioReaderOutput = AVAssetReaderTrackOutput(
      track: sourceAudioTrack,
      outputSettings: nil   // nil = compressed passthrough
    )
    // Clip audio to the target duration.
    reader.timeRange = CMTimeRange(start: .zero, duration: audioDuration)
    guard reader.canAdd(audioReaderOutput) else { throw ImageComposerError.cannotAddAudioReaderOutput }
    reader.add(audioReaderOutput)

    // ── 6. Build the pixel buffer from the image ───────────────────────────
    let pixelBuffer = try makePixelBuffer(from: loadedCGImage, width: width, height: height)

    // ── 7. Write ───────────────────────────────────────────────────────────
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    reader.startReading()

    let frameRate = request.frameRate
    let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
    let totalFrames = Int(CMTimeGetSeconds(audioDuration) * Double(frameRate)) + 1

    // Progress reporting timer on main thread.
    var framesWritten = 0
    let outputPath = request.outputPath
    let channelRef = channel
    var progressTimer: Timer?
    DispatchQueue.main.async {
      progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
        guard let self = self else { return }
        self.lock.lock()
        let cancelled = self.isCancelled
        self.lock.unlock()
        if cancelled { return }
        let progress = totalFrames > 0 ? Double(framesWritten) / Double(totalFrames) : 0
        channelRef.invokeMethod("onProgress", arguments: [
          "outputPath": outputPath,
          "progress": min(progress, 0.99)
        ])
      }
    }

    // Write video frames synchronously on the current background thread.
    let videoGroup = DispatchGroup()
    videoGroup.enter()
    let videoQueue = DispatchQueue(label: "image_composer.video")
    videoInput.requestMediaDataWhenReady(on: videoQueue) { [weak self] in
      guard let self = self else { videoGroup.leave(); return }
      while videoInput.isReadyForMoreMediaData {
        self.lock.lock()
        let cancelled = self.isCancelled
        self.lock.unlock()
        if cancelled { videoInput.markAsFinished(); videoGroup.leave(); return }

        let pts = CMTimeMultiply(frameDuration, multiplier: Int32(framesWritten))
        if CMTimeCompare(pts, audioDuration) >= 0 {
          videoInput.markAsFinished()
          videoGroup.leave()
          return
        }
        adaptor.append(pixelBuffer, withPresentationTime: pts)
        framesWritten += 1
      }
    }
    videoGroup.wait()

    // Write audio samples.
    let audioGroup = DispatchGroup()
    audioGroup.enter()
    let audioQueue = DispatchQueue(label: "image_composer.audio")
    audioInput.requestMediaDataWhenReady(on: audioQueue) { [weak self] in
      guard let self = self else { audioGroup.leave(); return }
      while audioInput.isReadyForMoreMediaData {
        self.lock.lock()
        let cancelled = self.isCancelled
        self.lock.unlock()
        if cancelled { audioInput.markAsFinished(); audioGroup.leave(); return }

        if let sample = audioReaderOutput.copyNextSampleBuffer() {
          audioInput.append(sample)
        } else {
          audioInput.markAsFinished()
          audioGroup.leave()
          return
        }
      }
    }
    audioGroup.wait()

    // Stop progress timer.
    DispatchQueue.main.async { progressTimer?.invalidate() }

    lock.lock()
    let wasCancelled = isCancelled
    lock.unlock()

    if wasCancelled {
      writer.cancelWriting()
      completion(.failure(ImageComposerError.cancelled))
      return
    }

    // Finish writing.
    let finishGroup = DispatchGroup()
    finishGroup.enter()
    writer.finishWriting {
      finishGroup.leave()
    }
    finishGroup.wait()

    // Final progress = 1.0
    DispatchQueue.main.async {
      channelRef.invokeMethod("onProgress", arguments: [
        "outputPath": outputPath,
        "progress": 1.0
      ])
    }

    switch writer.status {
    case .completed:
      completion(.success(request.outputPath))
    case .failed, .cancelled:
      completion(.failure(writer.error ?? ImageComposerError.writeFailed))
    default:
      completion(.failure(ImageComposerError.writeFailed))
    }
  }

  // MARK: – Helpers

  private func makePixelBuffer(
    from cgImage: CGImage,
    width: Int,
    height: Int
  ) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let attrs: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    ]
    CVPixelBufferCreate(
      kCFAllocatorDefault,
      width, height,
      kCVPixelFormatType_32BGRA,
      attrs as CFDictionary,
      &buffer
    )
    guard let pb = buffer else { throw ImageComposerError.pixelBufferCreationFailed }

    CVPixelBufferLockBaseAddress(pb, [])
    defer { CVPixelBufferUnlockBaseAddress(pb, []) }

    guard let ctx = CGContext(
      data: CVPixelBufferGetBaseAddress(pb),
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else {
      throw ImageComposerError.cgContextCreationFailed
    }

    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return pb
  }
}

// MARK: – Errors

enum ImageComposerError: LocalizedError {
  case invalidImage
  case unresolvableAudioDuration
  case missingAudioTrack
  case cannotAddVideoInput
  case cannotAddAudioInput
  case cannotAddAudioReaderOutput
  case pixelBufferCreationFailed
  case cgContextCreationFailed
  case writeFailed
  case cancelled

  var errorDescription: String? {
    switch self {
    case .invalidImage: return "Cannot load or decode the source image."
    case .unresolvableAudioDuration: return "Cannot determine the audio file duration."
    case .missingAudioTrack: return "The audio file does not contain an audio track."
    case .cannotAddVideoInput: return "Cannot add the video input to the asset writer."
    case .cannotAddAudioInput: return "Cannot add the audio input to the asset writer."
    case .cannotAddAudioReaderOutput: return "Cannot add the audio reader output."
    case .pixelBufferCreationFailed: return "Cannot create a CVPixelBuffer."
    case .cgContextCreationFailed: return "Cannot create a CGContext for pixel rendering."
    case .writeFailed: return "AVAssetWriter finished with an error."
    case .cancelled: return "The composition was cancelled."
    }
  }
}
