// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

// A review decision must change the next detection run on the same document:
// the recorder and the detector have to embed the very same crop, and one
// decision on that crop has to be enough.
import XCTest
import PDFKit
import CoreGraphics
@testable import Chevron7Kit

final class ReviewLearningTests: XCTestCase {
    /// Deterministic stand-in for Vision feature prints: an 8 x 8 grayscale
    /// thumbnail plus the crop size, so a crop cut from a differently sized
    /// render lands far away while the same crop lands at 0.
    private struct PixelPrints: FeaturePrintProviding {
        func featureVector(for image: CGImage) async throws -> FeatureVector {
            let side = 8
            var gray = [UInt8](repeating: 0, count: side * side)
            let context = CGContext(data: &gray, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return FeatureVector(values: gray.map { Float($0) / 255 } + [Float(image.width) / 100, Float(image.height) / 100])
        }
    }
    private struct FixedSource: CandidateSourcing {
        let source: CandidateSource = .contour
        let boxes: [NormalizedRect]
        func candidates(pageImage: CGImage, pageIndex: Int) async throws -> [DetectionCandidate] {
            boxes.map { DetectionCandidate(pageIndex: pageIndex, box: $0, sources: [source]) }
        }
    }
    /// A model without memory that calls every crop an initial, as the
    /// on-device model kept doing for the reviewer's stamp fragments.
    private struct AlwaysInitial: ElementClassifying {
        func classify(crop: CGImage, hint: SecurityElement.Kind?) async throws -> ElementJudgement {
            ElementJudgement(kind: .initial, confidence: 0.71, decidedBy: .foundationModel)
        }
    }

    private let renderWidth = 380

    private func fixture() throws -> (PDFDocument, Data, [PageAnalysis], ExampleBank, LayeredDetectionProvider, ExampleBankRecorder) {
        let data = TestPDFBuilder.typicalContractPDF()
        let document = try XCTUnwrap(PDFDocument(data: data))
        let analyses = PDFAnalysisEngine().analyze(document: document).pageAnalyses
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("learn-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let bank = ExampleBank(directory: dir)
        let provider = LayeredDetectionProvider(
            extraSources: [FixedSource(boxes: [fixedBox])],
            classifier: TwoStageClassifier(primary: FeaturePrintClassifier(bank: bank, featurePrints: PixelPrints()),
                                           secondary: AlwaysInitial()),
            renderTargetWidth: renderWidth)
        let recorder = ExampleBankRecorder(bank: bank, featurePrints: PixelPrints(),
                                           featureRenderWidth: renderWidth, detectorVersion: "test/1")
        // Like the reviewer's real bank: plenty of confirmed initials elsewhere,
        // so a lone decision cannot win on vote support alone.
        let doc = TestUncheckedSendable(document)
        try awaitAsyncThrowing {
            for column in 0..<5 {
                let initial = SecurityElement(kind: .initial, pageIndex: 0,
                                              boundingBox: .init(x: 0.05 + Double(column) * 0.1, y: 0.02,
                                                                 width: 0.06, height: 0.04),
                                              confidence: 1, detectedByAI: false)
                try await recorder.record(document: doc.value, documentData: data, element: initial,
                                          label: .kind(.initial))
            }
        }
        return (document, data, analyses, bank, provider, recorder)
    }

    private func suggestions(_ provider: LayeredDetectionProvider, _ document: PDFDocument,
                             _ analyses: [PageAnalysis]) -> [SecurityElement] {
        let doc = TestUncheckedSendable(document)
        return awaitAsync { await provider.detect(in: doc.value, pageAnalyses: analyses) }.filter(\.detectedByAI)
    }

    private let fixedBox = NormalizedRect(x: 0.6, y: 0.1, width: 0.2, height: 0.2)

    func testOneRejectionRemovesTheSuggestionFromTheNextRun() throws {
        let (document, data, analyses, _, provider, recorder) = try fixture()
        let rejected = try XCTUnwrap(suggestions(provider, document, analyses).first { $0.pageIndex == 0 && $0.boundingBox == fixedBox })
        let doc = TestUncheckedSendable(document)
        try awaitAsyncThrowing {
            try await recorder.record(document: doc.value, documentData: data, element: rejected, label: .negative)
        }
        let again = suggestions(provider, document, analyses).filter { $0.pageIndex == 0 && $0.boundingBox == fixedBox }
        XCTAssertTrue(again.isEmpty, "rejected suggestion came back: \(again.map(\.kind))")
    }

    func testOneConfirmationWinsOverTheModelOnTheNextRun() throws {
        let (document, data, analyses, _, provider, recorder) = try fixture()
        var suggestion = try XCTUnwrap(suggestions(provider, document, analyses).first { $0.pageIndex == 0 && $0.boundingBox == fixedBox })
        suggestion.kind = .waxSeal
        let corrected = suggestion
        let doc = TestUncheckedSendable(document)
        try awaitAsyncThrowing {
            try await recorder.record(document: doc.value, documentData: data, element: corrected, label: .kind(.waxSeal))
        }
        let again = suggestions(provider, document, analyses).filter { $0.pageIndex == 0 && $0.boundingBox == fixedBox }
        XCTAssertFalse(again.isEmpty)
        XCTAssertTrue(again.allSatisfy { $0.kind == .waxSeal }, "\(again.map(\.kind))")
        XCTAssertTrue(again.allSatisfy { $0.detectionSource?.hasSuffix("kNN(exact)") == true },
                      "\(again.map(\.detectionSource))")
    }

    func testRecorderEmbedsCropsAtTheDetectorsRenderWidthByDefault() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("learn-\(UUID().uuidString)", isDirectory: true)
        let recorder = ExampleBankRecorder(bank: ExampleBank(directory: dir), detectorVersion: "test/1")
        XCTAssertEqual(recorder.featureRenderWidth, LayeredDetectionProvider.defaultRenderTargetWidth)
        XCTAssertEqual(LayeredDetectionProvider.makeDefault(bank: ExampleBank(directory: dir), useFoundationModel: false)
            .renderTargetWidth, LayeredDetectionProvider.defaultRenderTargetWidth)
    }
}
