import XCTest
@testable import AutogramApp

/// A dropped document must keep its own location and name. When the drop carries
/// a file URL, the signed output belongs next to the original, not in a temporary
/// directory under a generated name.
final class DroppedFileURLTests: XCTestCase {
    private let file = URL(fileURLWithPath: "/Users/tester/Documents/zmluva.pdf")

    func testResolvesAURL() {
        XCTAssertEqual(DroppedFileURL.resolve(from: file), file)
    }

    func testResolvesAnNSURL() {
        XCTAssertEqual(DroppedFileURL.resolve(from: file as NSURL), file)
    }

    /// Finder hands the URL over as its data representation.
    func testResolvesADataRepresentation() {
        XCTAssertEqual(DroppedFileURL.resolve(from: file.dataRepresentation), file)
    }

    func testRejectsANonFileURL() {
        let remote = URL(string: "https://example.org/zmluva.pdf")!
        XCTAssertNil(DroppedFileURL.resolve(from: remote))
    }

    func testRejectsGarbage() {
        XCTAssertNil(DroppedFileURL.resolve(from: nil))
        XCTAssertNil(DroppedFileURL.resolve(from: Data([0xFF, 0xFE])))
        XCTAssertNil(DroppedFileURL.resolve(from: 42))
    }

    /// A drop that only carries bytes has no location to preserve.
    func testRejectsRawDocumentBytes() {
        XCTAssertNil(DroppedFileURL.resolve(from: Data("%PDF-1.7".utf8)))
    }
}
