// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest

final class ZakoClauseRouteTests: XCTestCase {
    private var source: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/Chevron7App/ZakoSessionStore.swift")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    func testAuthorizationSignsTheClauseAsADataObjectAndEmbedsNothing() throws {
        let text = try source
        XCTAssertTrue(text.contains("ZakoClauseDeliveryBuilder()"))
        XCTAssertTrue(text.contains("signsExtraFilesAsDataObjects: true"))
        XCTAssertFalse(text.contains("osvedcovacia-dolozka.xml"), "the PDF/A must not embed XML after its fingerprint")
        XCTAssertFalse(text.contains("dolozkaXML: Data(xml.utf8)"), "the clause slot must hold the clause XDC, not the record")
    }
}
