import Foundation
import XCTest
@testable import AutogramKit

final class AttestationValidatorTests: XCTestCase {
    private let validElements = [
        SecurityElement(
            kind: .handwrittenSignature,
            pageIndex: 0,
            boundingBox: NormalizedRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2),
            confidence: 1,
            verbalDescription: "Podpis",
            detectedByAI: false)
    ]

    private func validAttestationData() -> AttestationData {
        AttestationData(
            originalDocumentName: "Pôvodný dokument",
            originalDocumentTypeLabel: "Zmluva",
            numberOfSheets: 1,
            nonEmptyPageCount: 1,
            newDocumentName: "Dokument.pdf",
            evidenceNumber: "2026/000001",
            performingPerson: AdvocateProfile(
                fullName: "JUDr. Test",
                registrationNumber: "1234"))
    }

    func testValidationRequiresOriginConfirmation() {
        var data = validAttestationData()
        data.originConfirmed = false

        let errors = AttestationValidator.validate(data, securityElements: validElements, qualifiedTimestampTime: nil)

        XCTAssertTrue(errors.contains(.originNotConfirmed))
    }

    func testValidationPassesWhenOriginIsConfirmed() {
        var data = validAttestationData()
        data.originConfirmed = true

        let errors = AttestationValidator.validate(data, securityElements: validElements, qualifiedTimestampTime: nil)

        XCTAssertFalse(errors.contains(.originNotConfirmed))
    }

    func testPreflightRejectsInvalidLocalAttestation() {
        var data = validAttestationData()
        data.originConfirmed = false

        let result = AttestationPreflight.evaluate(
            data,
            securityElements: validElements,
            hasSelectedIdentity: true,
            mandateRequirementSatisfied: true,
            inputSignatureInspection: .completed(signatures: []))

        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.errors.contains(.originNotConfirmed))
    }
    func testLegacyAttestationDecodesOriginAsUnconfirmed() throws {
        let encoded = try JSONEncoder.pretty.encode(validAttestationData())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "originConfirmed")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder.standard.decode(AttestationData.self, from: legacyData)

        XCTAssertFalse(decoded.originConfirmed)
    }
    func testReusedTemplateRequiresFreshOriginConfirmation() throws {
        var template = validAttestationData()
        template.originConfirmed = true
        let persisted = try JSONEncoder.pretty.encode(template)
        let decodedTemplate = try JSONDecoder.standard.decode(AttestationData.self, from: persisted)

        var reusedForAnotherDocument = decodedTemplate
        reusedForAnotherDocument.originConfirmed = false
        let errors = AttestationValidator.validate(
            reusedForAnotherDocument,
            securityElements: validElements,
            qualifiedTimestampTime: nil)

        XCTAssertTrue(errors.contains(.originNotConfirmed))
    }
    func testPreflightBlocksResolvedNonMandateIdentity() {
        var data = validAttestationData()
        data.originConfirmed = true

        let result = AttestationPreflight.evaluate(
            data,
            securityElements: validElements,
            hasSelectedIdentity: true,
            mandateRequirementSatisfied: false,
            inputSignatureInspection: .completed(signatures: []))

        XCTAssertFalse(result.isComplete)
    }

    func testPreflightAllowsResolvedMandateIdentity() {
        var data = validAttestationData()
        data.originConfirmed = true

        let result = AttestationPreflight.evaluate(
            data,
            securityElements: validElements,
            hasSelectedIdentity: true,
            mandateRequirementSatisfied: true,
            inputSignatureInspection: .completed(signatures: []))

        XCTAssertTrue(result.isComplete)
    }

    func testPreflightRequiresReviewOfElementsAndNonEmptyPages() {
        var data = validAttestationData()
        data.originConfirmed = true
        let pending = SecurityElement(
            kind: .officialStamp,
            pageIndex: 0,
            boundingBox: NormalizedRect(x: 0.4, y: 0.2, width: 0.2, height: 0.2),
            confidence: 0.8,
            detectedByAI: true)

        let blocked = AttestationPreflight.evaluate(
            data,
            securityElements: [pending],
            hasSelectedIdentity: true,
            mandateRequirementSatisfied: true,
            inputSignatureInspection: .completed(signatures: []),
            unreviewedNonEmptyPages: [0])

        XCTAssertFalse(blocked.isComplete)
        XCTAssertTrue(blocked.errors.contains { error in
            if case .securityElementsNeedReview(1) = error { return true }
            return false
        })
        XCTAssertTrue(blocked.errors.contains { error in
            if case .unreviewedNonEmptyPages([0]) = error { return true }
            return false
        })

        var confirmed = pending
        confirmed.reviewState = .confirmed
        let complete = AttestationPreflight.evaluate(
            data,
            securityElements: [confirmed],
            hasSelectedIdentity: true,
            mandateRequirementSatisfied: true,
            inputSignatureInspection: .completed(signatures: []),
            unreviewedNonEmptyPages: [])
        XCTAssertTrue(complete.isComplete)
    }

    func testRejectedElementDoesNotSatisfyConfirmedElementRequirement() {
        var data = validAttestationData()
        data.originConfirmed = true
        let rejected = SecurityElement(
            kind: .officialStamp,
            pageIndex: 0,
            boundingBox: .zero,
            confidence: 1,
            detectedByAI: true,
            reviewState: .rejected)

        let result = AttestationPreflight.evaluate(
            data,
            securityElements: [rejected],
            hasSelectedIdentity: true,
            mandateRequirementSatisfied: true,
            inputSignatureInspection: .completed(signatures: []),
            unreviewedNonEmptyPages: [])

        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.errors.contains(.noSecurityElementsConfirmed))
    }

    func testLegacySecurityElementDecodesAsPending() throws {
        let element = SecurityElement(
            kind: .handwrittenSignature,
            pageIndex: 0,
            boundingBox: .zero,
            confidence: 0.5,
            detectedByAI: false)
        let encoded = try JSONEncoder().encode(element)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "reviewState")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(SecurityElement.self, from: legacy)

        XCTAssertEqual(decoded.reviewState, .pending)
    }

    func testSecurityReviewStampSortsPagesAndRoundTrips() throws {
        let stamp = SecurityReviewStamp(
            checkedNonEmptyPageIndices: [3, 0, 2],
            confirmedElementCount: 2,
            rejectedElementCount: 1,
            detectorIdentifier: "test-detector",
            reviewedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let encoded = try JSONEncoder().encode(stamp)
        let decoded = try JSONDecoder().decode(SecurityReviewStamp.self, from: encoded)

        XCTAssertEqual(decoded, stamp)
        XCTAssertEqual(decoded.checkedNonEmptyPageIndices, [0, 2, 3])
        XCTAssertEqual(decoded.detectorIdentifier, "test-detector")
    }
}
