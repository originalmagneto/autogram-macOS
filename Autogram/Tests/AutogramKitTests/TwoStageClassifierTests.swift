import XCTest
import CoreGraphics
@testable import AutogramKit

final class TwoStageClassifierTests: XCTestCase {
    private func knn(_ kind: SecurityElement.Kind?, conf: Double, margin: Double, support: Int) -> ElementJudgement {
        ElementJudgement(kind: kind, confidence: conf, margin: margin, decidedBy: .featurePrintKNN, supportCount: support)
    }
    private func fm(_ kind: SecurityElement.Kind?, conf: Double, desc: String = "",
                    isUnsure: Bool = false) -> ElementJudgement {
        ElementJudgement(kind: kind, confidence: conf, descriptionSK: desc, decidedBy: .foundationModel,
                         isUnsure: isUnsure)
    }

    func testConfidentKNNWins() {
        let result = TwoStageClassifier.decide(primary: knn(.officialStamp, conf: 0.8, margin: 0.6, support: 5),
                                               secondary: fm(.handwrittenSignature, conf: 0.9),
                                               hint: nil, hintConfidence: nil, minimumSupport: 3, minimumMargin: 0.25)
        XCTAssertEqual(result?.kind, .officialStamp)
        XCTAssertEqual(result?.decidedBy, .featurePrintKNN)
    }

    func testWeakKNNDefersToFoundationModelAndBlendsWhenAgreeing() {
        let result = TwoStageClassifier.decide(primary: knn(.officialStamp, conf: 0.5, margin: 0.1, support: 4),
                                               secondary: fm(.officialStamp, conf: 0.9, desc: "Pečiatka."),
                                               hint: nil, hintConfidence: nil, minimumSupport: 3, minimumMargin: 0.25)
        XCTAssertEqual(result?.kind, .officialStamp)
        XCTAssertEqual(result?.decidedBy, .foundationModel)
        XCTAssertEqual(result!.confidence, 0.6 * 0.9 + 0.4 * 0.5, accuracy: 1e-9)
        XCTAssertEqual(result?.descriptionSK, "Pečiatka.")
    }

    func testLowSupportDefersEvenWithHighMargin() {
        let result = TwoStageClassifier.decide(primary: knn(.initial, conf: 1, margin: 1, support: 1),
                                               secondary: fm(.handwrittenSignature, conf: 0.7),
                                               hint: nil, hintConfidence: nil, minimumSupport: 3, minimumMargin: 0.25)
        XCTAssertEqual(result?.kind, .handwrittenSignature)
        XCTAssertEqual(result!.confidence, 0.7, accuracy: 1e-9)
    }

    func testFoundationModelNegativeDiscardsCandidate() {
        let result = TwoStageClassifier.decide(primary: knn(nil, conf: 0, margin: 0, support: 0),
                                               secondary: fm(nil, conf: 0.9),
                                               hint: .officialStamp, hintConfidence: 0.7, minimumSupport: 3, minimumMargin: 0.25)
        XCTAssertNil(result)
    }

    func testNoSecondaryFallsBackToHint() {
        let result = TwoStageClassifier.decide(primary: knn(nil, conf: 0, margin: 0, support: 0),
                                               secondary: nil,
                                               hint: .handwrittenSignature, hintConfidence: 0.66, minimumSupport: 3, minimumMargin: 0.25)
        XCTAssertEqual(result?.kind, .handwrittenSignature)
        XCTAssertEqual(result!.confidence, 0.66, accuracy: 1e-9)
        XCTAssertEqual(result?.decidedBy, .builtInHint)
    }

    func testNoSecondaryAndNoHintDiscards() {
        let result = TwoStageClassifier.decide(primary: knn(nil, conf: 0, margin: 0, support: 0),
                                               secondary: nil, hint: nil, hintConfidence: nil,
                                               minimumSupport: 3, minimumMargin: 0.25)
        XCTAssertNil(result)
    }

    func testConfidentKNNNegativeDiscardsEvenWithHint() {
        let result = TwoStageClassifier.decide(primary: knn(nil, conf: 0.9, margin: 0.8, support: 6),
                                               secondary: nil, hint: .officialStamp, hintConfidence: 0.9,
                                               minimumSupport: 3, minimumMargin: 0.25)
        XCTAssertNil(result)
    }

    func testUnsureSecondaryFallsThroughToHint() {
        let result = TwoStageClassifier.decide(primary: knn(nil, conf: 0, margin: 0, support: 0),
                                               secondary: fm(nil, conf: 0, isUnsure: true),
                                               hint: .officialStamp, hintConfidence: 0.7,
                                               minimumSupport: 3, minimumMargin: 0.25)
        XCTAssertEqual(result?.kind, .officialStamp)
        XCTAssertEqual(result?.decidedBy, .builtInHint)
    }

    func testUnsureSecondaryWithoutHintDiscards() {
        let result = TwoStageClassifier.decide(primary: knn(nil, conf: 0, margin: 0, support: 0),
                                               secondary: fm(nil, conf: 0, isUnsure: true),
                                               hint: nil, hintConfidence: nil,
                                               minimumSupport: 3, minimumMargin: 0.25)
        XCTAssertNil(result)
    }

    /// A model answer of "not a security element" is decisive even at confidence 0,
    /// so it must beat the built-in hint instead of falling through to it.
    func testDecisiveNegativeSecondaryDiscardsHintedCandidateEvenAtZeroConfidence() {
        let result = TwoStageClassifier.decide(primary: knn(nil, conf: 0, margin: 0, support: 0),
                                               secondary: fm(nil, conf: 0, isUnsure: false),
                                               hint: .handwrittenSignature, hintConfidence: 0.75,
                                               minimumSupport: 3, minimumMargin: 0.25)
        XCTAssertNil(result)
    }

    private final class CountingClassifier: ElementClassifying, @unchecked Sendable {
        let judgement: ElementJudgement
        var calls = 0
        init(_ judgement: ElementJudgement) { self.judgement = judgement }
        func classify(crop: CGImage, hint: SecurityElement.Kind?) async throws -> ElementJudgement {
            calls += 1
            return judgement
        }
    }

    private func blankImage() throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(ctx.makeImage())
    }

    func testSecondaryIsConsultedOnlyWhenPrimaryIsUnsure() throws {
        let image = try blankImage()
        let confident = CountingClassifier(knn(.officialStamp, conf: 0.9, margin: 0.9, support: 9))
        let weak = CountingClassifier(knn(.officialStamp, conf: 0.4, margin: 0.05, support: 9))
        let secondary = CountingClassifier(fm(.officialStamp, conf: 0.8))

        let a = TwoStageClassifier(primary: confident, secondary: secondary)
        _ = awaitAsync { await a.classify(crop: image, hint: nil, hintConfidence: nil) }
        XCTAssertEqual(secondary.calls, 0)

        let b = TwoStageClassifier(primary: weak, secondary: secondary)
        let result = awaitAsync { await b.classify(crop: image, hint: nil, hintConfidence: nil) }
        XCTAssertEqual(secondary.calls, 1)
        XCTAssertEqual(result?.decidedBy, .foundationModel)
    }
}
