// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class DetectorPromotionTests: XCTestCase {
    private func metrics(precision tpFP: (Int, Int), recall tpFN: (Int, Int)) -> LabelMetrics {
        LabelMetrics(truePositives: tpFP.0, falsePositives: tpFP.1, falseNegatives: tpFN.1)
    }

    func testPromoteOnRecallGain() {
        let decision = DetectorPromotion.decide(
            candidate: ["officialStamp": metrics(precision: (8, 2), recall: (8, 2))],
            active: ["officialStamp": metrics(precision: (6, 4), recall: (6, 4))],
            trainedLabels: ["officialStamp"])
        guard case .promote = decision else {
            return XCTFail("recall 0.8 vs 0.6 with steady precision must promote, got \(decision)")
        }
    }

    func testKeepWhenPrecisionDropsTooMuch() {
        let decision = DetectorPromotion.decide(
            candidate: ["officialStamp": metrics(precision: (8, 8), recall: (8, 2))],
            active: ["officialStamp": metrics(precision: (6, 4), recall: (6, 4))],
            trainedLabels: ["officialStamp"])
        guard case .keep = decision else {
            return XCTFail("precision 0.5 vs 0.6 must keep, got \(decision)")
        }
    }

    func testKeepWhenRecallGainTooSmall() {
        let decision = DetectorPromotion.decide(
            candidate: ["officialStamp": metrics(precision: (6, 4), recall: (6, 4))],
            active: ["officialStamp": metrics(precision: (6, 4), recall: (6, 4))],
            trainedLabels: ["officialStamp"])
        guard case .keep = decision else {
            return XCTFail("recall gain below 0.05 must keep, got \(decision)")
        }
    }

    func testKeepWhenNoTrainedLabels() {
        let decision = DetectorPromotion.decide(candidate: [:], active: [:], trainedLabels: [])
        guard case .keep = decision else {
            return XCTFail("no trained labels must keep, got \(decision)")
        }
    }
}
