import XCTest
import PDFKit
@testable import AutogramKit

final class VisibleSignatureStamperTests: XCTestCase {
    func testStampAddsAnnotationAndChangesData() throws {
        let document = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let originalLength = document.dataRepresentation()?.count ?? 0

        let stamper = VisibleSignatureStamper()
        let stamp = VisibleSignatureStamper.StampData(
            fullName: "JUDr. Test Testovací",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            pageIndex: 0,
            normalizedRect: NormalizedRect(x: 0.55, y: 0.78, width: 0.32, height: 0.10))

        let stamped = try XCTUnwrap(stamper.stamp(document: document,
                                                  stamp: stamp,
                                                  includeTimestamp: true))
        let stampedDoc = try XCTUnwrap(PDFDocument(data: stamped))
        XCTAssertEqual(stampedDoc.pageCount, 3)
        XCTAssertGreaterThan(stamped.count, originalLength)

        let page = try XCTUnwrap(stampedDoc.page(at: 0))
        XCTAssertEqual(page.annotations.filter { $0.type == "FreeText" }.count, 1,
                       "Na strane musí byť práve jeden FreeText podpisový blok.")

        let annotation = page.annotations.first { $0.type == "FreeText" }
        XCTAssertTrue(annotation?.contents?.contains("JUDr. Test Testovací") == true)
        XCTAssertTrue(annotation?.contents?.contains("Elektronicky podpísané") == true)
    }

    func testStampWithoutTimestampOmitsDate() throws {
        let document = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let stamper = VisibleSignatureStamper()
        let stamp = VisibleSignatureStamper.StampData(
            fullName: "Test Osoba",
            timestamp: Date(),
            pageIndex: 1,
            normalizedRect: .zero)

        let stamped = try XCTUnwrap(stamper.stamp(document: document,
                                                  stamp: stamp,
                                                  includeTimestamp: false))
        let doc = try XCTUnwrap(PDFDocument(data: stamped))
        let annotation = doc.page(at: 1)?.annotations.first { $0.type == "FreeText" }
        XCTAssertFalse(annotation?.contents?.contains("Elektronicky podpísané\nTest Osoba\n") == true &&
                       (annotation?.contents?.components(separatedBy: "\n").count ?? 0) > 2)
        XCTAssertEqual(annotation?.contents?.components(separatedBy: "\n").count, 2)
    }
}
