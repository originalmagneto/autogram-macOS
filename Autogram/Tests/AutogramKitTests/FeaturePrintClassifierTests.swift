import XCTest
@testable import AutogramKit

final class FeaturePrintClassifierTests: XCTestCase {
    private func v(_ a: Float, _ b: Float) -> FeatureVector { FeatureVector(values: [a, b]) }

    func testDistanceIsEuclidean() {
        XCTAssertEqual(v(0, 0).distance(to: v(3, 4)), 5, accuracy: 1e-9)
    }

    func testVoteReturnsNearestLabelWithMargin() {
        let examples: [(FeatureVector, BankLabel)] = [
            (v(1, 0), .kind(.officialStamp)), (v(1.1, 0), .kind(.officialStamp)), (v(0.9, 0), .kind(.officialStamp)),
            (v(0, 1), .kind(.handwrittenSignature)), (v(0, 1.1), .negative)
        ]
        let judgement = FeaturePrintClassifier.vote(query: v(1, 0.05), examples: examples, k: 5)
        XCTAssertEqual(judgement.kind, .officialStamp)
        XCTAssertEqual(judgement.decidedBy, .featurePrintKNN)
        XCTAssertGreaterThan(judgement.margin, 0.25)
        XCTAssertEqual(judgement.supportCount, 3)
    }

    func testNegativeWinnerYieldsNilKind() {
        let examples: [(FeatureVector, BankLabel)] = [(v(0, 0), .negative), (v(0.1, 0), .negative), (v(5, 5), .kind(.initial))]
        let judgement = FeaturePrintClassifier.vote(query: v(0, 0), examples: examples, k: 3)
        XCTAssertNil(judgement.kind)
        XCTAssertEqual(judgement.supportCount, 2)
    }

    func testEmptyBankYieldsZeroConfidence() {
        let judgement = FeaturePrintClassifier.vote(query: v(0, 0), examples: [], k: 5)
        XCTAssertNil(judgement.kind)
        XCTAssertEqual(judgement.confidence, 0)
        XCTAssertEqual(judgement.margin, 0)
        XCTAssertEqual(judgement.supportCount, 0)
    }
}
