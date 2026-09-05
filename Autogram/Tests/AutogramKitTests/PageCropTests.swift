import XCTest
import CoreGraphics
@testable import AutogramKit

final class PageCropTests: XCTestCase {
    func testPixelRectFlipsToTopOriginAndAddsMargin() {
        // Box in bottom-origin normalized space: x 0.5, y 0.0, w 0.5, h 0.5 (bottom-right quadrant).
        let rect = PageCrop.pixelRect(for: .init(x: 0.5, y: 0.0, width: 0.5, height: 0.5),
                                      imageWidth: 200, imageHeight: 100, margin: 0.0)
        XCTAssertEqual(rect, CGRect(x: 100, y: 50, width: 100, height: 50))

        let padded = PageCrop.pixelRect(for: .init(x: 0.5, y: 0.0, width: 0.5, height: 0.5),
                                        imageWidth: 200, imageHeight: 100, margin: 0.1)
        XCTAssertEqual(padded.minX, 90, accuracy: 0.5)   // 10% of 100px width
        XCTAssertEqual(padded.maxX, 200, accuracy: 0.5)  // clamped to image
        XCTAssertEqual(padded.minY, 45, accuracy: 0.5)   // 10% of 50px height
        XCTAssertEqual(padded.maxY, 100, accuracy: 0.5)
    }

    func testNormalizedRectFromPixelRectRoundTrips() {
        let original = NormalizedRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        let px = PageCrop.pixelRect(for: original, imageWidth: 400, imageHeight: 200, margin: 0)
        let back = PageCrop.normalizedRect(fromPixelRect: px, imageWidth: 400, imageHeight: 200)
        XCTAssertEqual(back.x, original.x, accuracy: 1e-9)
        XCTAssertEqual(back.y, original.y, accuracy: 1e-9)
        XCTAssertEqual(back.width, original.width, accuracy: 1e-9)
        XCTAssertEqual(back.height, original.height, accuracy: 1e-9)
    }

    func testCropReturnsImageOfExpectedSize() throws {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(ctx.makeImage())
        let crop = try XCTUnwrap(PageCrop.crop(image, to: .init(x: 0.5, y: 0.0, width: 0.5, height: 0.5), margin: 0))
        XCTAssertEqual(crop.width, 100)
        XCTAssertEqual(crop.height, 50)
    }
}
