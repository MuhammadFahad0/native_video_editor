import XCTest
@testable import native_video_editor

final class VideoEditRequestTests: XCTestCase {

    // MARK: - Helper

    private var validBase: [String: Any] {
        ["inputPath": "/tmp/input.mp4", "outputPath": "/tmp/output.mp4"]
    }

    // MARK: - Happy path

    func testInitSucceedsWithAllFields() throws {
        var map = validBase
        map["trimStartMs"] = NSNumber(value: 1000)
        map["trimEndMs"] = NSNumber(value: 5000)
        map["targetWidth"] = NSNumber(value: 1280)
        map["targetHeight"] = NSNumber(value: 720)
        map["rotationDegrees"] = NSNumber(value: 90)
        map["speedMultiplier"] = NSNumber(value: 1.5)
        map["muteAudio"] = true
        let req = try VideoEditRequest(map)
        XCTAssertEqual(req.inputPath, "/tmp/input.mp4")
        XCTAssertEqual(req.outputPath, "/tmp/output.mp4")
        XCTAssertEqual(req.trimStartMs, 1000)
        XCTAssertEqual(req.trimEndMs, 5000)
        XCTAssertEqual(req.targetWidth, 1280)
        XCTAssertEqual(req.targetHeight, 720)
        XCTAssertEqual(req.rotationDegrees, 90)
        XCTAssertEqual(req.speedMultiplier, 1.5, accuracy: 0.001)
        XCTAssertTrue(req.muteAudio)
    }

    func testInitSucceedsWithMinimalFields() throws {
        let req = try VideoEditRequest(validBase)
        XCTAssertNil(req.trimStartMs)
        XCTAssertNil(req.trimEndMs)
        XCTAssertNil(req.cropRect)
        XCTAssertNil(req.targetWidth)
        XCTAssertNil(req.targetHeight)
        XCTAssertEqual(req.rotationDegrees, 0)
        XCTAssertEqual(req.speedMultiplier, 1.0, accuracy: 0.001)
        XCTAssertFalse(req.muteAudio)
    }

    // MARK: - Path validation

    func testInitThrowsOnMissingInputPath() {
        XCTAssertThrowsError(try VideoEditRequest(["outputPath": "/tmp/output.mp4"]))
    }

    func testInitThrowsOnBlankInputPath() {
        XCTAssertThrowsError(try VideoEditRequest(["inputPath": "   ", "outputPath": "/tmp/output.mp4"]))
    }

    func testInitThrowsOnMissingOutputPath() {
        XCTAssertThrowsError(try VideoEditRequest(["inputPath": "/tmp/input.mp4"]))
    }

    func testInitThrowsOnSamePath() {
        XCTAssertThrowsError(try VideoEditRequest(["inputPath": "/tmp/video.mp4", "outputPath": "/tmp/video.mp4"]))
    }

    // MARK: - Trim validation

    func testInitThrowsOnNegativeTrimStart() {
        var map = validBase
        map["trimStartMs"] = NSNumber(value: -1)
        XCTAssertThrowsError(try VideoEditRequest(map))
    }

    func testInitThrowsOnNegativeTrimEnd() {
        var map = validBase
        map["trimEndMs"] = NSNumber(value: -1)
        XCTAssertThrowsError(try VideoEditRequest(map))
    }

    func testInitThrowsOnTrimStartEqualTrimEnd() {
        var map = validBase
        map["trimStartMs"] = NSNumber(value: 3000)
        map["trimEndMs"] = NSNumber(value: 3000)
        XCTAssertThrowsError(try VideoEditRequest(map))
    }

    func testInitThrowsOnTrimStartGreaterThanTrimEnd() {
        var map = validBase
        map["trimStartMs"] = NSNumber(value: 5000)
        map["trimEndMs"] = NSNumber(value: 1000)
        XCTAssertThrowsError(try VideoEditRequest(map))
    }

    // MARK: - Dimension validation

    func testInitThrowsOnOnlyTargetWidth() {
        var map = validBase
        map["targetWidth"] = NSNumber(value: 1280)
        XCTAssertThrowsError(try VideoEditRequest(map))
    }

    func testInitThrowsOnOnlyTargetHeight() {
        var map = validBase
        map["targetHeight"] = NSNumber(value: 720)
        XCTAssertThrowsError(try VideoEditRequest(map))
    }

    func testInitThrowsOnOddTargetWidth() {
        var map = validBase
        map["targetWidth"] = NSNumber(value: 721)
        map["targetHeight"] = NSNumber(value: 720)
        XCTAssertThrowsError(try VideoEditRequest(map))
    }

    func testInitThrowsOnOddTargetHeight() {
        var map = validBase
        map["targetWidth"] = NSNumber(value: 1280)
        map["targetHeight"] = NSNumber(value: 721)
        XCTAssertThrowsError(try VideoEditRequest(map))
    }

    // MARK: - Rotation validation

    func testInitThrowsOnInvalidRotation() {
        var map = validBase
        map["rotationDegrees"] = NSNumber(value: 45)
        XCTAssertThrowsError(try VideoEditRequest(map))
    }

    func testInitAcceptsAllValidRotations() throws {
        for deg in [0, 90, 180, 270] {
            var map = validBase
            map["rotationDegrees"] = NSNumber(value: deg)
            let req = try VideoEditRequest(map)
            XCTAssertEqual(req.rotationDegrees, deg)
        }
    }

    // MARK: - Speed validation

    func testInitThrowsOnSpeedBelowMin() {
        var map = validBase
        map["speedMultiplier"] = NSNumber(value: 0.1)
        XCTAssertThrowsError(try VideoEditRequest(map))
    }

    func testInitThrowsOnSpeedAboveMax() {
        var map = validBase
        map["speedMultiplier"] = NSNumber(value: 4.1)
        XCTAssertThrowsError(try VideoEditRequest(map))
    }

    func testInitThrowsOnInfiniteSpeed() {
        var map = validBase
        map["speedMultiplier"] = NSNumber(value: Double.infinity)
        XCTAssertThrowsError(try VideoEditRequest(map))
    }

    func testInitAcceptsBoundarySpeed() throws {
        var mapLow = validBase
        mapLow["speedMultiplier"] = NSNumber(value: 0.25)
        let reqLow = try VideoEditRequest(mapLow)
        XCTAssertEqual(reqLow.speedMultiplier, 0.25, accuracy: 0.001)

        var mapHigh = validBase
        mapHigh["speedMultiplier"] = NSNumber(value: 4.0)
        let reqHigh = try VideoEditRequest(mapHigh)
        XCTAssertEqual(reqHigh.speedMultiplier, 4.0, accuracy: 0.001)
    }

    // MARK: - CropRect parsing

    func testInitParsesCropRect() throws {
        var map = validBase
        map["cropRect"] = ["left": 0.1, "top": 0.2, "width": 0.5, "height": 0.6]
        let req = try VideoEditRequest(map)
        XCTAssertNotNil(req.cropRect)
        XCTAssertEqual(Double(req.cropRect!.left), 0.1, accuracy: 0.001)
    }

    func testMuteAudioDefaultsFalse() throws {
        let req = try VideoEditRequest(validBase)
        XCTAssertFalse(req.muteAudio)
    }
}
