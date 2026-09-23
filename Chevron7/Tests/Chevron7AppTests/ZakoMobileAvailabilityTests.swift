// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation
import XCTest
import Chevron7Kit
@testable import Chevron7App

@MainActor
final class ZakoMobileAvailabilityTests: XCTestCase {
    func testMobileZakoIsRefusedOutsideDemo() async {
        let (settingsStore, _) = makeTestModeSettingsStore()
        settingsStore.settings.mobileSigningEnabled = true
        let store = ZakoSessionStore(settingsStore: settingsStore)

        XCTAssertFalse(store.isMobileSigningAvailable)
        await store.authorizeAndSign(viaMobile: true)
        XCTAssertEqual(store.lastError, ZakoSessionStore.mobileOutsideDemoMessage)
    }

    /// Demo EZZK with a real (non-demo) signing provider is the one combination this
    /// guard allows: `isMobileSigningAvailable` checks the EZZK mode, not the signing
    /// provider, so a real card in Demo still offers the phone.
    func testMobileZakoIsOfferedInDemoWithRealSigningProvider() {
        let settingsStore = makeSettingsStore()
        settingsStore.ezzkAccountController.setMode(.demo)
        settingsStore.settings.mobileSigningEnabled = true
        settingsStore.useRealSigningProvider(StubSigningProvider())
        let store = ZakoSessionStore(settingsStore: settingsStore)

        XCTAssertTrue(store.isMobileSigningAvailable)
    }

    /// Builds a settings store on an EZZK controller already in Test mode, with in-memory
    /// credentials and a transport with no replies, exactly as
    /// `ZakoEvidenceNumberTests.testNumberFetchedInDemoIsRefusedAfterSwitchingToTest` does
    /// for its own controller: no Keychain, no network.
    private func makeTestModeSettingsStore() -> (AppSettingsStore, EZZKAccountController) {
        let transport = ScriptedTransport([])
        let controller = EZZKAccountController(mode: .test, credentialStore: MemoryCredentialStore(),
                                               transportFactory: { _ in transport })
        let settingsStore = makeSettingsStore(ezzkAccountController: controller)
        return (settingsStore, controller)
    }
}

/// Minimal non-demo signing provider: only what `QualifiedSigningProviding` requires with
/// no default implementation. Nothing in these tests calls `sign` or `availableIdentities`.
private final class StubSigningProvider: QualifiedSigningProviding, @unchecked Sendable {
    func availableIdentities() async -> [SigningIdentityInfo] { [] }

    func sign(_ request: SigningRequest) async throws -> SignedConversionResult {
        SignedConversionResult(pdfData: Data(), asicData: nil, signedAt: Date(),
                               signatureLabel: "stub", isLegallyBinding: false)
    }
}
