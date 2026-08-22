import XCTest
import PDFKit
@testable import AutogramKit

final class PDFAnalysisEngineTests: XCTestCase {
    func testCountsPagesNonEmptyPagesAndSheets() throws {
        let data = TestPDFBuilder.typicalContractPDF()
        let document = try XCTUnwrap(PDFDocument(data: data))

        let engine = PDFAnalysisEngine()
        let analysis = engine.analyze(document: document)

        XCTAssertEqual(analysis.totalPages, 3)
        XCTAssertEqual(analysis.nonEmptyPages, 2)
        XCTAssertEqual(analysis.estimatedSheetsDuplex, 1)
    }

    func testBlankPageDetection() throws {
        let blankData = TestPDFBuilder.singlePageWhitePDF()
        let document = try XCTUnwrap(PDFDocument(data: blankData))
        let engine = PDFAnalysisEngine(blankInkCoverageThreshold: 0.006)

        let analysis = engine.analyze(document: document)
        XCTAssertTrue(analysis.pageAnalyses[0].isEmpty)
        XCTAssertLessThan(analysis.pageAnalyses[0].inkCoverage, 0.006)
    }

    func testPaperSizeClassification() throws {
        let document = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let analysis = PDFAnalysisEngine().analyze(document: document)

        XCTAssertEqual(analysis.pageAnalyses[0].sizeClass, .a4Portrait)
        XCTAssertEqual(analysis.pageAnalyses[1].sizeClass, .a4Portrait)
        XCTAssertEqual(analysis.pageAnalyses[2].sizeClass, .a3Landscape)
        XCTAssertTrue(analysis.pageAnalyses.allSatisfy { $0.sizeClass.isKnownFormat })
    }

    func testTitleSuggestion() throws {
        let document = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let analysis = PDFAnalysisEngine().analyze(document: document)
        let title = try XCTUnwrap(analysis.suggestedTitle)
        XCTAssertTrue(title.contains("ZMLUVA"))
    }

    func testSheetMethods() {
        var store = SheetMethodProbe(totalNonEmpty: 7, duplexEstimate: 4)
        store.method = .duplexEstimate
        XCTAssertEqual(store.resolved, 4)
        store.method = .oneSheetPerPage
        XCTAssertEqual(store.resolved, 7)
        store.method = .manual
        store.manual = 9
        XCTAssertEqual(store.resolved, 9)
    }
}

private struct SheetMethodProbe {
    let totalNonEmpty: Int
    let duplexEstimate: Int
    var method: SheetCountingMethod = .duplexEstimate
    var manual: Int?

    var resolved: Int {
        switch method {
        case .duplexEstimate: return duplexEstimate
        case .oneSheetPerPage: return totalNonEmpty
        case .manual: return max(manual ?? 0, 0)
        }
    }
}
