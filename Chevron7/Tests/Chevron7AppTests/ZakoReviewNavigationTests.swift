// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
import PDFKit
import Chevron7Kit
@testable import Chevron7App

@MainActor
final class ZakoReviewNavigationTests: XCTestCase {
    func testEmptyConfirmationIsExplicitAndInvalidatedByANewFinding() throws {
        let store = try makeTwoPageStore()
        store.confirmNoSecurityElements()
        XCTAssertFalse(store.attestation.noSecurityElementsConfirmed)
        store.markPageReviewed(0)
        store.markPageReviewed(1)
        store.confirmNoSecurityElements()
        XCTAssertTrue(store.attestation.noSecurityElementsConfirmed)
        store.addPhysicalSecurityElement(kind: .bindingCord, pageIndex: 0,
            description: "Zväzok zviazaný šnúrkou", location: "Ľavý okraj", newDocumentPageIndex: 0)
        XCTAssertFalse(store.attestation.noSecurityElementsConfirmed)
        XCTAssertFalse(store.reviewedNonEmptyPages.contains(0))
        XCTAssertTrue(store.reviewedNonEmptyPages.contains(1))
        XCTAssertFalse(try XCTUnwrap(store.securityElements.last).hasScanRegion)
    }

    func testEditingConfirmedKindInvalidatesOnlyItsPage() throws {
        let store = try makeTwoPageStore()
        store.addSecurityElement(kind: .officialStamp, pageIndex: 0,
            rect: .init(x: 0.1, y: 0.1, width: 0.2, height: 0.2))
        let id = try XCTUnwrap(store.securityElements.last?.id)
        store.confirmSecurityElement(id: id)
        store.markPageReviewed(0)
        store.markPageReviewed(1)
        store.updateElementKind(id: id, kind: .waxSeal)
        XCTAssertEqual(store.securityElements.first?.reviewState, .pending)
        XCTAssertFalse(store.reviewedNonEmptyPages.contains(0))
        XCTAssertTrue(store.reviewedNonEmptyPages.contains(1))
    }
    func testManualDetailStaysRequiredWhenElementMoves() throws {
        let store = try makeTwoPageStore()
        for kind in [SecurityElement.Kind.other, .permanentBinding] {
            store.addSecurityElement(kind: kind, pageIndex: 0,
                rect: .init(x: 0.1, y: 0.1, width: 0.2, height: 0.2))
            let id = try XCTUnwrap(store.securityElements.last?.id)
            store.moveElement(id: id, center: .init(x: 0.5, y: 0.5))
            store.updateElementPage(id: id, pageIndex: 1)
            store.confirmSecurityElement(id: id)
            XCTAssertEqual(store.securityElements.last?.verbalDescription, "")
            XCTAssertTrue(AttestationValidator.validate(store.attestation,
                securityElements: store.confirmedSecurityElements, qualifiedTimestampTime: nil)
                .contains(.securityElementDescriptionRequired))
            store.updateElementDescription(id: id, text: "Spojené kovovým nitom")
            store.moveElement(id: id, center: .init(x: 0.4, y: 0.4))
            XCTAssertEqual(store.securityElements.last?.verbalDescription, "Spojené kovovým nitom")
        }
    }

    func testConfirmedPhysicalFindingOverridesBlankDetectionUntilRejected() throws {
        let store = try makeTwoPageStore()
        store.analysis.pageAnalyses[1].isEmpty = true
        store.analysis.nonEmptyPages = 1
        store.attestation.nonEmptyPageCount = 1
        let id = store.addPhysicalSecurityElement(kind: .watermark, pageIndex: 1,
            description: "Vodoznak viditeľný proti svetlu", location: "Stred listu", newDocumentPageIndex: 1)
        store.confirmSecurityElement(id: id)
        XCTAssertFalse(store.analysis.pageAnalyses[1].isEmpty)
        XCTAssertEqual(store.analysis.nonEmptyPages, 2)
        XCTAssertEqual(store.attestation.nonEmptyPageCount, 2)
        store.markPageReviewed(1)
        XCTAssertTrue(store.reviewedNonEmptyPages.contains(1))
        store.rejectSecurityElement(id: id)
        XCTAssertTrue(store.analysis.pageAnalyses[1].isEmpty)
        XCTAssertEqual(store.analysis.nonEmptyPages, 1)
        XCTAssertEqual(store.attestation.nonEmptyPageCount, 1)
    }

    private func makeTwoPageStore() throws -> ZakoSessionStore {
        let a4 = CGSize(width: 595, height: 842)
        let data = TestPDFBuilderApp.build(pages: [
            (a4, { ctx, size in TestPDFBuilderApp.text("Strana jeden", at: CGPoint(x: 60, y: size.height - 90), size: 16)(ctx, size) }),
            (a4, { ctx, size in TestPDFBuilderApp.text("Strana dva", at: CGPoint(x: 60, y: size.height - 90), size: 16)(ctx, size) })
        ])
        let settingsStore = makeSettingsStore()
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
