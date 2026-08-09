import AVFoundation
import Flutter

/// Merges an audio track into an existing video file using AVFoundation.
///
/// Strategy:
///  1. Load the source video with AVURLAsset and compose its video track into
///     an AVMutableComposition.
///  2. If replaceExistingAudio == true, skip the video's audio track entirely.
///  3. Load the new audio with AVURLAsset and insert its audio track into the
///     composition, clipped to min(videoDuration, audioDuration).
///  4. Export with AVAssetExportSession (.mp4) – same pattern as VideoAVPipeline.
///  5. Progress is reported every 250ms via the Flutter method channel.
final class AudioMergerPipeline {
  private let channel: FlutterMethodChannel
  private var exportSession: AVAssetExportSession?
  private var timer: Timer?
  private var isRunning = false
  private let lock = NSLock()

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  // MARK: – Public

  func merge(
    _ request: AudioMergeRequest,
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
    isRunning = false
    timer?.invalidate()
    timer = nil
    exportSession?.cancelExport()
    exportSession = nil
    lock.unlock()
  }

  // MARK: – Implementation

  private func run(
    _ request: AudioMergeRequest,
    completion: @escaping (Result<String, Error>) -> Void
  ) throws {
    let videoAsset = AVURLAsset(url: URL(fileURLWithPath: request.inputVideoPath))
    let audioAsset = AVURLAsset(url: URL(fileURLWithPath: request.audioPath))

    guard let sourceVideoTrack = videoAsset.tracks(withMediaType: .video).first else {
      throw AudioMergerError.missingVideoTrack
    }

    let videoDuration = videoAsset.duration
    guard videoDuration.isNumeric && videoDuration > .zero else {
      throw AudioMergerError.invalidVideoDuration
    }

    // Use the shorter of video duration and audio duration.
    let audioDuration = audioAsset.duration
    let compositionDuration = (audioDuration.isNumeric && audioDuration < videoDuration)
      ? audioDuration
      : videoDuration

    // ── Build composition ──────────────────────────────────────────────────
    let composition = AVMutableComposition()
    let compVideoRange = CMTimeRange(start: .zero, duration: compositionDuration)

    // Video track.
    guard let compVideoTrack = composition.addMutableTrack(
      withMediaType: .video,
      preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
      throw AudioMergerError.unableToCreateTrack
    }
    try compVideoTrack.insertTimeRange(
      CMTimeRange(start: .zero, duration: compositionDuration),
      of: sourceVideoTrack,
      at: .zero
    )

    // Carry over the preferred transform so the video stays correctly oriented.
    compVideoTrack.preferredTransform = sourceVideoTrack.preferredTransform

    // Existing audio track (only if we are not replacing).
    if !request.replaceExistingAudio,
       let sourceAudioTrack = videoAsset.tracks(withMediaType: .audio).first,
       let compExistingAudio = composition.addMutableTrack(
         withMediaType: .audio,
         preferredTrackID: kCMPersistentTrackID_Invalid
       ) {
      try? compExistingAudio.insertTimeRange(compVideoRange, of: sourceAudioTrack, at: .zero)
    }

    // New audio track.
    if let newAudioTrack = audioAsset.tracks(withMediaType: .audio).first,
       let compNewAudio = composition.addMutableTrack(
         withMediaType: .audio,
         preferredTrackID: kCMPersistentTrackID_Invalid
       ) {
      let insertRange = CMTimeRange(start: .zero, duration: compositionDuration)
      try compNewAudio.insertTimeRange(insertRange, of: newAudioTrack, at: .zero)
    } else {
      throw AudioMergerError.missingAudioTrack
    }

    // ── Prepare output ─────────────────────────────────────────────────────
    let outputURL = URL(fileURLWithPath: request.outputPath)
    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }

    // ── AVAssetExportSession ───────────────────────────────────────────────
    guard let session = AVAssetExportSession(
      asset: composition,
      presetName: AVAssetExportPresetHighestQuality
    ) else {
      throw AudioMergerError.unableToCreateExportSession
    }

    lock.lock()
    self.exportSession = session
    self.isRunning = true
    lock.unlock()

    session.outputURL = outputURL
    session.outputFileType = .mp4
    session.shouldOptimizeForNetworkUse = true

    // Progress timer.
    let outputPath = request.outputPath
    let channelRef = channel
    DispatchQueue.main.async { [weak self, weak session] in
      guard let self = self else { return }
      self.timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self, weak session] timer in
        guard let self = self, let session = session else { timer.invalidate(); return }
        self.lock.lock()
        let running = self.isRunning
        self.lock.unlock()
        if !running { timer.invalidate(); return }

        channelRef.invokeMethod("onProgress", arguments: [
          "outputPath": outputPath,
          "progress": Double(session.progress)
        ])

        if session.status == .completed || session.status == .failed || session.status == .cancelled {
          timer.invalidate()
        }
      }
    }

    session.exportAsynchronously { [weak self] in
      guard let self = self else { return }
      self.lock.lock()
      self.isRunning = false
      self.timer?.invalidate()
      self.timer = nil
      self.exportSession = nil
      self.lock.unlock()

      DispatchQueue.main.async {
        switch session.status {
        case .completed:
          completion(.success(request.outputPath))
        case .failed, .cancelled:
          completion(.failure(session.error ?? AudioMergerError.exportFailed))
        default:
          completion(.failure(AudioMergerError.exportFailed))
        }
      }
    }
  }
}

// MARK: – Errors

enum AudioMergerError: LocalizedError {
  case missingVideoTrack
  case missingAudioTrack
  case invalidVideoDuration
  case unableToCreateTrack
  case unableToCreateExportSession
  case exportFailed

  var errorDescription: String? {
    switch self {
    case .missingVideoTrack: return "The input video does not contain a video track."
    case .missingAudioTrack: return "The audio file does not contain an audio track."
    case .invalidVideoDuration: return "Unable to determine the input video duration."
    case .unableToCreateTrack: return "Unable to create a composition track."
    case .unableToCreateExportSession: return "Unable to create an AVAssetExportSession."
    case .exportFailed: return "The export session failed."
    }
  }
}
