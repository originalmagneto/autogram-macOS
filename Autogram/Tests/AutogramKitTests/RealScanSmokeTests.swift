import XCTest
import PDFKit
@testable import AutogramKit

/// End-to-end check against a real scan, gated on `AUTOGRAM_DIAG_PDF` so CI without
/// the file simply skips it. The document is a two page power of attorney: page 0 is a
/// ruled form of printed text with no security element, page 1 carries the signatures.
final class RealScanSmokeTests: XCTestCase {
    func testRealScanHasNoSignaturesOnTheFormPage() throws {
        guard let path = ProcessInfo.processInfo.environment["AUTOGRAM_DIAG_PDF"],
              let document = PDFDocument(url: URL(fileURLWithPath: path)) else { throw XCTSkip("no pdf") }
        let analysis = PDFAnalysisEngine().analyze(document: document)
        let bank = ExampleBank(directory: FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID())"))
        let provider = LayeredDetectionProvider.makeDefault(bank: bank, useFoundationModel: true)
        let doc = TestUncheckedSendable(document)
        let start = Date()
        let (elements, stats) = diagWait { await provider.detectWithStats(in: doc.value, pageAnalyses: analysis.pageAnalyses) }
        print("DIAG elapsed=\(Date().timeIntervalSince(start))s stats=\(stats)")
        for e in elements {
            print("DIAG p\(e.pageIndex) \(e.kind.rawValue) conf=\(e.confidence) box=\(e.boundingBox) src=\(e.detectionSource ?? "-") desc=\(e.verbalDescription)")
        }

        let signatureKinds: Set<SecurityElement.Kind> = [.handwrittenSignature, .initial]
        let formPage = elements.filter { $0.pageIndex == 0 && signatureKinds.contains($0.kind) }
        let signedPage = elements.filter { $0.pageIndex == 1 && $0.kind == .handwrittenSignature }
        XCTAssertTrue(formPage.isEmpty,
                      "Strana 1 je tlačený formulár bez podpisu: \(formPage.map(\.detectionSource))")
        XCTAssertFalse(signedPage.isEmpty, "Strana 2 obsahuje rukou písaný podpis")
    }
}

func diagWait<T: Sendable>(_ body: @escaping @Sendable () async -> T) -> T {
    let exp = XCTestExpectation(description: "diag")
    nonisolated(unsafe) var result: T?
    Task { result = await body(); exp.fulfill() }
    _ = XCTWaiter.wait(for: [exp], timeout: 900)
    return result!
}
