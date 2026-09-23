// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class ZakoCodelistsTests: XCTestCase {
    func testCentreUsesOfficialMidCodeAndNamesFollowTheCodelist() {
        func element(x: Double, y: Double) -> SecurityElement {
            SecurityElement(kind: .handwrittenSignature, pageIndex: 0,
                            boundingBox: NormalizedRect(x: x - 0.05, y: y - 0.05, width: 0.1, height: 0.1),
                            confidence: 1, detectedByAI: false)
        }
        XCTAssertEqual(element(x: 0.5, y: 0.5).locationCodelist11Item, ZakoCodelistItem(code: "Mid", skName: "Uprostred"))
        XCTAssertEqual(element(x: 0.1, y: 0.1).locationCodelist11Item, ZakoCodelistItem(code: "Left down", skName: "Vľavo dole"))
        XCTAssertEqual(element(x: 0.9, y: 0.9).locationCodelist11Item, ZakoCodelistItem(code: "Right up", skName: "Vpravo hore"))
        for item in [element(x: 0.5, y: 0.5), element(x: 0.1, y: 0.1), element(x: 0.9, y: 0.1)].map(\.locationCodelist11Item) {
            XCTAssertEqual(ZakoCodelists.locationItem(code: item.code), item)
        }
    }

    func testLocationListIsTheOfficialCodelist() {
        XCTAssertEqual(ZakoCodelists.locationItems.map(\.code),
                       ["Down", "Up", "Down edge", "Up edge", "Left edge", "Right edge", "Mid",
                        "Left", "Left down", "Left up", "Right", "Right down", "Right up"])
        XCTAssertNil(ZakoCodelists.locationItem(code: "vpravo dole pri podpise"))
    }

    func testLegalSubjectURI() {
        XCTAssertEqual(ZakoCodelists.legalSubjectURI(ico: " 42249180 "), "https://data.gov.sk/id/legal-subject/42249180")
        XCTAssertNil(ZakoCodelists.legalSubjectURI(ico: ""))
    }

    func testLegalSubjectURIRejectsNonDigits() {
        XCTAssertNil(ZakoCodelists.legalSubjectURI(ico: "42 249 180"))
        XCTAssertNil(ZakoCodelists.legalSubjectURI(ico: "SK42249180"))
        XCTAssertNil(ZakoCodelists.legalSubjectURI(ico: "1234567"))
    }

    func testClausePaperSize() {
        XCTAssertEqual(ZakoCodelists.clausePaperSize(for: .a4Landscape).item.code, "A4")
        XCTAssertNil(ZakoCodelists.clausePaperSize(for: .a3Portrait).other)
        let letter = ZakoCodelists.clausePaperSize(for: .letterPortrait)
        XCTAssertEqual(letter.item, ZakoCodelistItem(code: "Iny", skName: "Iný"))
        XCTAssertEqual(letter.other, "Letter")
        XCTAssertEqual(ZakoCodelists.clausePaperSize(for: .unknown).other, "neurčený")
    }
}
