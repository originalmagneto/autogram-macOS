// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

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
            usedDeviceDescription: "Skenovanie / import do aplikácie Chevron7")
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
                       "<OriginalDocumentSecurityElementsDescription>Odtlačok pečiatky: Úradná pečiatka v pravej dolnej časti.</OriginalDocumentSecurityElementsDescription>",
                       "<OriginalDocumentSecurityElementsPage>1</OriginalDocumentSecurityElementsPage>",
                       "<OriginalDocumentSecurityElementsSheet>1</OriginalDocumentSecurityElementsSheet>",
                       "<OriginalDocumentSecurityElementsPage>5</OriginalDocumentSecurityElementsPage>",
                       "<OriginalDocumentSecurityElementsSheet>3</OriginalDocumentSecurityElementsSheet>",
                       "<OriginalDocumentSecurityElementsLocation>Dole vpravo</OriginalDocumentSecurityElementsLocation>",
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
                       "<UsedDevice>Skenovanie / import do aplikácie Chevron7</UsedDevice>",
                       "<ConversionExecutionDateTime>",
                       "<ConversionRecordEvidenceNumber>https://data.gov.sk/id/egov/conversion-record/1563-231114-42</ConversionRecordEvidenceNumber>",
                       "</ConversionRecord>"] {
            XCTAssertTrue(xml.contains(marker), "Chýba fragment: \(marker)\n---\n\(xml)")
        }
    }

    private func securityDetails(_ xml: String) throws -> [XMLElement] {
        let document = try XMLDocument(xmlString: xml, options: [.nodeLoadExternalEntitiesNever])
        return try document.nodes(forXPath: "//*[local-name()='DocumentSecurityElementsDetails']").compactMap { $0 as? XMLElement }
    }

    private func validate(_ xml: String, input: AttestationClauseGenerator.Input) -> [String] {
        AttestationXMLValidator().validate(xml, context: .init(
            fingerprintSHA256Hex: input.newDocumentFingerprintSHA256Hex,
            securityElementCount: input.securityElements.count))
    }

    func testRecordSecurityDetailsHaveExactPlainTextStructure() throws {
        var input = sampleInput()
        input.securityElements[0].kind = .bindingCord
        input.securityElements[0].verbalDescription = "Červená šnúrka & uzol <zachované>"
        let xml = try AttestationClauseGenerator().generateXML(input: input, formPack: FormPackRepository.currentLegacyUnverified)
        let details = try securityDetails(xml)
        XCTAssertEqual(details.count, 2)
        let children = try XCTUnwrap(details.first?.children).compactMap { $0 as? XMLElement }
        XCTAssertEqual(children.map(\.localName), ["OriginalDocumentSecurityElementsDescription",
            "OriginalDocumentSecurityElementsPage", "OriginalDocumentSecurityElementsSheet",
            "OriginalDocumentSecurityElementsLocation", "NewDocumentSecurityElementsPage"])
        XCTAssertEqual(children[0].stringValue, "Trikolóra / viazacia šnúrka: Červená šnúrka & uzol <zachované>")
        XCTAssertEqual(children[3].stringValue, "Dole vpravo")
        XCTAssertTrue(children.allSatisfy { !($0.children ?? []).contains { $0 is XMLElement } })
        XCTAssertFalse(xml.contains("SecurityElementVerbalDescription"))
        XCTAssertTrue(validate(xml, input: input).isEmpty)
    }

    func testNonEmptyOriginalPageOrdinalKeepsPhysicalSheetAndOutputPage() throws {
        var input = sampleInput()
        input.originalNonEmptyPageIndices = [0, 2, 4]
        let xml = try AttestationClauseGenerator().generateXML(input: input, formPack: FormPackRepository.currentLegacyUnverified)
        let detail = try XCTUnwrap(securityDetails(xml).last)
        XCTAssertEqual(detail.elements(forName: "OriginalDocumentSecurityElementsPage").first?.stringValue, "3")
        XCTAssertEqual(detail.elements(forName: "OriginalDocumentSecurityElementsSheet").first?.stringValue, "3")
        XCTAssertEqual(detail.elements(forName: "NewDocumentSecurityElementsPage").first?.stringValue, "5")
    }

    func testMappedOriginalPageMustExist() throws {
        var input = sampleInput()
        input.originalNonEmptyPageIndices = [0, 2]
        XCTAssertThrowsError(try AttestationClauseGenerator().generateXML(input: input, formPack: FormPackRepository.currentLegacyUnverified)) {
            XCTAssertEqual($0 as? AttestationGenerationError, .invalidSecurityElementPage)
        }
        XCTAssertEqual(try securityDetails(AttestationClauseGenerator().generateXML(input: input)).count, 1)
    }

    func testPhysicalObservationUsesExplicitLocationAndOutputPage() throws {
        var input = sampleInput()
        input.securityElements = [SecurityElement(kind: .watermark, pageIndex: 4, boundingBox: .zero,
            confidence: 1, verbalDescription: "Overené proti svetlu", detectedByAI: false,
            observation: .physicalOriginal, originalLocation: "  Horný okraj & stred  ", newDocumentPageIndex: 7)]
        let xml = try AttestationClauseGenerator().generateXML(input: input, formPack: FormPackRepository.currentLegacyUnverified)
        let detail = try XCTUnwrap(securityDetails(xml).first)
        XCTAssertEqual(detail.elements(forName: "OriginalDocumentSecurityElementsLocation").first?.stringValue, "Horný okraj & stred")
        XCTAssertEqual(detail.elements(forName: "OriginalDocumentSecurityElementsPage").first?.stringValue, "5")
        XCTAssertEqual(detail.elements(forName: "OriginalDocumentSecurityElementsSheet").first?.stringValue, "3")
        XCTAssertEqual(detail.elements(forName: "NewDocumentSecurityElementsPage").first?.stringValue, "8")
        XCTAssertTrue(validate(xml, input: input).isEmpty)
    }

    func testIncompletePhysicalObservationThrowsAndLegacyOmitsIt() throws {
        for (location, outputPage) in [("Horný okraj", nil), ("Horný okraj", -1), (" \n ", 0)] as [(String, Int?)] {
            var input = sampleInput()
            input.securityElements = [SecurityElement(kind: .watermark, pageIndex: 0, boundingBox: .zero,
                confidence: 1, detectedByAI: false, observation: .physicalOriginal,
                originalLocation: location, newDocumentPageIndex: outputPage)]
            XCTAssertThrowsError(try AttestationClauseGenerator().generateXML(input: input, formPack: FormPackRepository.currentLegacyUnverified)) {
                XCTAssertEqual($0 as? AttestationGenerationError, .incompletePhysicalSecurityElement)
            }
            let xml = AttestationClauseGenerator().generateXML(input: input)
            XCTAssertTrue(try securityDetails(xml).isEmpty)
            XCTAssertTrue(validate(xml, input: input).contains { $0.contains("Počet prvkov") })
        }
    }

    func testSecurityPageIndicesMustFitRecordRange() {
        for page in [-1, 99_999, Int.max] {
            var input = sampleInput()
            input.securityElements[0].pageIndex = page
            XCTAssertThrowsError(try AttestationClauseGenerator().generateXML(input: input, formPack: FormPackRepository.currentLegacyUnverified)) {
                XCTAssertEqual($0 as? AttestationGenerationError, .invalidSecurityElementPage)
            }
        }
    }

    func testValidatorAcceptsNoSecurityElementsWhenExpectedCountIsZero() {
        var input = sampleInput()
        input.securityElements = []
        let xml = AttestationClauseGenerator().generateXML(input: input)
        XCTAssertTrue(validate(xml, input: input).isEmpty)
    }

    func testValidatorRejectsMissingEmptyNestedAndUnexpectedSecurityFields() throws {
        let input = sampleInput()
        let xml = AttestationClauseGenerator().generateXML(input: input)
        let fields = ["OriginalDocumentSecurityElementsDescription", "OriginalDocumentSecurityElementsPage",
                      "OriginalDocumentSecurityElementsSheet", "OriginalDocumentSecurityElementsLocation", "NewDocumentSecurityElementsPage"]
        for field in fields {
            for mutation in ["missing", "empty", "nested"] {
                let document = try XMLDocument(xmlString: xml, options: [.nodeLoadExternalEntitiesNever])
                let node = try XCTUnwrap(document.nodes(forXPath: "//*[local-name()='DocumentSecurityElementsDetails']/*[local-name()='\(field)']").first as? XMLElement)
                switch mutation {
                case "missing": node.detach()
                case "empty": node.stringValue = " \n "
                default:
                    node.stringValue = ""
                    node.addChild(XMLElement(name: "Codelist", stringValue: "1"))
                }
                XCTAssertFalse(validate(document.xmlString, input: input).isEmpty, "\(mutation) \(field)")
            }
        }
        let unexpected = xml.replacingOccurrences(of: "</DocumentSecurityElementsDetails>",
            with: "<SecurityElementVerbalDescription>text</SecurityElementVerbalDescription></DocumentSecurityElementsDetails>")
        XCTAssertTrue(validate(unexpected, input: input).contains { $0.contains("poradie") })
        let document = try XMLDocument(xmlString: xml, options: [.nodeLoadExternalEntitiesNever])
        let first = try XCTUnwrap(document.nodes(forXPath: "//*[local-name()='DocumentSecurityElementsDetails']").first as? XMLElement)
        let location = try XCTUnwrap(first.elements(forName: "OriginalDocumentSecurityElementsLocation").first)
        location.detach()
        first.insertChild(location, at: 0)
        XCTAssertTrue(validate(document.xmlString, input: input).contains { $0.contains("poradie") })
    }

    func testValidatorRejectsInvalidSecurityPageAndSheetNumbers() {
        let input = sampleInput()
        let xml = AttestationClauseGenerator().generateXML(input: input)
        for field in ["OriginalDocumentSecurityElementsPage", "OriginalDocumentSecurityElementsSheet", "NewDocumentSecurityElementsPage"] {
            for value in ["0", "-1", "100000", "1.5", "+1"] {
                let invalid = xml.replacingOccurrences(of: "<\(field)>1</\(field)>", with: "<\(field)>\(value)</\(field)>")
                XCTAssertTrue(validate(invalid, input: input).contains { $0.contains(field) }, "\(field)=\(value)")
            }
        }
    }

    func testSecurityFragmentsValidateAgainstExtractedOfficialRecordSchema() throws {
        let executable = URL(fileURLWithPath: "/usr/bin/xmllint")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw XCTSkip("xmllint is needed to validate the extracted official XSD fragment.")
        }
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let schema = package.appendingPathComponent("docs/reference/security-elements/record-1.0-security-fragment.xsd")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var input = sampleInput()
        input.securityElements.append(SecurityElement(kind: .watermark, pageIndex: 4, boundingBox: .zero,
            confidence: 1, detectedByAI: false, observation: .physicalOriginal,
            originalLocation: "Celá plocha listu", newDocumentPageIndex: 4))
        let xml = try AttestationClauseGenerator().generateXML(input: input, formPack: FormPackRepository.currentLegacyUnverified)
        let details = try securityDetails(xml)
        for (index, detail) in details.enumerated() {
            // Give the extracted fragment its inherited official record namespace.
            detail.addNamespace(XMLNode.namespace(withName: "", stringValue: AttestationXMLConstants.namespaceP2E) as! XMLNode)
            let file = directory.appendingPathComponent("element-\(index).xml")
            try detail.xmlString.write(to: file, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = executable
            process.arguments = ["--nonet", "--noout", "--schema", schema.path, file.path]
            let stderr = Pipe()
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()
            let message = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertEqual(process.terminationStatus, 0, message)
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
