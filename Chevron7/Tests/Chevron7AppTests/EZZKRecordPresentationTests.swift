// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Chevron7Kit
import Foundation
import XCTest
@testable import Chevron7App

/// What the ZaKo Done screen tells the advocate about the conversion's EZZK record. It
/// reads the stored row (its state and the EZZK mode it was signed in), never the current
/// mode, and claims success only when EZZK has the record.
@MainActor
final class EZZKRecordPresentationTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-09-24T10:00:00Z")!

    func testDoneClaimsSuccessOnlyWhenEZZKHasTheRecord() {
        for status in EvidenceRecord.Status.allCases {
            let done = ZakoDonePresentation(record: row(status), lastError: nil, lastErrorStatus: nil,
                                            archiveCopyError: nil, nextStatusCheck: nil, now: now)
            let succeeded = status == .acceptedForProcessing || status == .processed || status == .submitted
            XCTAssertEqual(done.tone == .success, succeeded, "\(status)")
            if !succeeded {
                XCTAssertFalse(done.title.contains("úspešne"), "\(status): \(done.title)")
            }
        }
    }

    func testDoneReadsTheModeTheRowWasSignedIn() {
        let test = ZakoDonePresentation(record: row(.queuedForSubmission, mode: .test), lastError: nil,
                                        lastErrorStatus: nil, archiveCopyError: nil, nextStatusCheck: nil, now: now)
        XCTAssertTrue(test.lines.contains("Režim EZZK pri podpise: Test"), "\(test.lines)")
        XCTAssertEqual(test.action, .send)

        let demo = ZakoDonePresentation(record: row(.queuedForSubmission, mode: .demo), lastError: nil,
                                        lastErrorStatus: nil, archiveCopyError: nil, nextStatusCheck: nil, now: now)
        XCTAssertEqual(demo.action, .send)

        let production = ZakoDonePresentation(record: row(.queuedForSubmission, mode: .production), lastError: nil,
                                              lastErrorStatus: nil, archiveCopyError: nil, nextStatusCheck: nil, now: now)
        XCTAssertEqual(production.action, .none, "production stays refused")
        XCTAssertTrue(production.lines.contains(EZZKError.submissionUnavailable.errorDescription ?? "-"))
    }

    func testDoneExplainsEveryStateThatNeedsTheAdvocate() {
        var unknown = row(.outcomeUnknown)
        unknown.ezzkResultDescription = EZZKError.outcomeUnknown.localizedDescription
        let unknownDone = presentation(unknown, nextStatusCheck: now.addingTimeInterval(4 * 60))
        XCTAssertTrue(unknownDone.lines.joined(separator: " ").contains("najprv overte v EZZK"), "\(unknownDone.lines)")
        XCTAssertEqual(unknownDone.action, .verify(availableAt: now.addingTimeInterval(4 * 60)))
        XCTAssertFalse(unknownDone.isActionEnabled, "the lookup waits five minutes after the attempt")
        XCTAssertTrue(presentation(unknown, nextStatusCheck: now.addingTimeInterval(-1)).isActionEnabled)

        var rejected = row(.rejected)
        rejected.ezzkResultCode = 12
        rejected.ezzkResultDescription = "Neznámy obsah"
        let rejectedDone = presentation(rejected)
        XCTAssertEqual(rejectedDone.tone, .failure)
        XCTAssertTrue(rejectedDone.lines.contains("EZZK vrátilo kód 12: Neznámy obsah"), "\(rejectedDone.lines)")
        XCTAssertEqual(rejectedDone.action, .none)

        var unsigned = row(.recordUnsigned)
        unsigned.ezzkResultDescription = "Karta bola vybratá."
        let unsignedDone = presentation(unsigned)
        let unsignedText = unsignedDone.lines.joined(separator: " ")
        XCTAssertTrue(unsignedText.contains("1563-260924-1"), unsignedText)
        XCTAssertTrue(unsignedText.contains("Neodovzdávajte"), unsignedText)
        XCTAssertTrue(unsignedText.contains("nové evidenčné číslo"), unsignedText)
        XCTAssertEqual(unsignedDone.action, .none)

        let lateDone = presentation(row(.late))
        XCTAssertTrue(lateDone.lines.contains(EZZKRecordPresentation.lateWarning))
        XCTAssertEqual(lateDone.action, .send)

        var queued = row(.queuedForSubmission)
        queued.ezzkResultDescription = "Sieťová chyba pri spojení s EZZK: offline"
        let queuedDone = presentation(queued)
        XCTAssertTrue(queuedDone.lines.contains("Sieťová chyba pri spojení s EZZK: offline"))
        XCTAssertEqual(queuedDone.tone, .pending)

        let accepted = presentation(row(.acceptedForProcessing), nextStatusCheck: now.addingTimeInterval(60))
        XCTAssertEqual(accepted.action, .verify(availableAt: nil), "a refresh of an accepted row needs no wait")
        XCTAssertTrue(accepted.isActionEnabled)
    }

    /// The flow's last error describes the row as ZaKo last saw it; once the periodic check
    /// moved the row on, only the archive copy failure still applies.
    func testDoneShowsTheFlowsErrorOnlyWhileItStillDescribesTheRow() {
        let copyError = "Záznam o konverzii je uložený v Registri, ale jeho kópiu sa nepodarilo uložiť k výstupom: disk"
        var unknown = row(.outcomeUnknown)
        unknown.ezzkResultDescription = "Výsledok neznámy"
        let stillUnknown = ZakoDonePresentation(record: unknown, lastError: "Výsledok neznámy\n" + copyError,
                                                lastErrorStatus: .outcomeUnknown, archiveCopyError: copyError,
                                                nextStatusCheck: nil, now: now)
        XCTAssertEqual(stillUnknown.error, copyError, "the row's own description is already a line")

        let movedOn = ZakoDonePresentation(record: row(.acceptedForProcessing), lastError: "Výsledok neznámy\n" + copyError,
                                           lastErrorStatus: .outcomeUnknown, archiveCopyError: copyError,
                                           nextStatusCheck: nil, now: now)
        XCTAssertEqual(movedOn.error, copyError)

        let refused = ZakoDonePresentation(record: row(.queuedForSubmission), lastError: EZZKStatusChecker.rowBusyMessage,
                                           lastErrorStatus: .queuedForSubmission, archiveCopyError: nil,
                                           nextStatusCheck: nil, now: now)
        XCTAssertEqual(refused.error, EZZKStatusChecker.rowBusyMessage)
    }

    func testDoneWithoutARowSaysSoAndOffersNothing() {
        let done = ZakoDonePresentation(record: nil, lastError: "Register konverzií sa nepodarilo načítať.",
                                        lastErrorStatus: nil, archiveCopyError: nil, nextStatusCheck: nil, now: now)
        XCTAssertNotEqual(done.tone, .success)
        XCTAssertEqual(done.action, .none)
        XCTAssertEqual(done.error, "Register konverzií sa nepodarilo načítať.")
    }

    // MARK: - Fixtures

    private func presentation(_ record: EvidenceRecord, nextStatusCheck: Date? = nil) -> ZakoDonePresentation {
        ZakoDonePresentation(record: record, lastError: nil, lastErrorStatus: nil, archiveCopyError: nil,
                             nextStatusCheck: nextStatusCheck, now: now)
    }

    private func row(_ status: EvidenceRecord.Status, mode: AppSettings.EZZKMode = .test) -> EvidenceRecord {
        EvidenceRecord(createdAt: now, status: status, direction: .paperToElectronic, originalName: "Zmluva",
                       newDocumentName: "Zmluva.pdf", evidenceNumber: "1563-260924-1", fingerprintSHA256Hex: "ab",
                       attestationXML: "<x/>", conversionTime: now, performingPersonName: "JUDr. Test Testovací",
                       securityElementCount: 0, totalPages: 1, totalSheets: 1, ezzkMode: mode,
                       evidenceNumberAllocatedAt: now)
    }
}
