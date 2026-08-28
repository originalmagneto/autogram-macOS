import XCTest
@testable import AutogramKit

final class AccessibilityContractTests: XCTestCase {
    func testSubmittedEvidenceOutcomeIsExplicit() {
        XCTAssertEqual(EvidenceRecord.Status.submitted.rawValue, "Zapísané v CEZZK")
        XCTAssertNotEqual(EvidenceRecord.Status.submitted, .queuedForSubmission)
    }

    func testQueuedEvidenceOutcomeIsNotSubmitted() {
        XCTAssertEqual(EvidenceRecord.Status.queuedForSubmission.rawValue, "Vo fronte odoslania")
        XCTAssertTrue(EvidenceRecord.Status.queuedForSubmission.progressIndex < EvidenceRecord.Status.submitted.progressIndex)
    }
}
