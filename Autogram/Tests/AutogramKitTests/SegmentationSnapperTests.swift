import XCTest
@testable import AutogramKit

final class SegmentationSnapperTests: XCTestCase {
    func testBoundingRectOfMaskFlipsToBottomOriginAndPads() {
        // 10x10 mask, filled rows 6..7 (top-origin), cols 2..3.
        var mask = [Bool](repeating: false, count: 100)
        for y in 6...7 { for x in 2...3 { mask[y * 10 + x] = true } }
        let rect = try! XCTUnwrap(SegmentationSnapper.boundingRect(ofMask: mask, width: 10, height: 10, padding: 0))
        XCTAssertEqual(rect.x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(rect.width, 0.2, accuracy: 1e-9)
        // rows 6..7 from the top means bottom-origin y from 0.2 to 0.4
        XCTAssertEqual(rect.y, 0.2, accuracy: 1e-9)
        XCTAssertEqual(rect.height, 0.2, accuracy: 1e-9)

        let padded = try! XCTUnwrap(SegmentationSnapper.boundingRect(ofMask: mask, width: 10, height: 10, padding: 0.5))
        XCTAssertEqual(padded.x, 0.1, accuracy: 1e-9)
        XCTAssertEqual(padded.width, 0.4, accuracy: 1e-9)
    }

    func testEmptyMaskYieldsNil() {
        XCTAssertNil(SegmentationSnapper.boundingRect(ofMask: [Bool](repeating: false, count: 4), width: 2, height: 2))
    }

    func testPaddingIsClampedToImage() {
        var mask = [Bool](repeating: false, count: 4)
        mask[0] = true // top-left pixel
        let rect = try! XCTUnwrap(SegmentationSnapper.boundingRect(ofMask: mask, width: 2, height: 2, padding: 2))
        XCTAssertEqual(rect.x, 0, accuracy: 1e-9)
        XCTAssertEqual(rect.y + rect.height, 1, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(rect.x + rect.width, 1)
        XCTAssertGreaterThanOrEqual(rect.y, 0)
    }
}
