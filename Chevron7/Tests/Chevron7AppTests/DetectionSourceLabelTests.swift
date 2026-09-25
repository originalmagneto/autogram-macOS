// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7App

final class DetectionSourceLabelTests: XCTestCase {
    func testManualElementHasNoDetectionSource() {
        XCTAssertEqual(DetectionSourceLabel.slovak(nil), "Označené ručne")
    }

    func testHintOnlyHeuristicIsNamedAsAnEstimate() {
        XCTAssertEqual(DetectionSourceLabel.slovak("builtIn; builtInHint"),
                       "heuristika; iba odhad heuristiky")
    }

    func testNearestNeighbourCountIsSpelledOut() {
        XCTAssertEqual(DetectionSourceLabel.slovak("contour+saliency; kNN(n=7)"),
                       "kontúry+saliency; porovnanie s 7 príkladmi")
    }

    func testFoundationModelIsNamed() {
        XCTAssertEqual(DetectionSourceLabel.slovak("builtIn; fm"), "heuristika; on-device model")
    }

    func testRecalledReviewIsNamed() {
        XCTAssertEqual(DetectionSourceLabel.slovak("reviewedPage"), "vaša skoršia kontrola tejto strany")
    }

    func testLearnedDetectorIsNamed() {
        XCTAssertEqual(DetectionSourceLabel.slovak("learned+contour; kNN(n=7)"),
                       "váš detektor+kontúry; porovnanie s 7 príkladmi")
    }

    func testExactMatchWithAnEarlierDecisionIsNamed() {
        XCTAssertEqual(DetectionSourceLabel.slovak("contour; kNN(exact)"),
                       "kontúry; rovnaké ako vaše skoršie rozhodnutie")
    }
}
