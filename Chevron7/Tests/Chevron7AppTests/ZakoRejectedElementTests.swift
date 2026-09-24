// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
import PDFKit
import Chevron7Kit
@testable import Chevron7App

/// A rejected finding is a negative training example: it recedes on the canvas,
/// never reacts to a click and cannot be reshaped, so its bank entry survives.
@MainActor
final class ZakoRejectedElementTests: XCTestCase {
    private struct ConstantPrints: FeaturePrintProviding {
        func featureVector(for image: CGImage) async throws -> FeatureVector { FeatureVector(values: [0.5]) }
    }

    private func makeStore(learn: Bool) throws -> (ZakoSessionStore, ExampleBank) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zako-rejected-\(UUID().uuidString)", isDirectory: true)
        let bank = ExampleBank(directory: dir)
        let settingsStore = makeSettingsStore()
        let originalSettings = settingsStore.settings
        addTeardownBlock { await MainActor.run { settingsStore.settings = originalSettings } }
        settingsStore.settings.learnFromReviews = learn
        let store = ZakoSessionStore(settingsStore: settingsStore, exampleBank: bank)
        store.bankRecorderFactory = { bank, version in
            ExampleBankRecorder(bank: bank, featurePrints: ConstantPrints(), detectorVersion: version)
        }
        let data = TestPDFBuilderApp.typicalContractPDF()
        store.document = try XCTUnwrap(PDFDocument(data: data))
        store.documentData = data
        store.analysis = PDFAnalysisEngine().analyze(document: store.document!)
        return (store, bank)
    }

    func testHitTestIgnoresARejectedElementAndFindsThePendingOneUnderneath() throws {
        let (store, _) = try makeStore(learn: false)
        // The rejected box is the smaller one, so a plain hit test would prefer it.
        let pending = SecurityElement(kind: .officialStamp, pageIndex: 0,
                                      boundingBox: .init(x: 0.1, y: 0.1, width: 0.5, height: 0.5), confidence: 0.8)
        let rejected = SecurityElement(kind: .handwrittenSignature, pageIndex: 0,
                                       boundingBox: .init(x: 0.2, y: 0.2, width: 0.1, height: 0.1), confidence: 0.5)
        store.securityElements = [pending, rejected]
        store.rejectSecurityElement(id: rejected.id)

        let probe = NormalizedPoint(x: 0.25, y: 0.25)
        XCTAssertEqual(store.elementID(at: probe, pageIndex: 0), pending.id)
        XCTAssertFalse(store.isResizeHandle(rejected.id, at: NormalizedPoint(x: 0.3, y: 0.3)))
        XCTAssertEqual(store.interactiveCanvasElements(onPage: 0).map(\.id), [pending.id])

        store.rejectSecurityElement(id: pending.id)
        XCTAssertNil(store.elementID(at: probe, pageIndex: 0), "Only rejected boxes there: a click starts a new element")
    }

    func testRejectedElementIsLockedAndKeepsItsNegativeExample() async throws {
        let (store, bank) = try makeStore(learn: true)
        let noise = SecurityElement(kind: .handwrittenSignature, pageIndex: 0,
                                    boundingBox: .init(x: 0.1, y: 0.7, width: 0.3, height: 0.05), confidence: 0.5)
        store.securityElements = [noise]
        store.rejectSecurityElement(id: noise.id)
        await store.waitForBankWrites()
        let recorded = await bank.entries()
        XCTAssertEqual(recorded.first { $0.id == noise.id }?.label, .negative)
        let before = try XCTUnwrap(store.securityElements.first)

        store.moveElement(id: noise.id, center: .init(x: 0.5, y: 0.5))
        store.drawElement(id: noise.id, from: .init(x: 0.1, y: 0.1), to: .init(x: 0.6, y: 0.6))
        store.updateElementBoundingBox(id: noise.id, boundingBox: .init(x: 0.3, y: 0.3, width: 0.2, height: 0.2))
        store.updateElementPage(id: noise.id, pageIndex: 1)
        store.updateElementKind(id: noise.id, kind: .officialStamp)
        store.updateElementDescription(id: noise.id, text: "Iný popis")
        XCTAssertNil(store.duplicateElement(id: noise.id))
        await store.refineElement(id: noise.id)
        await store.waitForBankWrites()

        XCTAssertEqual(store.securityElements, [before], "A rejected element must not change")
        let after = await bank.entries()
        XCTAssertEqual(after.first { $0.id == noise.id }?.label, .negative, "The negative example must survive")
    }

    func testDeleteRejectsAPendingAISuggestionAndRemovesAHandDrawnElement() throws {
        let (store, _) = try makeStore(learn: false)
        let suggestion = SecurityElement(kind: .officialStamp, pageIndex: 0,
                                         boundingBox: .init(x: 0.1, y: 0.1, width: 0.2, height: 0.2), confidence: 0.7)
        let drawn = SecurityElement(kind: .initial, pageIndex: 0,
                                    boundingBox: .init(x: 0.5, y: 0.1, width: 0.1, height: 0.1), confidence: 1,
                                    detectedByAI: false, reviewState: .pending)
        let rejected = SecurityElement(kind: .handwrittenSignature, pageIndex: 0,
                                       boundingBox: .init(x: 0.5, y: 0.5, width: 0.1, height: 0.1), confidence: 0.4,
                                       reviewState: .rejected)
        store.securityElements = [suggestion, drawn, rejected]

        XCTAssertEqual(store.deleteOrRejectSecurityElement(id: suggestion.id), .rejected)
        XCTAssertEqual(store.securityElements.first { $0.id == suggestion.id }?.reviewState, .rejected)
        XCTAssertNil(store.lastDeletedElement, "A rejection is not a deletion to undo")

        XCTAssertEqual(store.deleteOrRejectSecurityElement(id: drawn.id), .removed)
        XCTAssertFalse(store.securityElements.contains { $0.id == drawn.id })

        XCTAssertEqual(store.deleteOrRejectSecurityElement(id: rejected.id), .ignored)
        XCTAssertEqual(store.securityElements.first { $0.id == rejected.id }?.reviewState, .rejected)

        store.removeSecurityElement(id: rejected.id)
        XCTAssertTrue(store.securityElements.contains { $0.id == rejected.id }, "The store never deletes a rejected element")
    }

    func testReturningARejectedElementToReviewMakesItPendingAndEditableAgain() async throws {
        let (store, bank) = try makeStore(learn: true)
        let noise = SecurityElement(kind: .handwrittenSignature, pageIndex: 0,
                                    boundingBox: .init(x: 0.1, y: 0.7, width: 0.3, height: 0.05), confidence: 0.5)
        store.securityElements = [noise]
        store.rejectSecurityElement(id: noise.id)
        store.returnSecurityElementToReview(id: noise.id)
        await store.waitForBankWrites()

        XCTAssertEqual(store.securityElements.first?.reviewState, .pending)
        let entries = await bank.entries()
        XCTAssertTrue(entries.isEmpty, "Returning to review forgets the negative example")
        store.moveElement(id: noise.id, center: .init(x: 0.5, y: 0.5))
        XCTAssertEqual(try XCTUnwrap(store.securityElements.first).boundingBox.midX, 0.5, accuracy: 0.001)
    }
}
