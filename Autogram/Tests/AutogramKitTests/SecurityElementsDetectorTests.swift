import XCTest
import PDFKit
@testable import AutogramKit

final class SecurityElementsDetectorTests: XCTestCase {
    func testDetectsStampAndSignatureOnContractScan() throws {
        let document = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let analysis = PDFAnalysisEngine().analyze(document: document)
        let provider = BuiltInVisionProvider()

        let doc = TestUncheckedSendable(document)
        let elements = awaitAsync { await provider.detect(in: doc.value, pageAnalyses: analysis.pageAnalyses) }

        let stamps = elements.filter { $0.kind == .officialStamp && $0.pageIndex == 0 }
        XCTAssertGreaterThanOrEqual(stamps.count, 1,
                                    "Okrúhla pečiatka na strane 1 nebola detegovaná. Našlo sa: \(elements.map { "\($0.kind)@\($0.pageIndex)" })")

        if let stamp = stamps.first {
            XCTAssertEqual(stamp.boundingBox.midX > 0.5, true, "Pečiatka je v pravej časti strany")
            XCTAssertEqual(stamp.boundingBox.midY < 0.35, true, "Pečiatka je v dolnej časti strany")
        }

        let signatures = elements.filter { $0.kind == .handwrittenSignature && $0.pageIndex == 0 }
        XCTAssertGreaterThanOrEqual(signatures.count, 1,
                                    "Vlastnoručný podpis nebol detegovaný.")
    }

    func testRotatedPageKeepsDisplayedOrientationForAnalysisAndVision() throws {
        let document = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let page = try XCTUnwrap(document.page(at: 0))
        page.rotation = 90

        let analysis = PDFAnalysisEngine().analyze(document: document)
        XCTAssertEqual(analysis.pageAnalyses[0].sizeClass, .a4Landscape)
        XCTAssertEqual(analysis.pageAnalyses[0].widthPt, 842, accuracy: 0.1)
        XCTAssertEqual(analysis.pageAnalyses[0].heightPt, 595, accuracy: 0.1)

        let rendered = try XCTUnwrap(BuiltInVisionProvider.render(page: page, targetWidth: 520))
        XCTAssertGreaterThan(rendered.cgImage.width, rendered.cgImage.height)

        let provider = BuiltInVisionProvider()
        let doc = TestUncheckedSendable(document)
        let elements = awaitAsync { await provider.detect(in: doc.value, pageAnalyses: analysis.pageAnalyses) }
        XCTAssertTrue(elements.contains { $0.pageIndex == 0 && $0.kind == .officialStamp })
    }

    func testNoElementsOnBlankPage() throws {
        let document = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.singlePageWhitePDF()))
        let analysis = PDFAnalysisEngine().analyze(document: document)
        let provider = BuiltInVisionProvider()

        let doc = TestUncheckedSendable(document)
        let elements = awaitAsync { await provider.detect(in: doc.value, pageAnalyses: analysis.pageAnalyses) }

        XCTAssertTrue(elements.isEmpty)
    }

    func testMergerDoesNotDuplicateOverlappingElements() {
        let primary = SecurityElement(kind: .officialStamp, pageIndex: 0,
                                      boundingBox: NormalizedRect(x: 0.6, y: 0.1, width: 0.2, height: 0.2),
                                      confidence: 0.9)
        let duplicate = SecurityElement(kind: .officialStamp, pageIndex: 0,
                                        boundingBox: NormalizedRect(x: 0.62, y: 0.12, width: 0.2, height: 0.2),
                                        confidence: 0.7)
        let extra = SecurityElement(kind: .handwrittenSignature, pageIndex: 0,
                                    boundingBox: NormalizedRect(x: 0.1, y: 0.8, width: 0.3, height: 0.1),
                                    confidence: 0.6)

        let merged = SecurityElementMerger.merge(primary: [primary], secondary: [duplicate, extra])
        XCTAssertEqual(merged.count, 2)
    }

    func testLocationDescriptionZones() {
        let element = SecurityElement(kind: .officialStamp, pageIndex: 1,
                                      boundingBox: NormalizedRect(x: 0.75, y: 0.15, width: 0.15, height: 0.15),
                                      confidence: 0.9)
        let description = element.locationDescription(pageSizePt: .zero)
        XCTAssertTrue(description.contains("strane 2"))
        XCTAssertTrue(description.contains("dolnej"))
    }
}


func awaitAsync<T: Sendable>(_ body: @escaping @Sendable () async -> T) -> T {
    let exp = XCTestExpectation(description: "async")
    nonisolated(unsafe) var result: T?
    Task {
        result = await body()
        exp.fulfill()
    }
    _ = XCTWaiter.wait(for: [exp], timeout: 60)
    return result!
}
