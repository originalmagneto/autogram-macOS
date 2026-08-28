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
            mandateRequirementSatisfied: true)

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
}
