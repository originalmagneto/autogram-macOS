// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class ConversionRecordRendererTests: XCTestCase {
    override func setUpWithError() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/xmllint") else {
            throw XCTSkip("xmllint is needed for schema validation.")
        }
    }

    private func model(_ attestation: AttestationData = ConversionFormModelTests.attestation(),
                       elements: [SecurityElement] = [ConversionFormModelTests.scanElement()]) throws -> ConversionFormModel {
        try ConversionFormModel.make(attestation: attestation, securityElements: elements,
                                     newDocumentSHA256Hex: ConversionFormModelTests.fingerprintHex,
                                     originalNonEmptyPageIndices: [0], usedDevice: "Chevron7 v0.7.0")
    }

    private func elementOrder(_ xml: String) throws -> [String] {
        let document = try XMLDocument(xmlString: xml)
        return (document.rootElement()?.children ?? []).compactMap { $0.localName }
    }

    func testRecordValidatesAndFollowsTheAcceptedRecordShape() throws {
        let xml = ConversionRecordRenderer().render(try model())
        XCTAssertNoThrow(try FormSchemaValidator().validate(Data(xml.utf8), against: .record_1_0))
        XCTAssertEqual(try elementOrder(xml), ["OriginalDocumentInfo", "NewDocumentInfo", "ConversionRecordEvidenceNumber",
                                               "UsedDevice", "ConversionExecutionDateTime", "PersonPerformingConversion"])
        XCTAssertTrue(xml.contains("<ConversionRecordEvidenceNumber>1563-260824-1</ConversionRecordEvidenceNumber>"))
        XCTAssertTrue(xml.contains("<OriginalDocumentName>Brezinová_diplom</OriginalDocumentName><OriginalDocumentOrder>1</OriginalDocumentOrder><OriginalDocumentType>Brezinová_diplom</OriginalDocumentType>"))
        XCTAssertTrue(xml.contains("<PaperSize>A4</PaperSize>"))
        XCTAssertTrue(xml.contains("<OriginalDocumentSecurityElementsDescription>vlastnoručný podpis</OriginalDocumentSecurityElementsDescription>"))
        XCTAssertTrue(xml.contains("<OriginalDocumentSecurityElementsLocation>Left down</OriginalDocumentSecurityElementsLocation>"))
        XCTAssertTrue(xml.contains("<NewDocumentFormat>PDF/A-2</NewDocumentFormat>"))
        XCTAssertTrue(xml.contains("<ElectronicFingerprintCalculationMethod>SHA-256</ElectronicFingerprintCalculationMethod>"))
        XCTAssertTrue(xml.contains("<UsedDevice>Chevron7 v0.7.0</UsedDevice>"))
        XCTAssertTrue(xml.contains("<ConversionExecutionDateTime>2026-08-24T18:35:44+02:00</ConversionExecutionDateTime>"))
        XCTAssertTrue(xml.contains("<IdentifierValue>https://data.gov.sk/id/legal-subject/42249180</IdentifierValue>"))
        XCTAssertFalse(xml.contains("<Codelist><CodelistCode>12"), "record uses plain strings, not codelists")
    }

    func testOtherKindsLetterPaperAndPhysicalElementsValidate() throws {
        var data = ConversionFormModelTests.attestation()
        data.paperSizeBreakdown = [.init(sizeClass: .letterPortrait, sheets: 1)]
        var other = ConversionFormModelTests.scanElement(.bindingCord)
        other.verbalDescription = "trikolóra"
        var physical = ConversionFormModelTests.scanElement(.embossedSeal)
        physical.observation = .physicalOriginal
        physical.originalLocation = "Down edge"
        physical.newDocumentPageIndex = 0
        let xml = ConversionRecordRenderer().render(try model(data, elements: [other, physical]))
        XCTAssertNoThrow(try FormSchemaValidator().validate(Data(xml.utf8), against: .record_1_0))
        XCTAssertTrue(xml.contains("<PaperSize>Letter</PaperSize>"))
        XCTAssertTrue(xml.contains("trikolóra"))
        XCTAssertTrue(xml.contains("<OriginalDocumentSecurityElementsLocation>Down edge</OriginalDocumentSecurityElementsLocation>"))
    }

    func testIcoWithElevenDigitsIsOmittedBecauseTheRecordAllowsOnlyEightOrTwelve() throws {
        var data = ConversionFormModelTests.attestation()
        data.performingPerson.ico = "12345678901"
        let xml = ConversionRecordRenderer().render(try model(data))
        XCTAssertNoThrow(try FormSchemaValidator().validate(Data(xml.utf8), against: .record_1_0))
        XCTAssertFalse(xml.contains("<ID>"))
    }
}
