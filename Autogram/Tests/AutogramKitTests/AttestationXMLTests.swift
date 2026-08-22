import XCTest
@testable import AutogramKit

final class AttestationXMLTests: XCTestCase {
    private func sampleInput(fingerprint: String = "aabbcc") -> AttestationClauseGenerator.Input {
        let profile = AdvocateProfile(fullName: "JUDr. Ján Advokát",
                                      position: "advokát",
                                      registrationNumber: "1234",
                                      ico: "35764102",
                                      officeName: "Advokátska kancelária Test")
        let attestation = AttestationData(
            originalDocumentOrder: 1,
            originalDocumentName: "Zmluva o dielo <verzia 2>",
            originalDocumentTypeLabel: "Zmluva",
            numberOfSheets: 3,
            sheetCountingMethod: .duplexEstimate,
            nonEmptyPageCount: 5,
            paperSizeBreakdown: [.init(sizeClass: .a4Portrait, sheets: 3)],
            newDocumentName: "Zmluva o dielo (PDF/A)",
            newDocumentFormatLabel: "PDF",
            conversionExecutionDateTime: Date(timeIntervalSince1970: 1_700_000_000),
            evidenceNumber: "2026/000042",
            performingPerson: profile)
        let elements = [
            SecurityElement(kind: .officialStamp, pageIndex: 0,
                            boundingBox: NormalizedRect(x: 0.7, y: 0.1, width: 0.2, height: 0.2),
                            confidence: 0.93,
                            verbalDescription: "Úradná pečiatka v pravej dolnej časti."),
            SecurityElement(kind: .handwrittenSignature, pageIndex: 0,
                            boundingBox: NormalizedRect(x: 0.12, y: 0.82, width: 0.4, height: 0.08),
                            confidence: 0.71)
        ]
        return AttestationClauseGenerator.Input(attestation: attestation,
                                                securityElements: elements,
                                                newDocumentFingerprintSHA256Hex: fingerprint,
                                                qualifiedTimestampTime: nil)
    }

    func testXMLContainsRequiredSchemaElements() throws {
        let xml = AttestationClauseGenerator().generateXML(input: sampleInput())

        XCTAssertTrue(xml.contains(AttestationXMLConstants.namespaceP2E))
        for marker in ["<ConversionRecord",
                       "<OriginalDocumentInfo>",
                       "<OriginalDocumentNumberOfSheets>3</OriginalDocumentNumberOfSheets>",
                       "<OriginalDocumentNonEmptyPageCount>5</OriginalDocumentNonEmptyPageCount>",
                       "<PaperSize>A4 na výšku</PaperSize>",
                       "<NewDocumentInfo>",
                       "<ElectronicFingerprintValue algorithm=\"sha-256\">aabbcc</ElectronicFingerprintValue>",
                       "<GivenName>Ján</GivenName>",
                       "<FamilyName>Advokát</FamilyName>",
                       "<Position>advokát</Position>",
                       "<ConversionExecutionDateTime>",
                       "<ConversionRecordEvidenceNumber>2026/000042</ConversionRecordEvidenceNumber>",
                       "</ConversionRecord>"] {
            XCTAssertTrue(xml.contains(marker), "Chýba fragment: \(marker)\n---\n\(xml)")
        }
    }

    func testXMLEscapesSpecialCharacters() {
        let xml = AttestationClauseGenerator().generateXML(input: sampleInput())
        XCTAssertFalse(xml.contains("<verzia"))
        XCTAssertTrue(xml.contains("&lt;verzia 2&gt;"))
    }

    func testLegalSubjectVariant() {
        var input = sampleInput()
        input.attestation.performingPerson.isLegalEntity = true
        input.attestation.performingPerson.fullName = ""
        input.attestation.performingPerson.officeName = "AK & Partners s.r.o."
        let xml = AttestationClauseGenerator().generateXML(input: input)
        XCTAssertTrue(xml.contains("<LegalSubject>"))
        XCTAssertTrue(xml.contains("AK &amp; Partners s.r.o."))
    }

    func testSHA256HexMatchesKnownVector() {
        XCTAssertEqual(AttestationClauseGenerator.sha256Hex(of: Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testValidatorFlagsMissingFields() {
        var data = AttestationData()
        let errors = AttestationValidator.validate(data, securityElements: [], qualifiedTimestampTime: nil)
        XCTAssertTrue(errors.contains(.missingOriginalName))
        XCTAssertTrue(errors.contains(.missingPerformingPerson))
        XCTAssertTrue(errors.contains(.missingEvidenceNumber))
        XCTAssertTrue(errors.contains(.noSecurityElementsConfirmed))

        data.originalDocumentName = "x"
        data.newDocumentName = "y"
        data.numberOfSheets = 2
        data.evidenceNumber = "2026/001"
        data.performingPerson = AdvocateProfile(fullName: "JUDr. A B", registrationNumber: "1")
        let element = SecurityElement(kind: .officialStamp, pageIndex: 0,
                                      boundingBox: .zero, confidence: 0.9)

        let futureStamp = Date().addingTimeInterval(3600)
        data.conversionExecutionDateTime = Date()
        let timestampErrors = AttestationValidator.validate(data, securityElements: [element],
                                                            qualifiedTimestampTime: futureStamp.addingTimeInterval(-7200))
        XCTAssertTrue(timestampErrors.contains { error in
            if case .timestampBeforeConversionTime = error { return true }
            return false
        })
    }
}
