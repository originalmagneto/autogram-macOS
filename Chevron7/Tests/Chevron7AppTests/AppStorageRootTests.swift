// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Chevron7Kit
import XCTest
@testable import Chevron7App

/// Every folder the app keeps files in hangs off `AppSettingsStore.storageRoot`, so a
/// test that passes a temporary root cannot reach the user's evidence register.
@MainActor
final class AppStorageRootTests: XCTestCase {
    func testStorageFoldersHangOffTheInjectedRoot() async {
        let settingsStore = makeSettingsStore()
        let root = settingsStore.storageRoot
        XCTAssertEqual(settingsStore.outputDirectory, root.appendingPathComponent("Output", isDirectory: true))
        XCTAssertEqual(settingsStore.templatesDirectory, root.appendingPathComponent("Templates", isDirectory: true))
        XCTAssertEqual(settingsStore.signaturesDirectory, root.appendingPathComponent("Signatures", isDirectory: true))
        let bankDirectory = await settingsStore.exampleBank.directory
        XCTAssertEqual(bankDirectory, root.appendingPathComponent("VisionBank", isDirectory: true))
        XCTAssertEqual(bankDirectory.lastPathComponent, ExampleBank.defaultDirectory.lastPathComponent)

        let zakoBankDirectory = await ZakoSessionStore(settingsStore: settingsStore).exampleBank.directory
        XCTAssertEqual(zakoBankDirectory, bankDirectory)
    }

    func testEvidenceRegisterIsWrittenUnderTheInjectedRoot() {
        let settingsStore = makeSettingsStore()
        settingsStore.evidenceStore.upsert(EvidenceRecord(
            status: .draft,
            direction: .paperToElectronic,
            originalName: "Zmluva",
            newDocumentName: "Zmluva PDF/A",
            evidenceNumber: nil,
            fingerprintSHA256Hex: String(repeating: "ab", count: 32),
            attestationXML: "<ConversionRecord/>",
            conversionTime: Date(),
            performingPersonName: "Test",
            securityElementCount: 0,
            totalPages: 1,
            totalSheets: 1))

        let register = settingsStore.storageRoot.appendingPathComponent("Evidence/register.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: register.path))
    }
}
