import Flutter
import UIKit

public class NativeVideoEditorPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "native_video_editor",
      binaryMessenger: registrar.messenger()
    )
    let instance = NativeVideoEditorPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "processVideo":
      processVideo(call, result: result)
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

    VideoAVPipeline().process(request) { pipelineResult in
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
}
