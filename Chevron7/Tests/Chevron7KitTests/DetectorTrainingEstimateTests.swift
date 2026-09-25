// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class DetectorTrainingEstimateTests: XCTestCase {
    func testFirstEstimateFor40Pages() {
        XCTAssertEqual(DetectorTrainingEstimate.slovak(pages: 40, secondsPerPage: nil),
                       "približne 8 až 15 minút")
    }

    func testRecalibratedEstimateUsesLastRun() {
        XCTAssertEqual(DetectorTrainingEstimate.slovak(pages: 40, secondsPerPage: 10),
                       "približne 5 až 10 minút")
    }

    func testRetrainingEstimateScalesWithPages() {
        XCTAssertEqual(DetectorTrainingEstimate.slovak(pages: 20, secondsPerPage: nil),
                       "približne 4 až 8 minút")
    }

    func testMinuteForms() {
        XCTAssertEqual(DetectorTrainingEstimate.slovak(pages: 4, secondsPerPage: 2), "približne 1 až 1 minútu")
    }
}
