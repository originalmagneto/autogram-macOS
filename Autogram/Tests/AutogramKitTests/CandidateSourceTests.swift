import XCTest
import PDFKit
@testable import AutogramKit

final class CandidateSourceTests: XCTestCase {
    private func renderedContractPage() throws -> CGImage {
        let document = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let page = try XCTUnwrap(document.page(at: 0))
        return try XCTUnwrap(BuiltInVisionProvider.render(page: page, targetWidth: 760)?.cgImage)
    }

    /// Renders page 0 once and computes its exclusions, mirroring the shared
    /// render pass LayeredDetectionProvider performs.
    private func preparedContractPage() throws -> PreparedPage {
        let document = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let page = try XCTUnwrap(document.page(at: 0))
        let rendered = try XCTUnwrap(BuiltInVisionProvider.render(page: page, targetWidth: 760))
        let box = TestUncheckedSendable(rendered)
        return awaitAsync { () -> TestUncheckedSendable<PreparedPage> in
            let exclusions = await BuiltInVisionProvider.visionExclusionBoxes(cgImage: box.value.cgImage)
            return TestUncheckedSendable(PreparedPage(pageIndex: 0, pixels: box.value.pixels,
                                                      image: box.value.cgImage, exclusions: exclusions))
        }.value
    }

    func testBuiltInSourceConvertsElementsToHintedCandidatesAndPassesBarcodesThrough() throws {
        let prepared = try preparedContractPage()
        let result = BuiltInCandidateSource().candidates(on: prepared)
        XCTAssertFalse(result.candidates.isEmpty, "Vstavaný detektor má vrátiť aspoň jedného kandidáta")
        XCTAssertTrue(result.candidates.allSatisfy { $0.sources == [.builtIn] && $0.kindHint != nil })
        XCTAssertTrue(result.passthrough.allSatisfy { $0.kind == .other })
        // One passthrough element per barcode, exactly as the frozen provider emits.
        let barcodes = result.passthrough.filter { $0.verbalDescription == "Čiarový kód / QR (notárska pripojka)" }
        XCTAssertEqual(barcodes.count, prepared.exclusions.barcodeBoxes.count)
        XCTAssertTrue(barcodes.allSatisfy { !$0.detectedByAI && $0.confidence == 0.9 && $0.reviewState == .pending })
    }

    func testContourSourceFindsDrawnStampRegion() throws {
        let image = try renderedContractPage()
        let candidates = try awaitAsyncThrowing {
            try await ContourCandidateSource().candidates(pageImage: image, pageIndex: 0)
        }
        // typicalContractPDF draws a ring at the lower right; expect a candidate whose
        // centre lies in that quadrant.
        XCTAssertTrue(candidates.contains { $0.box.midX > 0.5 && $0.box.midY < 0.5 },
                      "Kontúry nenašli kandidáta v pravom dolnom kvadrante: \(candidates.map(\.box))")
        XCTAssertTrue(candidates.allSatisfy { $0.sources == [.contour] })
    }

    func testSaliencySourceReturnsOnlyValidNormalizedBoxes() throws {
        let image = try renderedContractPage()
        let candidates = try awaitAsyncThrowing {
            try await SaliencyCandidateSource().candidates(pageImage: image, pageIndex: 0)
        }
        for c in candidates {
            XCTAssertTrue((0...1).contains(c.box.x) && (0...1).contains(c.box.y))
            XCTAssertLessThanOrEqual(c.box.x + c.box.width, 1.0001)
            XCTAssertLessThanOrEqual(c.box.y + c.box.height, 1.0001)
            XCTAssertGreaterThan(c.box.width, 0)
            XCTAssertGreaterThan(c.box.height, 0)
            XCTAssertEqual(c.sources, [.saliency])
        }
    }
}

func awaitAsyncThrowing<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) throws -> T {
    let expectation = XCTestExpectation(description: "async")
    nonisolated(unsafe) var result: Result<T, Error>?
    Task {
        do { result = .success(try await body()) } catch { result = .failure(error) }
        expectation.fulfill()
    }
    _ = XCTWaiter.wait(for: [expectation], timeout: 60)
    return try result!.get()
}
