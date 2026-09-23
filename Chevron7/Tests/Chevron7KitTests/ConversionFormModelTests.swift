// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class ConversionFormModelTests: XCTestCase {
    static let fingerprintHex = String(repeating: "ab", count: 32)

    static func attestation(at time: Date = Date(timeIntervalSince1970: 1_787_589_344)) -> AttestationData {
        AttestationData(
            originalDocumentName: "Brezinová_diplom",
            numberOfSheets: 1,
            nonEmptyPageCount: 1,
            paperSizeBreakdown: [.init(sizeClass: .a4Portrait, sheets: 1)],
            newDocumentName: "Brezinová_diplom.pdf",
            conversionExecutionDateTime: time,
            evidenceNumber: " 1563-260824-1 ",
            performingPerson: AdvocateProfile(fullName: "Mgr. Marián Čuprík", position: "Partner",
                                              registrationNumber: "1042", ico: "42249180",
                                              officeName: "Advokátska kancelária CHZ"))
    }

    static func scanElement(_ kind: SecurityElement.Kind = .handwrittenSignature) -> SecurityElement {
        SecurityElement(kind: kind, pageIndex: 0,
                        boundingBox: NormalizedRect(x: 0.05, y: 0.05, width: 0.1, height: 0.1),
                        confidence: 1, detectedByAI: false)
    }

    func testBuildsEveryValueFromTheZakoState() throws {
        let model = try ConversionFormModel.make(attestation: Self.attestation(),
                                                 securityElements: [Self.scanElement()],
                                                 newDocumentSHA256Hex: Self.fingerprintHex,
                                                 originalNonEmptyPageIndices: [0],
                                                 usedDevice: "Chevron7 v0.5.0")
        XCTAssertEqual(model.evidenceNumber, "1563-260824-1")
        XCTAssertEqual(model.evidenceNumberURI, "https://data.gov.sk/id/egov/conversion-record/1563-260824-1")
        XCTAssertEqual(model.originalDocumentType, "Brezinová_diplom")
        XCTAssertEqual(model.person, .init(givenName: "Marián", familyName: "Čuprík", position: "Partner",
                                           legalSubjectName: "Advokátska kancelária CHZ",
                                           legalSubjectURI: "https://data.gov.sk/id/legal-subject/42249180"))
        XCTAssertEqual(model.paperSizes, [.init(item: ZakoCodelistItem(code: "A4", skName: "Formát papiera A4"), other: nil, sheets: 1)])
        XCTAssertEqual(model.securityElements.first?.description.code, "vlastnoručný podpis")
        XCTAssertNil(model.securityElements.first?.descriptionOther)
        XCTAssertEqual(model.securityElements.first?.location.code, "Left down")
        XCTAssertEqual(model.newDocumentFormat, ZakoCodelists.pdfa2FormatItem)
        XCTAssertEqual(model.fingerprintBase64, AttestationClauseGenerator.fingerprintBase64(hex: Self.fingerprintHex))
    }

    func testConversionTimeUsesBratislavaOffset() {
        // 2026-08-24T16:35:44Z is summer time, 2026-01-15T23:30:00Z is winter time.
        XCTAssertEqual(ConversionFormModel.bratislavaDateTime(Date(timeIntervalSince1970: 1_787_589_344)),
                       "2026-08-24T18:35:44+02:00")
        XCTAssertEqual(ConversionFormModel.bratislavaDateTime(Date(timeIntervalSince1970: 1_768_519_800)),
                       "2026-01-16T00:30:00+01:00")
    }

    func testOtherKindsCarryTheirDescriptionAsOtherText() throws {
        var element = Self.scanElement(.bindingCord)
        element.verbalDescription = "trikolóra cez ľavý okraj"
        let model = try ConversionFormModel.make(attestation: Self.attestation(), securityElements: [element],
                                                 newDocumentSHA256Hex: Self.fingerprintHex,
                                                 originalNonEmptyPageIndices: [0], usedDevice: "Chevron7")
        XCTAssertEqual(model.securityElements.first?.description.code, "iný manuálny vstup")
        XCTAssertEqual(model.securityElements.first?.descriptionOther, element.descriptionForRecord)
    }

    func testPhysicalElementUsesItsCodelistLocation() throws {
        var element = Self.scanElement()
        element.observation = .physicalOriginal
        element.originalLocation = "Right down"
        element.newDocumentPageIndex = 0
        let model = try ConversionFormModel.make(attestation: Self.attestation(), securityElements: [element],
                                                 newDocumentSHA256Hex: Self.fingerprintHex,
                                                 originalNonEmptyPageIndices: [0], usedDevice: "Chevron7")
        XCTAssertEqual(model.securityElements.first?.location, ZakoCodelistItem(code: "Right down", skName: "Vpravo dole"))
    }

    func testPhysicalElementWithFreeTextLocationIsRefused() {
        var element = Self.scanElement()
        element.observation = .physicalOriginal
        element.originalLocation = "vpravo dole pri podpise"
        element.newDocumentPageIndex = 0
        XCTAssertThrowsError(try ConversionFormModel.make(attestation: Self.attestation(), securityElements: [element],
                                                          newDocumentSHA256Hex: Self.fingerprintHex,
                                                          originalNonEmptyPageIndices: [0], usedDevice: "Chevron7")) {
            XCTAssertEqual($0 as? AttestationGenerationError, .invalidOriginalLocation)
        }
    }

    func testMissingEvidenceNumberAndBadFingerprintAreRefused() {
        var data = Self.attestation()
        data.evidenceNumber = "  "
        XCTAssertThrowsError(try ConversionFormModel.make(attestation: data, securityElements: [],
                                                          newDocumentSHA256Hex: Self.fingerprintHex,
                                                          originalNonEmptyPageIndices: nil, usedDevice: "Chevron7")) {
            XCTAssertEqual($0 as? AttestationGenerationError, .missingEvidenceNumber)
        }
        XCTAssertThrowsError(try ConversionFormModel.make(attestation: Self.attestation(), securityElements: [],
                                                          newDocumentSHA256Hex: "xyz",
                                                          originalNonEmptyPageIndices: nil, usedDevice: "Chevron7")) {
            XCTAssertEqual($0 as? AttestationGenerationError, .invalidFingerprint)
        }
    }

    func testMissingPaperBreakdownFallsBackToA4() throws {
        var data = Self.attestation()
        data.paperSizeBreakdown = []
        data.numberOfSheets = 3
        let model = try ConversionFormModel.make(attestation: data, securityElements: [],
                                                 newDocumentSHA256Hex: Self.fingerprintHex,
                                                 originalNonEmptyPageIndices: nil, usedDevice: "Chevron7")
        XCTAssertEqual(model.paperSizes.map(\.sheets), [3])
        XCTAssertEqual(model.paperSizes.first?.item.code, "A4")
    }

    func testOneWordPerformerNameIsRefused() {
        for fullName in ["Novák", "JUDr. Novák"] {
            var data = Self.attestation()
            data.performingPerson.fullName = fullName
            XCTAssertThrowsError(try ConversionFormModel.make(attestation: data, securityElements: [],
                                                              newDocumentSHA256Hex: Self.fingerprintHex,
                                                              originalNonEmptyPageIndices: nil, usedDevice: "Chevron7")) {
                XCTAssertEqual($0 as? AttestationGenerationError, .incompletePersonName, "for \"\(fullName)\"")
            }
        }
    }

    func testPostNominalSuffixIsNotPartOfTheFamilyName() throws {
        var data = Self.attestation()
        data.performingPerson.fullName = "JUDr. Ján Novák, PhD."
        let model = try ConversionFormModel.make(attestation: data, securityElements: [],
                                                 newDocumentSHA256Hex: Self.fingerprintHex,
                                                 originalNonEmptyPageIndices: nil, usedDevice: "Chevron7")
        XCTAssertEqual(model.person.givenName, "Ján")
        XCTAssertEqual(model.person.familyName, "Novák")
    }
}
