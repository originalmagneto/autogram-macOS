// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
import PDFKit
import Chevron7Kit
@testable import Chevron7App

@MainActor
final class ZakoBankRecordingTests: XCTestCase {
    private struct ConstantPrints: FeaturePrintProviding {
        func featureVector(for image: CGImage) async throws -> FeatureVector { FeatureVector(values: [0.5]) }
    }

    private func makeStore(learn: Bool) throws -> (ZakoSessionStore, ExampleBank) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zako-bank-\(UUID().uuidString)", isDirectory: true)
        let bank = ExampleBank(directory: dir)
        let settingsStore = makeSettingsStore()
        // AppSettingsStore.settings.didSet persists to disk, so the user's real
        // settings must be put back when the test finishes.
        let originalSettings = settingsStore.settings
        addTeardownBlock {
            await MainActor.run { settingsStore.settings = originalSettings }
        }
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

    func testConfirmAndRejectWriteBankEntriesAndReturnRemovesThem() async throws {
        let (store, bank) = try makeStore(learn: true)
        let stamp = SecurityElement(kind: .officialStamp, pageIndex: 0,
                                    boundingBox: .init(x: 0.6, y: 0.1, width: 0.2, height: 0.2), confidence: 0.8)
        let noise = SecurityElement(kind: .handwrittenSignature, pageIndex: 0,
                                    boundingBox: .init(x: 0.1, y: 0.7, width: 0.3, height: 0.05), confidence: 0.5)
        store.securityElements = [stamp, noise]

        store.confirmSecurityElement(id: stamp.id)
        store.rejectSecurityElement(id: noise.id)
        await store.waitForBankWrites()

        let entries = await bank.entries()
        XCTAssertEqual(Set(entries.map(\.id)), [stamp.id, noise.id])
        XCTAssertEqual(entries.first { $0.id == stamp.id }?.label, .kind(.officialStamp))
        XCTAssertEqual(entries.first { $0.id == noise.id }?.label, .negative)

        store.returnSecurityElementToReview(id: stamp.id)
        await store.waitForBankWrites()
        let remainingIDs = await bank.entries().map(\.id)
        XCTAssertEqual(remainingIDs, [noise.id])
    }

    func testPhysicalObservationInvalidatesAndExcludesBothReferencedPages() async throws {
        let (store, bank) = try makeStore(learn: true)
        // Use two pages so the original and converted page references differ.
        store.document!.insert(try XCTUnwrap(store.document!.page(at: 0)?.copy() as? PDFPage), at: 1)
        store.documentData = try XCTUnwrap(store.document!.dataRepresentation())
        store.analysis = PDFAnalysisEngine().analyze(document: store.document!)
        store.markPageReviewed(0)
        store.markPageReviewed(1)
        await store.waitForBankWrites()
        let before = try await bank.reviewedPages()
        XCTAssertEqual(Set(before.map(\.pageIndex)), [0, 1])
        let id = store.addPhysicalSecurityElement(kind: .bindingCord, pageIndex: 0,
            description: "Trikolóra", location: "Ľavý okraj", newDocumentPageIndex: 1)
        store.confirmSecurityElement(id: id)
        store.markPageReviewed(0)
        store.markPageReviewed(1)
        await store.waitForBankWrites()
        let pages = try await bank.reviewedPages()
        let crops = await bank.entries()
        XCTAssertTrue(pages.isEmpty)
        XCTAssertTrue(crops.isEmpty)
    }

    func testLearningOffWritesNothing() async throws {
        let (store, bank) = try makeStore(learn: false)
        let stamp = SecurityElement(kind: .officialStamp, pageIndex: 0,
                                    boundingBox: .init(x: 0.6, y: 0.1, width: 0.2, height: 0.2), confidence: 0.8)
        store.securityElements = [stamp]
        store.confirmSecurityElement(id: stamp.id)
        await store.waitForBankWrites()
        let entries = await bank.entries()
        XCTAssertTrue(entries.isEmpty)
    }

    func testRapidDecisionsOnOneElementApplyInOrder() async throws {
        let (store, bank) = try makeStore(learn: true)
        let stamp = SecurityElement(kind: .officialStamp, pageIndex: 0,
                                    boundingBox: .init(x: 0.6, y: 0.1, width: 0.2, height: 0.2), confidence: 0.8)
        store.securityElements = [stamp]

        store.confirmSecurityElement(id: stamp.id)
        store.returnSecurityElementToReview(id: stamp.id)
        await store.waitForBankWrites()
        let entriesAfterReturn = await bank.entries()
        XCTAssertTrue(entriesAfterReturn.isEmpty, "Návrat na kontrolu po potvrdení musí záznam odstrániť")

        store.rejectSecurityElement(id: stamp.id)
        store.confirmSecurityElement(id: stamp.id)
        await store.waitForBankWrites()
        let entriesAfterConfirm = await bank.entries()
        XCTAssertEqual(entriesAfterConfirm.first?.label, .kind(.officialStamp))
    }

    func testReviewStampCarriesDetectorIdentifier() throws {
        let (store, _) = try makeStore(learn: true)
        XCTAssertTrue(store.securityReviewStamp.detectorIdentifier.hasPrefix("LayeredDetectionProvider/"))
    }
}
