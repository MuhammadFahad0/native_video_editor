import XCTest
@testable import native_video_editor

final class VideoCropRectTests: XCTestCase {

    private var validMap: [String: Any] {
        ["left": 0.1, "top": 0.2, "width": 0.5, "height": 0.6]
    }

    // MARK: - Happy path

    func testInitSucceedsWithValidValues() throws {
        let rect = try VideoCropRect(validMap)
        XCTAssertEqual(Double(rect.left), 0.1, accuracy: 0.001)
        XCTAssertEqual(Double(rect.top), 0.2, accuracy: 0.001)
        XCTAssertEqual(Double(rect.width), 0.5, accuracy: 0.001)
        XCTAssertEqual(Double(rect.height), 0.6, accuracy: 0.001)
    }

    func testInitAcceptsExact1Boundary() throws {
        let rect = try VideoCropRect(["left": 0.0, "top": 0.0, "width": 1.0, "height": 1.0])
        XCTAssertEqual(Double(rect.width), 1.0, accuracy: 0.001)
        XCTAssertEqual(Double(rect.height), 1.0, accuracy: 0.001)
    }

    // MARK: - Missing key validation

    func testInitThrowsOnMissingLeftKey() {
        XCTAssertThrowsError(try VideoCropRect(["top": 0.2, "width": 0.5, "height": 0.6]))
    }

    func testInitThrowsOnMissingTopKey() {
        XCTAssertThrowsError(try VideoCropRect(["left": 0.1, "width": 0.5, "height": 0.6]))
    }

    func testInitThrowsOnMissingWidthKey() {
        XCTAssertThrowsError(try VideoCropRect(["left": 0.1, "top": 0.2, "height": 0.6]))
    }

    func testInitThrowsOnMissingHeightKey() {
        XCTAssertThrowsError(try VideoCropRect(["left": 0.1, "top": 0.2, "width": 0.5]))
    }

    // MARK: - Non-finite value validation

    func testInitThrowsOnNaNValue() {
        var map = validMap
        map["left"] = NSNumber(value: Double.nan)
        XCTAssertThrowsError(try VideoCropRect(map))
    }

    func testInitThrowsOnInfiniteValue() {
        var map = validMap
        map["top"] = NSNumber(value: Double.infinity)
        XCTAssertThrowsError(try VideoCropRect(map))
    }

    // MARK: - Range validation

    func testInitThrowsOnNegativeLeft() {
        var map = validMap
        map["left"] = -0.1
        XCTAssertThrowsError(try VideoCropRect(map))
    }

    func testInitThrowsOnZeroWidth() {
        var map = validMap
        map["width"] = 0.0
        XCTAssertThrowsError(try VideoCropRect(map))
    }

    func testInitThrowsOnRightEdgeOverflow() {
        XCTAssertThrowsError(try VideoCropRect(["left": 0.6, "top": 0.0, "width": 0.5, "height": 0.5]))
    }

    func testInitThrowsOnBottomEdgeOverflow() {
        XCTAssertThrowsError(try VideoCropRect(["left": 0.0, "top": 0.6, "width": 0.5, "height": 0.5]))
    }
}
