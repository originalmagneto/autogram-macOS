import XCTest
import CoreGraphics
@testable import AutogramKit

final class QRCodeRendererTests: XCTestCase {
    func testRendersSquareImageOfRequestedSide() throws {
        let image = try XCTUnwrap(QRCodeRenderer.image(
            for: "https://autogram.slovensko.digital/api/v1/qr-code?guid=abc&key=xyz", side: 320))
        XCTAssertEqual(image.width, 320)
        XCTAssertEqual(image.height, 320)
    }

    func testEmptyStringProducesNoImage() {
        XCTAssertNil(QRCodeRenderer.image(for: "", side: 100))
    }
}
