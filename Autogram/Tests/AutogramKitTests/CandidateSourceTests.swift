import XCTest
import PDFKit
@testable import AutogramKit

final class CandidateSourceTests: XCTestCase {
    private func renderedContractPage() throws -> CGImage {
        let document = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let page = try XCTUnwrap(document.page(at: 0))
        return try XCTUnwrap(BuiltInVisionProvider.render(page: page, targetWidth: 760)?.cgImage)
    }

    func testBuiltInSourceConvertsElementsToHintedCandidatesAndPassesBarcodesThrough() throws {
        let document = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let analysis = PDFAnalysisEngine().analyze(document: document)
        let doc = TestUncheckedSendable(document)
        let result = awaitAsync {
            await BuiltInCandidateSource().candidates(in: doc.value, pageAnalyses: analysis.pageAnalyses)
        }
        XCTAssertFalse(result.candidates.isEmpty, "Vstavaný detektor má vrátiť aspoň jedného kandidáta")
        XCTAssertTrue(result.candidates.allSatisfy { $0.sources == [.builtIn] && $0.kindHint != nil })
        XCTAssertTrue(result.passthrough.allSatisfy { $0.kind == .other })
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
