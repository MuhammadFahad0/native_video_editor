import Foundation

struct VideoEditRequest {
  let inputPath: String
  let outputPath: String
  let trimStartMs: Int64?
  let trimEndMs: Int64?
  let cropRect: VideoCropRect?
  let targetWidth: Int?
  let targetHeight: Int?
  let rotationDegrees: Int
  let muteAudio: Bool

  init(_ map: [String: Any]) throws {
    guard let inputPath = map["inputPath"] as? String, !inputPath.trimmingCharacters(in: .whitespaces).isEmpty else {
      throw VideoEditRequestError.invalid("inputPath is required.")
    }
    guard let outputPath = map["outputPath"] as? String, !outputPath.trimmingCharacters(in: .whitespaces).isEmpty else {
      throw VideoEditRequestError.invalid("outputPath is required.")
    }
    if URL(fileURLWithPath: inputPath).standardizedFileURL == URL(fileURLWithPath: outputPath).standardizedFileURL {
      throw VideoEditRequestError.invalid("inputPath and outputPath must be different files.")
    }

    let trimStartMs = (map["trimStartMs"] as? NSNumber)?.int64Value
    let trimEndMs = (map["trimEndMs"] as? NSNumber)?.int64Value
    let targetWidth = (map["targetWidth"] as? NSNumber)?.intValue
    let targetHeight = (map["targetHeight"] as? NSNumber)?.intValue
    let rotationDegrees = (map["rotationDegrees"] as? NSNumber)?.intValue ?? 0

    if let trimStartMs = trimStartMs, trimStartMs < 0 {
      throw VideoEditRequestError.invalid("trimStartMs must not be negative.")
    }
    if let trimEndMs = trimEndMs, trimEndMs < 0 {
      throw VideoEditRequestError.invalid("trimEndMs must not be negative.")
    }
    if let trimStartMs = trimStartMs, let trimEndMs = trimEndMs, trimStartMs >= trimEndMs {
      throw VideoEditRequestError.invalid("trimStartMs must be earlier than trimEndMs.")
    }
    if (targetWidth == nil) != (targetHeight == nil) {
      throw VideoEditRequestError.invalid("targetWidth and targetHeight must be provided together.")
    }
    if let targetWidth = targetWidth, targetWidth <= 0 || targetWidth % 2 != 0 {
      throw VideoEditRequestError.invalid("targetWidth must be a positive even number.")
    }
    if let targetHeight = targetHeight, targetHeight <= 0 || targetHeight % 2 != 0 {
      throw VideoEditRequestError.invalid("targetHeight must be a positive even number.")
    }
    if ![0, 90, 180, 270].contains(rotationDegrees) {
      throw VideoEditRequestError.invalid("rotationDegrees must be one of 0, 90, 180, or 270.")
    }

    self.inputPath = inputPath
    self.outputPath = outputPath
    self.trimStartMs = trimStartMs
    self.trimEndMs = trimEndMs
    self.cropRect = try (map["cropRect"] as? [String: Any]).map(VideoCropRect.init)
    self.targetWidth = targetWidth
    self.targetHeight = targetHeight
    self.rotationDegrees = rotationDegrees
    self.muteAudio = (map["muteAudio"] as? Bool) ?? false
  }
}

struct VideoCropRect {
  let left: CGFloat
  let top: CGFloat
  let width: CGFloat
  let height: CGFloat

  init(_ map: [String: Any]) throws {
    guard let left = map["left"] as? NSNumber,
      let top = map["top"] as? NSNumber,
      let width = map["width"] as? NSNumber,
      let height = map["height"] as? NSNumber else {
      throw VideoEditRequestError.invalid("cropRect requires left, top, width, and height.")
    }

    self.left = CGFloat(truncating: left)
    self.top = CGFloat(truncating: top)
    self.width = CGFloat(truncating: width)
    self.height = CGFloat(truncating: height)

    if !self.left.isFinite || !self.top.isFinite || !self.width.isFinite || !self.height.isFinite {
      throw VideoEditRequestError.invalid("cropRect values must be finite.")
    }
    if self.left < 0 || self.top < 0 || self.width <= 0 || self.height <= 0 {
      throw VideoEditRequestError.invalid("cropRect must use positive normalized values.")
    }
    if self.left + self.width > 1 || self.top + self.height > 1 {
      throw VideoEditRequestError.invalid("cropRect must stay inside the normalized frame.")
    }
  }
}

enum VideoEditRequestError: LocalizedError {
  case invalid(String)

  var errorDescription: String? {
    switch self {
    case .invalid(let message):
      return message
    }
  }
}
