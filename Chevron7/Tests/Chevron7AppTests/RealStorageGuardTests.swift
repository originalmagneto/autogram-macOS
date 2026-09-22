// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Chevron7Identity
import Chevron7TestSupport
import XCTest

/// `RealStorageGuard` installs itself when the test bundle loads; these pin that and the
/// folders it watches. The Kit target has the same checks.
final class RealStorageGuardTests: XCTestCase {
    func testGuardIsInstalledBeforeTestsRun() {
        XCTAssertTrue(RealStorageGuard.isInstalled)
    }

    func testGuardWatchesTheProductDataRoots() {
        XCTAssertEqual(RealStorageGuard.watchedRoots,
                       [ProductIdentity.applicationSupportDirectory(), ProductIdentity.cachesDirectory()])
    }
}
