// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7App

final class AppLaunchModeTests: XCTestCase {
    func testWebSigningArgumentSelectsBackgroundMode() {
        XCTAssertEqual(AppLaunchMode.from(arguments: ["/Applications/Chevron7.app/Contents/MacOS/Chevron7", "--web-signing"]), .webSigning)
    }

    func testOrdinaryLaunchIsNormal() {
        XCTAssertEqual(AppLaunchMode.from(arguments: ["/Applications/Chevron7.app/Contents/MacOS/Chevron7"]), .normal)
        XCTAssertEqual(AppLaunchMode.from(arguments: ["Chevron7", "-NSDocumentRevisionsDebugMode", "YES"]), .normal)
    }
}
