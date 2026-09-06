import XCTest
import PDFKit
import AutogramKit
@testable import AutogramApp

@MainActor
final class ZakoReviewNavigationTests: XCTestCase {
    private func makeTwoPageStore() throws -> ZakoSessionStore {
        let a4 = CGSize(width: 595, height: 842)
        let data = TestPDFBuilderApp.build(pages: [
            (a4, { ctx, size in TestPDFBuilderApp.text("Strana jeden", at: CGPoint(x: 60, y: size.height - 90), size: 16)(ctx, size) }),
            (a4, { ctx, size in TestPDFBuilderApp.text("Strana dva", at: CGPoint(x: 60, y: size.height - 90), size: 16)(ctx, size) })
        ])
        let settingsStore = AppSettingsStore()
        let original = settingsStore.settings
        addTeardownBlock { await MainActor.run { settingsStore.settings = original } }
        settingsStore.settings.learnFromReviews = false
        let bank = ExampleBank(directory: FileManager.default.temporaryDirectory.appendingPathComponent("nav-\(UUID().uuidString)", isDirectory: true))
        let store = ZakoSessionStore(settingsStore: settingsStore, exampleBank: bank)
        store.document = try XCTUnwrap(PDFDocument(data: data))
        store.documentData = data
        store.analysis = PDFAnalysisEngine().analyze(document: store.document!)
        XCTAssertEqual(store.analysis.nonEmptyPages, 2, "Fixtúra musí mať dve neprázdne strany")
        return store
    }

    func testMarkingAPageReviewedAdvancesToTheNextUnreviewedPage() throws {
        let store = try makeTwoPageStore()
        store.previewPageIndex = 0
        store.markPageReviewedAndAdvance(0)
        XCTAssertTrue(store.reviewedNonEmptyPages.contains(0))
        XCTAssertEqual(store.previewPageIndex, 1)

        store.markPageReviewedAndAdvance(1)
        XCTAssertEqual(store.previewPageIndex, 1, "Bez ďalšej neskontrolovanej strany zostane zobrazenie na mieste")
        XCTAssertTrue(store.unconfirmedNonEmptyPages.isEmpty)
    }

    func testConfirmAllPendingConfirmsOnlyThatPage() throws {
        let store = try makeTwoPageStore()
        let a = SecurityElement(kind: .officialStamp, pageIndex: 0, boundingBox: .init(x: 0.1, y: 0.1, width: 0.2, height: 0.2), confidence: 0.9)
        let b = SecurityElement(kind: .handwrittenSignature, pageIndex: 0, boundingBox: .init(x: 0.5, y: 0.1, width: 0.2, height: 0.1), confidence: 0.9)
        let other = SecurityElement(kind: .initial, pageIndex: 1, boundingBox: .init(x: 0.1, y: 0.1, width: 0.1, height: 0.1), confidence: 0.9)
        store.securityElements = [a, b, other]
        store.confirmAllPendingElements(onPage: 0)
        XCTAssertEqual(store.securityElements.filter { $0.pageIndex == 0 }.map(\.reviewState), [.confirmed, .confirmed])
        XCTAssertEqual(store.securityElements.first { $0.id == other.id }?.reviewState, .pending)
    }
}
