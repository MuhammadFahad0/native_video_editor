import Flutter
import UIKit

public class NativeVideoEditorPlugin: NSObject, FlutterPlugin {
  private var channel: FlutterMethodChannel?
  private var activePipelines = [String: VideoAVPipeline]()
  private let lock = NSLock()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "native_video_editor",
      binaryMessenger: registrar.messenger()
    )
    let instance = NativeVideoEditorPlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "processVideo":
      processVideo(call, result: result)
    case "cancelProcessVideo":
      cancelProcessVideo(call, result: result)
    case "extractThumbnail":
      extractThumbnail(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

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
          result(
            FlutterError(
              code: "processing_failed",
              message: error.localizedDescription,
              details: String(describing: error)
            )
          )
        }
      }
    }
  }

  private func cancelProcessVideo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
          let outputPath = arguments["outputPath"] as? String else {
      result(FlutterError(code: "invalid_arguments", message: "Expected outputPath.", details: nil))
      return
    }

    lock.lock()
    let pipeline = activePipelines.removeValue(forKey: outputPath)
    lock.unlock()

    if let pipeline = pipeline {
      pipeline.cancel()
    }
    result(nil)
  }

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
          result(
            FlutterError(
              code: "thumbnail_failed",
              message: error.localizedDescription,
              details: String(describing: error)
            )
          )
        }
      }
    }
  }
}
