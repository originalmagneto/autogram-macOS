import Foundation
import XCTest
import AutogramKit
@testable import AutogramApp

@MainActor
final class ZakoEvidenceNumberTests: XCTestCase {
    func testFetchedNumberRecordsItsAllocationTime() async {
        let settingsStore = AppSettingsStore()
        // Never reach EZZK from a unit test, whatever the developer selected in the app.
        settingsStore.ezzkAccountController.setMode(.demo)
        let store = ZakoSessionStore(settingsStore: settingsStore)

        await store.fetchEvidenceNumber()

        XCTAssertNotNil(store.attestation.evidenceNumber)
        XCTAssertNotNil(store.attestation.evidenceNumberAllocatedAt)
    }

    func testIdentityWarningIsSilentInDemoMode() {
        let settingsStore = AppSettingsStore()
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
        let settingsStore = AppSettingsStore()
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
