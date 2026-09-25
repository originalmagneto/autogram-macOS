// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

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
        // Off both negatives, so the vote runs instead of the exact-match rule.
        let judgement = FeaturePrintClassifier.vote(query: v(0.05, 0.05), examples: examples, k: 3)
        XCTAssertFalse(judgement.isExactMatch)
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

    /// One earlier decision on the very same crop outweighs any number of merely
    /// similar examples: the reviewer already ruled on exactly this region.
    func testExactMatchIsDecisiveWithASingleExample() {
        let examples: [(FeatureVector, BankLabel)] = [
            (v(0, 0), .negative),
            (v(0.5, 0), .kind(.initial)), (v(0.5, 0.1), .kind(.initial)),
            (v(0.5, 0.2), .kind(.initial)), (v(0.5, 0.3), .kind(.initial))
        ]
        let judgement = FeaturePrintClassifier.vote(query: v(0, 0.01), examples: examples, k: 5)
        XCTAssertTrue(judgement.isExactMatch)
        XCTAssertNil(judgement.kind)
        XCTAssertEqual(judgement.supportCount, 1)
        XCTAssertEqual(judgement.confidence, 1)
    }

    func testConflictingExactMatchesAreNotDecisive() {
        let examples: [(FeatureVector, BankLabel)] = [(v(0, 0), .negative), (v(0.01, 0), .kind(.initial))]
        let judgement = FeaturePrintClassifier.vote(query: v(0, 0), examples: examples, k: 5)
        XCTAssertFalse(judgement.isExactMatch)
    }

    func testSimilarButDistinctCropIsNotAnExactMatch() {
        let examples: [(FeatureVector, BankLabel)] = [(v(0, 0), .negative)]
        let judgement = FeaturePrintClassifier.vote(query: v(Float(FeaturePrintClassifier.exactMatchDistance * 2), 0),
                                                    examples: examples, k: 5)
        XCTAssertFalse(judgement.isExactMatch)
    }
}
