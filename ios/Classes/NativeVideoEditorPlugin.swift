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

/// A simple type-erasure so we can store different pipeline types in the same
/// dictionary and call cancel() on any of them uniformly.
private protocol Cancellable: AnyObject {
  func cancel()
}
extension VideoAVPipeline: Cancellable {}
extension ImageComposerPipeline: Cancellable {}
extension AudioMergerPipeline: Cancellable {}
extension CompositionAVPipeline: Cancellable {}

public class NativeVideoEditorPlugin: NSObject, FlutterPlugin {
  private var channel: FlutterMethodChannel?
  private var activePipelines = [String: Cancellable]()
  private let lock = NSLock()

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if canImport(FlutterMacOS)
    let messenger = registrar.messenger
    #else
    let messenger = registrar.messenger()
    #endif
    let channel = FlutterMethodChannel(
      name: "native_video_editor",
      binaryMessenger: messenger
    )
    let instance = NativeVideoEditorPlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getMediaInfo":
      guard let args = call.arguments as? [String: Any], let path = args["inputPath"] as? String else {
        result(FlutterError(code: "invalid_arguments", message: "inputPath is required.", details: nil)); return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let info = try CompositionAVPipeline.mediaInfo(path)
          DispatchQueue.main.async { result(info) }
        } catch { DispatchQueue.main.async { result(FlutterError(code: "metadata_failed", message: error.localizedDescription, details: nil)) } }
      }
    case "composeVideo":
      guard let args = call.arguments as? [String: Any], let path = args["outputPath"] as? String,
        let channel = channel else {
        result(FlutterError(code: "invalid_arguments", message: "Invalid composition request.", details: nil)); return
      }
      lock.lock()
      if activePipelines[path] != nil {
        lock.unlock(); result(FlutterError(code: "output_in_use", message: "Output already has an active export.", details: nil)); return
      }
      let pipeline = CompositionAVPipeline(channel: channel)
      activePipelines[path] = pipeline; lock.unlock()
      pipeline.compose(args) { outcome in
        self.lock.lock(); self.activePipelines.removeValue(forKey: path); self.lock.unlock()
        DispatchQueue.main.async {
          switch outcome {
          case .success(let path): result(path)
          case .failure(let error): result(FlutterError(code: "composition_failed", message: error.localizedDescription, details: nil))
          }
        }
      }
    case "processVideo":
      processVideo(call, result: result)
    case "cancelProcessVideo":
      cancelProcessVideo(call, result: result)
    case "extractThumbnail":
      extractThumbnail(call, result: result)
    case "composeImageWithAudio":
      composeImageWithAudio(call, result: result)
    case "mergeAudioIntoVideo":
      mergeAudioIntoVideo(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: – processVideo

  private func processVideo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_arguments", message: "Expected a request map.", details: nil))
      return
    }

    let request: VideoEditRequest
    do {
      request = try VideoEditRequest(arguments)
    } catch {
      result(FlutterError(code: "invalid_arguments", message: error.localizedDescription, details: nil))
      return
    }

    guard let channel = self.channel else {
      result(FlutterError(code: "internal_error", message: "Method channel not registered.", details: nil))
      return
    }

    let pipeline = VideoAVPipeline(channel: channel)
    lock.lock()
    activePipelines[request.outputPath] = pipeline
    lock.unlock()

    pipeline.process(request) { [weak self] pipelineResult in
      guard let self = self else { return }
      self.lock.lock()
      _ = self.activePipelines.removeValue(forKey: request.outputPath)
      self.lock.unlock()

      DispatchQueue.main.async {
        switch pipelineResult {
        case .success(let outputPath):
          result(outputPath)
        case .failure(let error):
          result(FlutterError(
            code: "processing_failed",
            message: error.localizedDescription,
            details: String(describing: error)
          ))
        }
      }
    }
  }

  // MARK: – cancelProcessVideo

  private func cancelProcessVideo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
          let outputPath = arguments["outputPath"] as? String else {
      result(FlutterError(code: "invalid_arguments", message: "Expected outputPath.", details: nil))
      return
    }

    lock.lock()
    let pipeline = activePipelines.removeValue(forKey: outputPath)
    lock.unlock()

    pipeline?.cancel()
    result(nil)
  }

  // MARK: – extractThumbnail

  private func extractThumbnail(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_arguments", message: "Expected a request map.", details: nil))
      return
    }

    let request: VideoThumbnailRequest
    do {
      request = try VideoThumbnailRequest(arguments)
    } catch {
      result(FlutterError(code: "invalid_arguments", message: error.localizedDescription, details: nil))
      return
    }

    guard let channel = self.channel else {
      result(FlutterError(code: "internal_error", message: "Method channel not registered.", details: nil))
      return
    }

    VideoAVPipeline(channel: channel).extractThumbnail(request) { pipelineResult in
      DispatchQueue.main.async {
        switch pipelineResult {
        case .success(let outputPath):
          result(outputPath)
        case .failure(let error):
          result(FlutterError(
            code: "thumbnail_failed",
            message: error.localizedDescription,
            details: String(describing: error)
          ))
        }
      }
    }
  }

  // MARK: – composeImageWithAudio

  private func composeImageWithAudio(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_arguments", message: "Expected a request map.", details: nil))
      return
    }

    let request: ImageComposeRequest
    do {
      request = try ImageComposeRequest(arguments)
    } catch {
      result(FlutterError(code: "invalid_arguments", message: error.localizedDescription, details: nil))
      return
    }

    guard let channel = self.channel else {
      result(FlutterError(code: "internal_error", message: "Method channel not registered.", details: nil))
      return
    }

    let pipeline = ImageComposerPipeline(channel: channel)
    lock.lock()
    activePipelines[request.outputPath] = pipeline
    lock.unlock()

    pipeline.compose(request) { [weak self] pipelineResult in
      guard let self = self else { return }
      self.lock.lock()
      _ = self.activePipelines.removeValue(forKey: request.outputPath)
      self.lock.unlock()

      DispatchQueue.main.async {
        switch pipelineResult {
        case .success(let outputPath):
          result(outputPath)
        case .failure(let error):
          result(FlutterError(
            code: "compose_failed",
            message: error.localizedDescription,
            details: String(describing: error)
          ))
        }
      }
    }
  }

  // MARK: – mergeAudioIntoVideo

  private func mergeAudioIntoVideo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_arguments", message: "Expected a request map.", details: nil))
      return
    }

    let request: AudioMergeRequest
    do {
      request = try AudioMergeRequest(arguments)
    } catch {
      result(FlutterError(code: "invalid_arguments", message: error.localizedDescription, details: nil))
      return
    }

    guard let channel = self.channel else {
      result(FlutterError(code: "internal_error", message: "Method channel not registered.", details: nil))
      return
    }

    let pipeline = AudioMergerPipeline(channel: channel)
    lock.lock()
    activePipelines[request.outputPath] = pipeline
    lock.unlock()

    pipeline.merge(request) { [weak self] pipelineResult in
      guard let self = self else { return }
      self.lock.lock()
      _ = self.activePipelines.removeValue(forKey: request.outputPath)
      self.lock.unlock()

      DispatchQueue.main.async {
        switch pipelineResult {
        case .success(let outputPath):
          result(outputPath)
        case .failure(let error):
          result(FlutterError(
            code: "merge_failed",
            message: error.localizedDescription,
            details: String(describing: error)
          ))
        }
      }
    }
  }
}

