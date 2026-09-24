// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class AdvocateProfilePreviewTests: XCTestCase {
    func testFunctionIsShownOnce() {
        let typedWithFunction = AdvocateProfile(fullName: "Mgr. Marián Čuprík, advokát",
                                                position: "advokát", registrationNumber: "8718")
        XCTAssertEqual(typedWithFunction.clausePreviewLine, "Mgr. Marián Čuprík, advokát, ev. č. SAK: 8718")

        let nameOnly = AdvocateProfile(fullName: "Mgr. Marián Čuprík", position: "advokát",
                                       registrationNumber: "8718")
        XCTAssertEqual(nameOnly.clausePreviewLine, "Mgr. Marián Čuprík, advokát, ev. č. SAK: 8718")
    }

    /// The office is what the clause names as the legal subject, so the preview shows it.
    func testOfficeIsShownWhenItDiffersFromTheName() {
        let withOffice = AdvocateProfile(fullName: "Mgr. Marián Čuprík", position: "advokát",
                                         registrationNumber: "8718",
                                         officeName: "SKALLARS Law | Advokáti CHZ")
        XCTAssertEqual(withOffice.clausePreviewLine,
                       "Mgr. Marián Čuprík, advokát, ev. č. SAK: 8718 (SKALLARS Law | Advokáti CHZ)")

        let officeIsTheName = AdvocateProfile(fullName: "Mgr. Marián Čuprík, advokát", position: "advokát",
                                              registrationNumber: "8718",
                                              officeName: "Mgr. Marián Čuprík, advokát")
        XCTAssertEqual(officeIsTheName.clausePreviewLine, "Mgr. Marián Čuprík, advokát, ev. č. SAK: 8718")
    }

    func testPlaceholdersForAnEmptyProfile() {
        XCTAssertEqual(AdvocateProfile(position: "").clausePreviewLine, "JUDr. Meno Priezvisko, ev. č. SAK: XXXX")
    }
}

final class ReadableDocumentNameTests: XCTestCase {
    /// The name from the reported screenshot, as the web saved it.
    func testURLEncodedDecomposedNameBecomesReadable() {
        let saved = "priloha_1203905720_0_2023-06-15_z%cc%8ca%cc%81dost_o_pozastaveni%cc%81_vy%cc%81konu_advokacie_(C%cc%8cAK)"
        XCTAssertEqual(ConversionOutputNaming.readableName(saved),
                       "priloha_1203905720_0_2023-06-15_žádost_o_pozastavení_výkonu_advokacie_(ČAK)"
                           .precomposedStringWithCanonicalMapping)
    }

    func testOrdinaryAndUndecodableNamesStay() {
        XCTAssertEqual(ConversionOutputNaming.readableName("Zmluva o dielo"), "Zmluva o dielo")
        XCTAssertEqual(ConversionOutputNaming.readableName("zľava 100%"), "zľava 100%")
    }
}
