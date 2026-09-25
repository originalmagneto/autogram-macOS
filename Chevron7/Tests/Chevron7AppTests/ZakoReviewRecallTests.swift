// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
import PDFKit
import Chevron7Kit
@testable import Chevron7App

/// What a reviewer taught the detector must survive the next analysis: opening
/// the same document again brings back the complete page review, and running
/// the AI again never erases decisions from the example bank.
@MainActor
final class ZakoReviewRecallTests: XCTestCase {
    private struct ConstantPrints: FeaturePrintProviding {
        func featureVector(for image: CGImage) async throws -> FeatureVector { FeatureVector(values: [0.5]) }
    }
    /// Stands in for the detector: always the same wrong suggestion on page 0.
    private struct FixedDetector: SecurityElementsProviding {
        var providerName: String { "fixed" }
        func detect(in document: PDFDocument, pageAnalyses: [PageAnalysis]) async -> [SecurityElement] {
            [SecurityElement(kind: .initial, pageIndex: 0, boundingBox: ZakoReviewRecallTests.wrongBox,
                             confidence: 0.71, detectedByAI: true, reviewState: .pending, detectionSource: "contour; fm")]
        }
    }

    nonisolated static let wrongBox = NormalizedRect(x: 0.65, y: 0.26, width: 0.05, height: 0.05)
    private let stampBox = NormalizedRect(x: 0.52, y: 0.2, width: 0.18, height: 0.12)

    private func makeStore(learn: Bool = true, bank existing: ExampleBank? = nil,
                           documentData existingData: Data? = nil) throws -> (ZakoSessionStore, ExampleBank) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zako-recall-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let bank = existing ?? ExampleBank(directory: dir)
        let settingsStore = makeSettingsStore()
        let originalSettings = settingsStore.settings
        addTeardownBlock { await MainActor.run { settingsStore.settings = originalSettings } }
        settingsStore.settings.learnFromReviews = learn
        let store = ZakoSessionStore(settingsStore: settingsStore, exampleBank: bank)
        store.bankRecorderFactory = { bank, version in
            ExampleBankRecorder(bank: bank, featurePrints: ConstantPrints(), detectorVersion: version)
        }
        store.detectionPipelineFactory = { _, _ in DetectionPipeline(builtin: FixedDetector()) }
        // The generated PDF carries its creation time, so reopening "the same
        // file" has to reuse the very same bytes.
        let data = existingData ?? TestPDFBuilderApp.typicalContractPDF()
        store.document = try XCTUnwrap(PDFDocument(data: data))
        store.documentData = data
        store.analysis = PDFAnalysisEngine().analyze(document: store.document!)
        return (store, bank)
    }

    /// Reviews page 0 with one hand-drawn stamp, as the reviewer did in an earlier session.
    private func reviewPageZero(_ store: ZakoSessionStore) async {
        store.securityElements = [SecurityElement(kind: .officialStamp, pageIndex: 0, boundingBox: stampBox,
                                                  confidence: 1, detectedByAI: false)]
        store.markPageReviewed(0)
        await store.waitForBankWrites()
    }

    func testOpeningAReviewedDocumentAgainRecallsTheReview() async throws {
        let (earlier, bank) = try makeStore()
        await reviewPageZero(earlier)

        // The same file opened again: a fresh session over the same bank.
        let (store, _) = try makeStore(bank: bank, documentData: earlier.documentData)
        await store.runAnalysis(recallingReviewedPages: true)
        await store.waitForBankWrites()

        let pageZero = store.securityElements.filter { $0.pageIndex == 0 }
        XCTAssertEqual(pageZero.map(\.boundingBox), [stampBox])
        XCTAssertEqual(pageZero.first?.kind, .officialStamp)
        XCTAssertEqual(pageZero.first?.reviewState, .pending)
        XCTAssertEqual(pageZero.first?.detectionSource, ReviewedPageRecall.detectionSource)
        // Loading the recalled boxes is not a human edit: the review stays in the bank.
        let pages = try await bank.reviewedPages()
        XCTAssertEqual(pages.map(\.pageIndex), [0])
    }

    func testRunningTheAIAgainDetectsAfreshButKeepsTheBankIntact() async throws {
        let (store, bank) = try makeStore()
        await reviewPageZero(store)

        await store.runAnalysis()
        await store.waitForBankWrites()

        XCTAssertEqual(store.securityElements.filter { $0.detectedByAI }.map(\.boundingBox), [Self.wrongBox])
        let pages = try await bank.reviewedPages()
        XCTAssertEqual(pages.map(\.pageIndex), [0])
    }

    func testRunningTheAIAgainKeepsRejectionsInTheBank() async throws {
        let (store, bank) = try makeStore()
        await store.runAnalysis()
        let suggestion = try XCTUnwrap(store.securityElements.first { $0.detectedByAI })
        store.rejectSecurityElement(id: suggestion.id)
        await store.waitForBankWrites()

        await store.runAnalysis()
        await store.waitForBankWrites()

        let entries = await bank.entries()
        XCTAssertEqual(entries.map(\.id), [suggestion.id])
        XCTAssertEqual(entries.first?.label, .negative)
    }

    func testNoRecallWhenLearningIsOff() async throws {
        let (store, bank) = try makeStore(learn: false)
        let recorder = ExampleBankRecorder(bank: bank, featurePrints: ConstantPrints(), detectorVersion: "test/1")
        let document = UncheckedSendable(store.document!)
        let stamp = SecurityElement(kind: .officialStamp, pageIndex: 0, boundingBox: stampBox,
                                    confidence: 1, detectedByAI: false)
        try await recorder.recordReviewedPage(document: document.value, documentData: store.documentData!,
                                              pageIndex: 0, elements: [stamp])

        await store.runAnalysis(recallingReviewedPages: true)

        XCTAssertEqual(store.securityElements.map(\.boundingBox), [Self.wrongBox])
    }
}
