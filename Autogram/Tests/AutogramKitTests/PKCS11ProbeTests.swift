import XCTest
@testable import AutogramKit

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
