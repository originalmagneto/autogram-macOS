// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class ConversionCertificateRendererTests: XCTestCase {
    private let renderer = ConversionCertificateRenderer()

    override func setUpWithError() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/xmllint") else {
            throw XCTSkip("xmllint is needed for schema validation.")
        }
    }

    private func model(_ attestation: AttestationData = ConversionFormModelTests.attestation(),
                       elements: [SecurityElement] = [ConversionFormModelTests.scanElement()]) throws -> ConversionFormModel {
        try ConversionFormModel.make(attestation: attestation, securityElements: elements,
                                     newDocumentSHA256Hex: ConversionFormModelTests.fingerprintHex,
                                     originalNonEmptyPageIndices: [0], usedDevice: "Chevron7 v0.5.0")
    }

    private func assertValid(_ xml: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNoThrow(try FormSchemaValidator().validate(Data(xml.utf8), against: .clause_1_3), file: file, line: line)
    }

    func testClauseValidatesAgainstTheOfficialSchema() throws {
        let xml = renderer.render(try model())
        assertValid(xml)
        XCTAssertTrue(xml.hasPrefix("<ConversionCertificateOfPaperToElectronicDocument xmlns=\"\(OfficialForm.clause_1_3.namespace)\">"))
        XCTAssertTrue(xml.contains("<ConversionRecordEvidenceNumber>https://data.gov.sk/id/egov/conversion-record/1563-260824-1</ConversionRecordEvidenceNumber>"))
        XCTAssertTrue(xml.contains("<ConversionExecutionDateTime>2026-08-24T18:35:44+02:00</ConversionExecutionDateTime>"))
        XCTAssertTrue(xml.contains("<CodelistCode>53</CodelistCode><CodelistItem><ItemCode>PDFA2</ItemCode>"))
        XCTAssertTrue(xml.contains("<IdentifierValue>https://data.gov.sk/id/legal-subject/42249180</IdentifierValue>"))
        XCTAssertFalse(xml.contains("UsedDevice"), "the clause has no UsedDevice element")
    }

    func testClauseWithoutValidICOValidates() throws {
        var data = ConversionFormModelTests.attestation()
        data.performingPerson.ico = "SK 4224"
        data.performingPerson.officeName = ""
        let xml = renderer.render(try model(data))
        assertValid(xml)
        XCTAssertFalse(xml.contains("<ID>"))
        XCTAssertTrue(xml.contains("<LegalSubject><Name>Mgr. Marián Čuprík</Name></LegalSubject>"))
    }

    func testLetterAndUnknownPaperValidate() throws {
        var data = ConversionFormModelTests.attestation()
        data.paperSizeBreakdown = [.init(sizeClass: .letterPortrait, sheets: 1), .init(sizeClass: .unknown, sheets: 2)]
        let xml = renderer.render(try model(data))
        assertValid(xml)
        XCTAssertTrue(xml.contains("<PaperSizeOther>Letter</PaperSizeOther>"))
    }

    func testOtherElementAndPhysicalElementValidate() throws {
        var other = ConversionFormModelTests.scanElement(.bindingCord)
        other.verbalDescription = "trikolóra"
        var physical = ConversionFormModelTests.scanElement(.embossedSeal)
        physical.observation = .physicalOriginal
        physical.originalLocation = "Down edge"
        physical.newDocumentPageIndex = 0
        let xml = renderer.render(try model(elements: [other, physical]))
        assertValid(xml)
        XCTAssertTrue(xml.contains("<OriginalDocumentSecurityElementsDescriptionOther>"))
        XCTAssertTrue(xml.contains("<ItemCode>Down edge</ItemCode>"))
    }

    func testSpecialCharactersAreEscaped() throws {
        var data = ConversionFormModelTests.attestation()
        data.originalDocumentName = "Zmluva \"A\" & <B>"
        data.performingPerson.officeName = "Čuprík & partneri"
        let xml = renderer.render(try model(data))
        assertValid(xml)
        XCTAssertTrue(xml.contains("Zmluva &quot;A&quot; &amp; &lt;B&gt;"))
    }
}
