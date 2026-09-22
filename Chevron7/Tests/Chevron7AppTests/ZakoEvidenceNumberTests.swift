// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation
import XCTest
import Chevron7Kit
@testable import Chevron7App

@MainActor
final class ZakoEvidenceNumberTests: XCTestCase {
    func testFetchedNumberRecordsItsAllocationTime() async {
        let settingsStore = makeSettingsStore()
        // Never reach EZZK from a unit test, whatever the developer selected in the app.
        settingsStore.ezzkAccountController.setMode(.demo)
        let store = ZakoSessionStore(settingsStore: settingsStore)

        await store.fetchEvidenceNumber()

        XCTAssertNotNil(store.attestation.evidenceNumber)
        XCTAssertNotNil(store.attestation.evidenceNumberAllocatedAt)
        XCTAssertEqual(store.attestation.evidenceNumberMode, .demo)
    }

    /// A demo number must never reach a clause signed for EZZK. `authorizeAndSign` refuses it
    /// before any EZZK call; with no document loaded nothing past that check could run anyway.
    func testNumberFetchedInDemoIsRefusedAfterSwitchingToTest() async {
        // In-memory credentials and a transport with no replies: no Keychain, no network.
        let transport = ScriptedTransport([])
        let controller = EZZKAccountController(mode: .demo, credentialStore: MemoryCredentialStore(),
                                               transportFactory: { _ in transport })
        let settingsStore = makeSettingsStore(ezzkAccountController: controller)
        let store = ZakoSessionStore(settingsStore: settingsStore)
        await store.fetchEvidenceNumber()
        XCTAssertNotNil(store.attestation.evidenceNumber)
        XCTAssertEqual(store.attestation.evidenceNumberMode, .demo)
        XCTAssertNil(store.evidenceNumberModeError)

        controller.setMode(.test)

        let refusal = EZZKError.evidenceNumberFromOtherMode.errorDescription
        XCTAssertNotNil(refusal)
        XCTAssertEqual(store.evidenceNumberModeError, refusal)
        await store.authorizeAndSign()
        XCTAssertEqual(store.evidenceNumberError, refusal)
        XCTAssertNil(store.result)
        XCTAssertNotEqual(store.step, .done)
        XCTAssertEqual(transport.requestCount, 0)
    }

    func testIdentityWarningIsSilentInDemoMode() {
        let settingsStore = makeSettingsStore()
        let original = settingsStore.settings
        defer { settingsStore.settings = original }
        settingsStore.ezzkAccountController.setMode(.demo)
        settingsStore.settings.ezzkPersonName = "Advokát Test"
        settingsStore.settings.ezzkICO = "22222222"
        let store = ZakoSessionStore(settingsStore: settingsStore)
        store.attestation.performingPerson = AdvocateProfile(fullName: "Iná osoba", ico: "11111111")

        XCTAssertNil(store.ezzkIdentityWarning)
    }

    func testIdentityWarningIsShownOutsideDemoModeOnMismatch() {
        let settingsStore = makeSettingsStore()
        let original = settingsStore.settings
        defer { settingsStore.settings = original }
        settingsStore.ezzkAccountController.setMode(.test)
        settingsStore.settings.ezzkPersonName = "Advokát Test"
        settingsStore.settings.ezzkICO = "22222222"
        let store = ZakoSessionStore(settingsStore: settingsStore)
        store.attestation.performingPerson = AdvocateProfile(fullName: "Iná osoba", ico: "11111111")

        XCTAssertNotNil(store.ezzkIdentityWarning)
    }
}
