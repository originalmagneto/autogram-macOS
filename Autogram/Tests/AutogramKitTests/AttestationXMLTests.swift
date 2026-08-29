import XCTest
@testable import AutogramKit

final class AttestationXMLTests: XCTestCase {
    private func sampleInput(fingerprintHex: String =
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        -> AttestationClauseGenerator.Input {
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
            newDocumentName: "Zmluva o dielo.pdf",
            newDocumentFormatLabel: "PDF/A-2",
            conversionExecutionDateTime: Date(timeIntervalSince1970: 1_700_000_000),
            evidenceNumber: "1563-231114-42",
            performingPerson: profile,
            usedDeviceDescription: "Skenovanie / import do aplikácie Autogram")
        let elements = [
            SecurityElement(kind: .officialStamp, pageIndex: 0,
                            boundingBox: NormalizedRect(x: 0.7, y: 0.1, width: 0.2, height: 0.2),
                            confidence: 0.93,
                            verbalDescription: "Úradná pečiatka v pravej dolnej časti."),
            SecurityElement(kind: .handwrittenSignature, pageIndex: 4,
                            boundingBox: NormalizedRect(x: 0.12, y: 0.82, width: 0.4, height: 0.08),
                            confidence: 0.71)
        ]
        return AttestationClauseGenerator.Input(attestation: attestation,
                                                securityElements: elements,
                                                newDocumentFingerprintSHA256Hex: fingerprintHex)
    }

    func testXMLContainsRequiredSchemaElements() throws {
        let xml = AttestationClauseGenerator().generateXML(input: sampleInput())

        XCTAssertTrue(xml.contains(AttestationXMLConstants.namespaceP2E))
        for marker in ["<ConversionRecord",
                       "<OriginalDocumentInfo>",
                       "<OriginalDocumentNumberOfSheets>3</OriginalDocumentNumberOfSheets>",
                       "<OriginalDocumentNonEmptyPageCount>5</OriginalDocumentNonEmptyPageCount>",
                       "<CodelistCode>12</CodelistCode>",
                       "<ItemCode>A4</ItemCode>",
                       "<PaperSizeNumberOfSheets>3</PaperSizeNumberOfSheets>",
                       "<CodelistCode>15</CodelistCode>",
                       "<ItemCode>okrúhla pečiatka so štátnym znakom</ItemCode>",
                       "<SecurityElementVerbalDescription>Úradná pečiatka",
                       "<OriginalDocumentSecurityElementsPage>1</OriginalDocumentSecurityElementsPage>",
                       "<OriginalDocumentSecurityElementsSheet>1</OriginalDocumentSecurityElementsSheet>",
                       "<OriginalDocumentSecurityElementsPage>5</OriginalDocumentSecurityElementsPage>",
                       "<OriginalDocumentSecurityElementsSheet>3</OriginalDocumentSecurityElementsSheet>",
                       "<CodelistCode>11</CodelistCode>",
                       "<ItemCode>Right down</ItemCode>",
                       "<NewDocumentInfo>",
                       "<NewDocumentName>Zmluva o dielo.pdf</NewDocumentName>",
                       "<CodelistCode>53</CodelistCode>",
                       "<ItemCode>PDFA2</ItemCode>",
                       "<ElectronicFingerprintValue>ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=</ElectronicFingerprintValue>",
                       "<ElectronicFingerprintCalculationMethod>",
                       "<CodelistCode>14</CodelistCode>",
                       "<ItemCode>SHA-256</ItemCode>",
                       "<GivenName>Ján</GivenName>",
                       "<FamilyName>Advokát</FamilyName>",
                       "<Position>advokát</Position>",
                       "<LegalSubject>",
                       "<Name>Advokátska kancelária Test</Name>",
                       "<IdentifierValue>ico://sk/35764102</IdentifierValue>",
                       "<UsedDevice>Skenovanie / import do aplikácie Autogram</UsedDevice>",
                       "<ConversionExecutionDateTime>",
                       "<ConversionRecordEvidenceNumber>https://data.gov.sk/id/egov/conversion-record/1563-231114-42</ConversionRecordEvidenceNumber>",
                       "</ConversionRecord>"] {
            XCTAssertTrue(xml.contains(marker), "Chýba fragment: \(marker)\n---\n\(xml)")
        }
    }

    func testLocationAndSheetMapping() {
        XCTAssertEqual(SecurityElement.Kind.handwrittenSignature.codelist15Item.code,
                       "vlastnoručný podpis")

        let bottomRight = SecurityElement(kind: .officialStamp, pageIndex: 0,
                                          boundingBox: NormalizedRect(x: 0.8, y: 0.05,
                                                                      width: 0.15, height: 0.15),
                                          confidence: 1)
        XCTAssertEqual(bottomRight.locationCodelist11Item.code, "Right down")

        let topCenter = SecurityElement(kind: .embossedSeal, pageIndex: 0,
                                        boundingBox: NormalizedRect(x: 0.45, y: 0.85,
                                                                    width: 0.1, height: 0.1),
                                        confidence: 1)
        XCTAssertEqual(topCenter.locationCodelist11Item.code, "Up")

        XCTAssertEqual(bottomRight.sheetNumber(sheetMethod: .duplexEstimate), 1)
        XCTAssertEqual(topCenter.sheetNumber(sheetMethod: .duplexEstimate), 1)

        var pageFive = topCenter
        pageFive.pageIndex = 4
        XCTAssertEqual(pageFive.sheetNumber(sheetMethod: .duplexEstimate), 3)
        XCTAssertEqual(pageFive.sheetNumber(sheetMethod: .oneSheetPerPage), 5)
    }

    func testFingerprintBase64KnownVector() {
        XCTAssertEqual(AttestationClauseGenerator.fingerprintBase64(
            hex: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
            "ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=")
    }

    func testXMLEscapesSpecialCharacters() {
        let xml = AttestationClauseGenerator().generateXML(input: sampleInput())
        XCTAssertFalse(xml.contains("<verzia"))
        XCTAssertTrue(xml.contains("&lt;verzia 2&gt;"))
    }

    func testLegalSubjectOnlyVariantForLegalEntity() {
        var input = sampleInput()
        input.attestation.performingPerson.isLegalEntity = true
        input.attestation.performingPerson.fullName = ""
        input.attestation.performingPerson.officeName = "AK & Partners s.r.o."
        let xml = AttestationClauseGenerator().generateXML(input: input)
        XCTAssertTrue(xml.contains("<LegalSubject>"))
        XCTAssertTrue(xml.contains("AK &amp; Partners s.r.o."))
        XCTAssertFalse(xml.contains("<PhysicalPerson>"))
    }

    func testSHA256HexMatchesKnownVector() {
        XCTAssertEqual(AttestationClauseGenerator.sha256Hex(of: Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testExplicitFormPackGenerationUsesPackNamespaceAndFormat() throws {
        let input = sampleInput()
        let customFormat = ZakoCodelistItem(code: "TEST_FORMAT", skName: "Test format")
        let pack = ConversionFormPack(
            id: "explicit-test-pack",
            direction: .paperToElectronic,
            recordVersion: "test-record",
            clauseVersion: "test-clause",
            namespace: "https://example.invalid/forms/test",
            eFormIdentifier: "example/test",
            effectiveFrom: Date(timeIntervalSince1970: 0),
            verificationState: .unverified,
            acceptanceState: .unknown,
            renderer: .legacySwift,
            newDocumentFormatItem: customFormat,
            fingerprintMethodItem: ZakoCodelists.sha256Item)

        let xml = try AttestationClauseGenerator().generateXML(input: input, formPack: pack)

        XCTAssertTrue(xml.contains("xmlns=\"https://example.invalid/forms/test\""))
        XCTAssertTrue(xml.contains("<ItemCode>TEST_FORMAT</ItemCode>"))
        XCTAssertFalse(xml.contains(AttestationXMLConstants.namespaceP2E))
    }

    func testValidatorRequiresNamespaceOnRootElement() throws {
        let input = sampleInput()
        let pack = FormPackRepository.currentLegacyUnverified
        let xml = try AttestationClauseGenerator().generateXML(input: input, formPack: pack)
        let wrongNamespaceXML = xml.replacingOccurrences(
            of: "xmlns=\"\(pack.namespace)\"",
            with: "xmlns=\"https://example.invalid/wrong\"")

        let issues = AttestationXMLValidator().validate(
            wrongNamespaceXML,
            context: .init(fingerprintSHA256Hex: input.newDocumentFingerprintSHA256Hex,
                           securityElementCount: input.securityElements.count),
            formPack: pack)

        XCTAssertTrue(issues.contains { $0.contains("namespace") })
    }

    func testExplicitFormPackGenerationRejectsMalformedFingerprint() {
        var input = sampleInput(fingerprintHex: "not-a-sha256")

        XCTAssertThrowsError(try AttestationClauseGenerator().generateXML(
            input: input,
            formPack: FormPackRepository.currentLegacyUnverified)) { error in
            XCTAssertEqual(error as? AttestationGenerationError, .invalidFingerprint)
        }
        input.newDocumentFingerprintSHA256Hex = String(repeating: "a", count: 64)
        XCTAssertNoThrow(try AttestationClauseGenerator().generateXML(
            input: input,
            formPack: FormPackRepository.currentLegacyUnverified))
    }

    func testExplicitFormPackGenerationRejectsNonPaperToElectronicPack() {
        let pack = ConversionFormPack(
            id: "e-to-p-test-pack",
            direction: .electronicToPaper,
            recordVersion: "1.0",
            clauseVersion: "1.0",
            namespace: "https://example.invalid/e-to-p",
            eFormIdentifier: "example/e-to-p",
            effectiveFrom: Date(timeIntervalSince1970: 0),
            verificationState: .verified,
            acceptanceState: .accepted,
            renderer: .legacySwift,
            newDocumentFormatItem: ZakoCodelists.pdfa2FormatItem,
            fingerprintMethodItem: ZakoCodelists.sha256Item)

        XCTAssertThrowsError(try AttestationClauseGenerator().generateXML(
            input: sampleInput(),
            formPack: pack)) { error in
            XCTAssertEqual(error as? FormPackError, .unsupportedDirection(.electronicToPaper))
        }
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
        data.evidenceNumber = "1563-231114-1"
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
