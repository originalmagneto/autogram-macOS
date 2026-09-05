import XCTest
import PDFKit
import CoreGraphics
@testable import AutogramKit

final class LayeredDetectionProviderTests: XCTestCase {
    private struct FixedSource: CandidateSourcing {
        let source: CandidateSource
        let boxes: [NormalizedRect]
        let fails: Bool
        func candidates(pageImage: CGImage, pageIndex: Int) async throws -> [DetectionCandidate] {
            if fails { throw NSError(domain: "test", code: 1) }
            return boxes.map { DetectionCandidate(pageIndex: pageIndex, box: $0, sources: [source]) }
        }
    }
    private struct FixedClassifier: ElementClassifying {
        let judgement: ElementJudgement
        func classify(crop: CGImage, hint: SecurityElement.Kind?) async throws -> ElementJudgement { judgement }
    }

    private func contract() throws -> (PDFDocument, [PageAnalysis]) {
        let document = try XCTUnwrap(PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        return (document, PDFAnalysisEngine().analyze(document: document).pageAnalyses)
    }

    func testEmitsPendingAIElementsWithDetectionSource() throws {
        let (document, analyses) = try contract()
        let classifier = TwoStageClassifier(
            primary: FixedClassifier(judgement: .init(kind: .officialStamp, confidence: 0.9, margin: 0.9,
                                                      descriptionSK: "Pečiatka.", decidedBy: .featurePrintKNN, supportCount: 10)),
            secondary: nil)
        let provider = LayeredDetectionProvider(
            extraSources: [FixedSource(source: .contour, boxes: [.init(x: 0.6, y: 0.1, width: 0.2, height: 0.2)], fails: false)],
            classifier: classifier)
        let doc = TestUncheckedSendable(document)
        let elements = awaitAsync { await provider.detect(in: doc.value, pageAnalyses: analyses) }
        let stamps = elements.filter { $0.kind == .officialStamp }
        XCTAssertFalse(stamps.isEmpty)
        for stamp in stamps {
            XCTAssertTrue(stamp.detectedByAI)
            XCTAssertEqual(stamp.reviewState, .pending)
            XCTAssertEqual(stamp.verbalDescription, "Pečiatka.")
            let source = try XCTUnwrap(stamp.detectionSource)
            XCTAssertTrue(source.contains("kNN"), source)
        }
    }

    func testFailingSourceDoesNotLoseBuiltInCandidates() throws {
        let (document, analyses) = try contract()
        let classifier = TwoStageClassifier(primary: FixedClassifier(judgement: .unsure), secondary: nil)
        let provider = LayeredDetectionProvider(
            extraSources: [FixedSource(source: .saliency, boxes: [], fails: true)],
            classifier: classifier)
        let doc = TestUncheckedSendable(document)
        let elements = awaitAsync { await provider.detect(in: doc.value, pageAnalyses: analyses) }
        // With an unsure kNN and no FM, hints from the built-in provider survive.
        XCTAssertTrue(elements.contains { $0.kind == .officialStamp || $0.kind == .handwrittenSignature },
                      "Vstavané nálezy musia prežiť zlyhanie zdroja: \(elements.map(\.kind))")
        XCTAssertTrue(elements.filter { $0.kind != .other }.allSatisfy { $0.detectionSource?.contains("builtInHint") == true })
    }

    func testNegativeClassificationDropsCandidates() throws {
        let (document, analyses) = try contract()
        let classifier = TwoStageClassifier(
            primary: FixedClassifier(judgement: .init(kind: nil, confidence: 0.95, margin: 0.9, decidedBy: .featurePrintKNN, supportCount: 9)),
            secondary: nil)
        let provider = LayeredDetectionProvider(extraSources: [], classifier: classifier)
        let doc = TestUncheckedSendable(document)
        let elements = awaitAsync { await provider.detect(in: doc.value, pageAnalyses: analyses) }
        XCTAssertTrue(elements.allSatisfy { $0.kind == .other }, "Len barcode passthrough smie zostať")
    }

    func testIdentifierListsActiveStages() {
        let classifier = TwoStageClassifier(primary: FixedClassifier(judgement: .unsure),
                                            secondary: FixedClassifier(judgement: .unsure))
        let provider = LayeredDetectionProvider(classifier: classifier)
        XCTAssertEqual(provider.identifier, "LayeredDetectionProvider/1 builtIn+contour+saliency kNN fm")
        let noFM = LayeredDetectionProvider(extraSources: [], classifier: TwoStageClassifier(primary: FixedClassifier(judgement: .unsure), secondary: nil))
        XCTAssertEqual(noFM.identifier, "LayeredDetectionProvider/1 builtIn kNN")
    }

    func testDetectionPipelineAcceptsLayeredProvider() throws {
        let (document, analyses) = try contract()
        let provider = LayeredDetectionProvider(extraSources: [], classifier: TwoStageClassifier(primary: FixedClassifier(judgement: .unsure), secondary: nil))
        let pipeline = DetectionPipeline(builtin: provider)
        let doc = TestUncheckedSendable(document)
        let elements = awaitAsync { await pipeline.detect(in: doc.value, pageAnalyses: analyses) }
        XCTAssertFalse(elements.isEmpty)
    }
}
