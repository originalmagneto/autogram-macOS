import XCTest
import CoreGraphics
import Vision
@testable import AutogramKit

final class QRCodeRendererTests: XCTestCase {
    private let payload = "https://autogram.slovensko.digital/api/v1/qr-code?guid=efb2e9f9-7c5e-4681-bea2-831a7f6269f4&key=YmoAmPmJBpUinGKx2mcSHtR17bOOcrUd98RvYmlaNc8%3D"

    func testRendersSquareImageOfRequestedSide() throws {
        let image = try XCTUnwrap(QRCodeRenderer.image(for: payload, side: 320))
        XCTAssertEqual(image.width, 320)
        XCTAssertEqual(image.height, 320)
    }

    func testEmptyStringProducesNoImage() {
        XCTAssertNil(QRCodeRenderer.image(for: "", side: 100))
    }

    func testRenderedCodeDecodesBackToPayload() throws {
        // A cropped code (missing finder pattern or quiet zone) fails to decode.
        for side in [200, 260, 512] {
            let image = try XCTUnwrap(QRCodeRenderer.image(for: payload, side: side))
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]
            try VNImageRequestHandler(cgImage: image).perform([request])
            let decoded = request.results?.first?.payloadStringValue
            XCTAssertEqual(decoded, payload, "side \(side)")
        }
    }

    func testCornersAreWhiteQuietZone() throws {
        let image = try XCTUnwrap(QRCodeRenderer.image(for: payload, side: 300))
        let data = try XCTUnwrap(image.dataProvider?.data) as Data
        let bytesPerRow = image.bytesPerRow
        let bpp = image.bitsPerPixel / 8
        func isWhite(x: Int, y: Int) -> Bool {
            let base = y * bytesPerRow + x * bpp
            return data[base] > 200 && data[base + 1] > 200 && data[base + 2] > 200
        }
        XCTAssertTrue(isWhite(x: 1, y: 1))
        XCTAssertTrue(isWhite(x: 298, y: 1))
        XCTAssertTrue(isWhite(x: 1, y: 298))
        XCTAssertTrue(isWhite(x: 298, y: 298))
    }
}
