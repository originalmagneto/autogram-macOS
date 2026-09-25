// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class AccessibilityContractTests: XCTestCase {
    func testSubmittedEvidenceOutcomeIsExplicit() {
        XCTAssertEqual(EvidenceRecord.Status.submitted.rawValue, "Zapísané v CEZZK")
        XCTAssertNotEqual(EvidenceRecord.Status.submitted, .queuedForSubmission)
    }

    func testQueuedEvidenceOutcomeIsNotSubmitted() {
        XCTAssertEqual(EvidenceRecord.Status.queuedForSubmission.rawValue, "Vo fronte odoslania")
        XCTAssertTrue(EvidenceRecord.Status.queuedForSubmission.progressIndex < EvidenceRecord.Status.submitted.progressIndex)
    }

    func testCountUsesSlovakPlurals() {
        XCTAssertEqual(UXLabels.count(1, one: "príklad", few: "príklady", many: "príkladov"), "1 príklad")
        XCTAssertEqual(UXLabels.count(2, one: "príklad", few: "príklady", many: "príkladov"), "2 príklady")
        XCTAssertEqual(UXLabels.count(5, one: "príklad", few: "príklady", many: "príkladov"), "5 príkladov")
        XCTAssertEqual(UXLabels.count(0, one: "strana", few: "strany", many: "strán"), "0 strán")
        XCTAssertEqual(UXLabels.count(1, one: "dokument", few: "dokumenty", many: "dokumentov"), "1 dokument")
    }

    func testConfidenceLabelRequiresNumericValue() {
        XCTAssertEqual(UXLabels.confidenceLabel(for: 0.62), "Istota 62 %")
    }

    func testPendingEvidenceLabelIncludesDeadlineState() {
        XCTAssertTrue(UXLabels.evidenceStatusLabel(for: .queuedForSubmission)
            .localizedCaseInsensitiveContains("čaká"))
    }
}
