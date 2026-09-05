import XCTest
@testable import AutogramKit

final class TwoStageClassifierTests: XCTestCase {
    private func knn(_ kind: SecurityElement.Kind?, conf: Double, margin: Double, support: Int) -> ElementJudgement {
        ElementJudgement(kind: kind, confidence: conf, margin: margin, decidedBy: .featurePrintKNN, supportCount: support)
    }
    private func fm(_ kind: SecurityElement.Kind?, conf: Double, desc: String = "") -> ElementJudgement {
        ElementJudgement(kind: kind, confidence: conf, descriptionSK: desc, decidedBy: .foundationModel)
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
}
