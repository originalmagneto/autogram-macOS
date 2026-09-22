// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class TokenIdentityScannerTests: XCTestCase {
    func testScanAllDoesNotHang() {
        let finished = expectation(description: "scanAll")
        DispatchQueue.global().async {
            _ = KeychainIdentityScanner.scanAll()
            finished.fulfill()
        }
        wait(for: [finished], timeout: 8)
    }

    func testConnectedTokenIDsExcludeApple() {
        for tokenID in KeychainIdentityScanner.connectedTokenIDs() {
            let lowered = tokenID.lowercased()
            XCTAssertFalse(lowered.hasPrefix("apple."))
            XCTAssertFalse(lowered.hasPrefix("com.apple"))
        }
    }
}
