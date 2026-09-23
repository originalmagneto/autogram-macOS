// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7App

/// A developer's Mac can have EZZK Test mode saved with a real Keychain password
/// (`AppSettings.load()` reads the real, saved settings). `makeSettingsStore()` must never let
/// that leak into a controller that could read or write the real Keychain or reach the network.
@MainActor
final class TestSettingsStoreTests: XCTestCase {
    func testDefaultTestSettingsStoreNeverTouchesTheRealKeychain() {
        let settingsStore = makeSettingsStore()

        settingsStore.ezzkAccountController.setMode(.test)

        XCTAssertEqual(settingsStore.ezzkAccountController.storedLogin, "")
        XCTAssertTrue(settingsStore.ezzkAccountController.credentialStore is MemoryCredentialStore)
    }
}
