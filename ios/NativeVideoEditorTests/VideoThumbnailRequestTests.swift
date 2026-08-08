import XCTest
@testable import native_video_editor

final class VideoThumbnailRequestTests: XCTestCase {

    private var validBase: [String: Any] {
        ["inputPath": "/tmp/input.mp4", "outputPath": "/tmp/thumb.jpg"]
    }

    // MARK: - Happy path

    func testInitSucceedsWithAllFields() throws {
        var map = validBase
        map["positionMs"] = NSNumber(value: 2000)
        map["quality"] = NSNumber(value: 80)
        let req = try VideoThumbnailRequest(map)
        XCTAssertEqual(req.inputPath, "/tmp/input.mp4")
        XCTAssertEqual(req.outputPath, "/tmp/thumb.jpg")
        XCTAssertEqual(req.positionMs, 2000)
        XCTAssertEqual(req.quality, 80)
    }

    func testInitUsesDefaultPosition() throws {
        let req = try VideoThumbnailRequest(validBase)
        XCTAssertEqual(req.positionMs, 0)
    }

    func testInitUsesDefaultQuality() throws {
        let req = try VideoThumbnailRequest(validBase)
        XCTAssertEqual(req.quality, 90)
    }

    // MARK: - Path validation

    func testInitThrowsOnMissingInputPath() {
        XCTAssertThrowsError(try VideoThumbnailRequest(["outputPath": "/tmp/thumb.jpg"]))
    }

    func testInitThrowsOnBlankInputPath() {
        XCTAssertThrowsError(try VideoThumbnailRequest(["inputPath": "   ", "outputPath": "/tmp/thumb.jpg"]))
    }

    func testInitThrowsOnSamePath() {
        XCTAssertThrowsError(try VideoThumbnailRequest(["inputPath": "/tmp/thumb.jpg", "outputPath": "/tmp/thumb.jpg"]))
    }

    // MARK: - Position validation

    func testInitThrowsOnNegativePosition() {
        var map = validBase
        map["positionMs"] = NSNumber(value: -1)
        XCTAssertThrowsError(try VideoThumbnailRequest(map))
    }

    // MARK: - Quality validation

    func testInitThrowsOnQuality0() {
        var map = validBase
        map["quality"] = NSNumber(value: 0)
        XCTAssertThrowsError(try VideoThumbnailRequest(map))
    }

    func testInitThrowsOnQuality101() {
        var map = validBase
        map["quality"] = NSNumber(value: 101)
        XCTAssertThrowsError(try VideoThumbnailRequest(map))
    }

    func testInitAcceptsQualityBoundaries() throws {
        var mapLow = validBase
        mapLow["quality"] = NSNumber(value: 1)
        let reqLow = try VideoThumbnailRequest(mapLow)
        XCTAssertEqual(reqLow.quality, 1)

        var mapHigh = validBase
        mapHigh["quality"] = NSNumber(value: 100)
        let reqHigh = try VideoThumbnailRequest(mapHigh)
        XCTAssertEqual(reqHigh.quality, 100)
    }
}
