import AVFoundation
import Foundation
import UIKit

final class VideoAVPipeline {
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

    let videoComposition = makeVideoComposition(
      sourceTrack: sourceVideoTrack,
      compositionTrack: compositionVideoTrack,
      duration: sourceRange.duration,
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

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.shouldOptimizeForNetworkUse = true
    exportSession.videoComposition = videoComposition

    exportSession.exportAsynchronously {
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

    switch rotationDegrees {
    case 90:
      transform = transform.concatenating(CGAffineTransform(translationX: cropFrame.height, y: 0))
      transform = transform.concatenating(CGAffineTransform(rotationAngle: .pi / 2))
    case 180:
      transform = transform.concatenating(CGAffineTransform(translationX: cropFrame.width, y: cropFrame.height))
      transform = transform.concatenating(CGAffineTransform(rotationAngle: .pi))
    case 270:
      transform = transform.concatenating(CGAffineTransform(translationX: 0, y: cropFrame.width))
      transform = transform.concatenating(CGAffineTransform(rotationAngle: -.pi / 2))
    default:
      break
    }

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
    case .exportFailed:
      return "The AVFoundation export failed."
    }
  }
}
