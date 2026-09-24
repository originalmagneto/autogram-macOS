// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Chevron7Kit
import XCTest
@testable import Chevron7App

/// The app follows `EZZKProductionPolicy` in the Register, ZaKo and the status checker.
/// Every controller here passes its policy explicitly: no test reads the developer's real
/// defaults to decide production.
@MainActor
final class EZZKProductionPolicyAppTests: XCTestCase {
    private func productionRow(status: EvidenceRecord.Status) -> EvidenceRecord {
        var row = EvidenceRecord(status: status, direction: .paperToElectronic,
                                 originalName: "Zmluva", newDocumentName: "Zmluva.pdf",
                                 evidenceNumber: "260924-P1", fingerprintSHA256Hex: "ab", attestationXML: "<x/>",
                                 conversionTime: Date(), performingPersonName: "JUDr. Test Testovací",
                                 securityElementCount: 0, totalPages: 1, totalSheets: 1, ezzkMode: .production,
                                 evidenceNumberAllocatedAt: Date())
        row.recordContainerPath = "records/x.asice"
        return row
    }

    func testRegisterOffersProductionActionsOnlyWhenAllowed() {
        let queued = productionRow(status: .queuedForSubmission)
        let refused = EvidenceRegisterDetail.actions(for: queued, currentMode: .production)
        XCTAssertFalse(refused.canSend)
        XCTAssertEqual(refused.note, EZZKError.submissionUnavailable.errorDescription)
        let allowed = EvidenceRegisterDetail.actions(for: queued, currentMode: .production, productionAllowed: true)
        XCTAssertTrue(allowed.canSend)

        let accepted = productionRow(status: .acceptedForProcessing)
        XCTAssertFalse(EvidenceRegisterDetail.actions(for: accepted, currentMode: .production).canVerify)
        XCTAssertTrue(EvidenceRegisterDetail.actions(for: accepted, currentMode: .production,
                                                     productionAllowed: true).canVerify)
    }

    func testZakoDoneOffersProductionActionsOnlyWhenAllowed() {
        let queued = productionRow(status: .queuedForSubmission)
        let refused = ZakoDonePresentation(record: queued, lastError: nil, lastErrorStatus: nil,
                                           nextStatusCheck: nil, now: Date(), currentMode: .production)
        XCTAssertEqual(refused.action, .none)
        XCTAssertTrue(refused.lines.contains(EZZKError.submissionUnavailable.errorDescription ?? "-"))
        let allowed = ZakoDonePresentation(record: queued, lastError: nil, lastErrorStatus: nil,
                                           nextStatusCheck: nil, now: Date(), currentMode: .production,
                                           productionAllowed: true)
        XCTAssertEqual(allowed.action, .send)
        XCTAssertFalse(allowed.lines.contains(EZZKError.submissionUnavailable.errorDescription ?? "-"))

        let accepted = productionRow(status: .acceptedForProcessing)
        XCTAssertEqual(ZakoDonePresentation(record: accepted, lastError: nil, lastErrorStatus: nil,
                                            nextStatusCheck: nil, now: Date(), currentMode: .production).action,
                       .none)
        XCTAssertEqual(ZakoDonePresentation(record: accepted, lastError: nil, lastErrorStatus: nil,
                                            nextStatusCheck: nil, now: Date(), currentMode: .production,
                                            productionAllowed: true).action,
                       .verify(availableAt: nil))
    }

    func testControllerHandsItsPolicyToTheChecker() {
        let controller = EZZKAccountController(mode: .production, credentialStore: MemoryCredentialStore(),
                                               transportFactory: { _ in ScriptedTransport([]) },
                                               productionPolicy: .allowed)
        let settingsStore = makeSettingsStore(ezzkAccountController: controller)
        XCTAssertEqual(settingsStore.ezzkAccountController.productionPolicy, .allowed)
        XCTAssertNil(settingsStore.statusChecker.refusalReason(forMode: .production))
    }

    /// Review focus 1: a production row created under the owner switch is left alone once the
    /// switch is gone, and the Register says why. The switch being gone is the refused policy.
    func testWithoutTheSwitchProductionRowsAreLeftAlone() {
        let controller = EZZKAccountController(mode: .production, credentialStore: MemoryCredentialStore(),
                                               transportFactory: { _ in ScriptedTransport([]) },
                                               productionPolicy: .refused)
        let settingsStore = makeSettingsStore(ezzkAccountController: controller)
        XCTAssertEqual(settingsStore.ezzkAccountController.productionPolicy, .refused)
        XCTAssertEqual(settingsStore.statusChecker.refusalReason(forMode: .production),
                       EZZKStatusChecker.productionRefusal)
        XCTAssertNil(settingsStore.statusChecker.refusalReason(forMode: .test))
    }

    /// The shared test helper never builds a controller that could reach production.
    func testDefaultTestSettingsStoreRefusesProduction() {
        XCTAssertEqual(makeSettingsStore().ezzkAccountController.productionPolicy, .refused)
    }
}
