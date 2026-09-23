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

    /// Ruling R15 in the Register detail: no "Odoslať" for a row from before B2, the
    /// Slovak note instead, and no warning about handing documents over.
    func testRegisterDetailOffersNothingForARowWrittenBeforeB2() {
        var legacy = row(.queuedForSubmission)
        legacy.ezzkMode = nil
        let actions = EvidenceRegisterDetail.actions(for: legacy, currentMode: .test)
        XCTAssertFalse(actions.canSend)
        XCTAssertFalse(actions.canVerify)
        XCTAssertEqual(actions.note, "Záznam vznikol pred odosielaním do EZZK v Chevron7, preto ho aplikácia neodosiela.")

        var unsigned = row(.recordUnsigned)
        unsigned.ezzkMode = nil
        XCTAssertEqual(EvidenceRegisterDetail.actions(for: unsigned, currentMode: .test).note,
                       EZZKStatusChecker.preB2RowMessage)
        XCTAssertFalse(EZZKRecordPresentation.stateExplanation(for: unsigned).joined().contains("Neodovzdávajte"))
    }

    /// A retry that leaves the row as it was replaces the flow's error, but the failed
    /// archive copy is still true.
    func testDoneKeepsTheArchiveCopyErrorAfterARetry() {
        let copyError = "Záznam o konverzii je uložený v Registri, ale jeho kópiu sa nepodarilo uložiť k výstupom: disk"
        var queued = row(.queuedForSubmission)
        queued.ezzkResultDescription = "Sieťová chyba pri spojení s EZZK: offline"
        let done = ZakoDonePresentation(record: queued, lastError: "Sieťová chyba pri spojení s EZZK: offline",
                                        lastErrorStatus: .queuedForSubmission, archiveCopyError: copyError,
                                        nextStatusCheck: nil, now: now)
        XCTAssertEqual(done.error, copyError)
    }

    func testDoneOffersNoActionForARowOfAnotherMode() {
        for status in [EvidenceRecord.Status.queuedForSubmission, .outcomeUnknown, .acceptedForProcessing] {
            let done = ZakoDonePresentation(record: row(status, mode: .test), lastError: nil, lastErrorStatus: nil,
                                            archiveCopyError: nil, nextStatusCheck: nil, now: now,
                                            currentMode: .demo)
            XCTAssertEqual(done.action, .none, "\(status)")
            XCTAssertFalse(done.isActionEnabled)
            XCTAssertTrue(done.lines.contains(EZZKStatusChecker.recordFromOtherModeMessage), "\(done.lines)")
        }
        let sameMode = ZakoDonePresentation(record: row(.queuedForSubmission, mode: .test), lastError: nil,
                                            lastErrorStatus: nil, archiveCopyError: nil, nextStatusCheck: nil,
                                            now: now, currentMode: .test)
        XCTAssertEqual(sameMode.action, .send)
    }

    // MARK: - Register konverzií

    func testRegisterSummaryCountsAcceptedAndProcessedAsSentAndRejectedAsFailed() {
        let rows = [row(.acceptedForProcessing), row(.processed), row(.submitted), row(.rejected),
                    row(.recordUnsigned), row(.outcomeUnknown), row(.late), row(.queuedForSubmission)]
        let summary = EvidenceRegisterSummary(records: rows)
        XCTAssertEqual(summary.total, 8)
        XCTAssertEqual(summary.sent, 3)
        XCTAssertEqual(summary.failed, 2)
        XCTAssertEqual(summary.pending, 3)
    }

    func testTimelineShowsAcceptedAsSentAndRejectedAsFailed() {
        let accepted = EvidenceRegisterDetail.timeline(for: row(.acceptedForProcessing))
        XCTAssertEqual(accepted.map(\.label), ["Evidenčné číslo", "Autorizácia KEP", "Záznam v EZZK", "Spracovaný"])
        XCTAssertEqual(accepted.map(\.done), [true, true, true, false])
        XCTAssertEqual(accepted.map(\.failed), [false, false, false, false])

        XCTAssertEqual(EvidenceRegisterDetail.timeline(for: row(.processed)).map(\.done), [true, true, true, true])
        XCTAssertEqual(EvidenceRegisterDetail.timeline(for: row(.rejected)).map(\.failed), [false, false, true, false])
        XCTAssertEqual(EvidenceRegisterDetail.timeline(for: row(.recordUnsigned)).map(\.failed), [false, false, true, false])
        XCTAssertEqual(EvidenceRegisterDetail.timeline(for: row(.outcomeUnknown)).map(\.done), [true, true, false, false])
    }

    func testDetailFactsShowTheSubmission() {
        var record = row(.rejected)
        record.submittedAt = now
        record.submissionMessageID = "ae6fbf72-1"
        record.ezzkResultCode = 12
        record.ezzkResultDescription = "Neznámy obsah"
        record.lastLookupAt = now.addingTimeInterval(3600)
        let facts = Dictionary(uniqueKeysWithValues: EvidenceRegisterDetail.submissionFacts(for: record).map { ($0.label, $0.value) })
        XCTAssertEqual(facts["Stav"], "Odmietnutý v EZZK")
        XCTAssertEqual(facts["Režim EZZK"], "Test")
        XCTAssertEqual(facts["Odoslané"], "24. 9. 2026 12:00")
        XCTAssertEqual(facts["ID správy"], "ae6fbf72-1")
        XCTAssertEqual(facts["Výsledok EZZK"], "12: Neznámy obsah")
        XCTAssertEqual(facts["Posledné overenie"], "24. 9. 2026 13:00")

        let fresh = EvidenceRegisterDetail.submissionFacts(for: row(.signed)).map(\.label)
        XCTAssertEqual(fresh, ["Stav", "Režim EZZK"], "only what the row has")
    }

    func testDetailActionsFollowStateAndMode() {
        let queued = EvidenceRegisterDetail.actions(for: row(.queuedForSubmission), currentMode: .test)
        XCTAssertTrue(queued.canSend)
        XCTAssertFalse(queued.canVerify)
        XCTAssertNil(queued.note)

        let late = EvidenceRegisterDetail.actions(for: row(.late), currentMode: .test)
        XCTAssertTrue(late.canSend)
        XCTAssertEqual(late.note, EZZKRecordPresentation.lateWarning)

        for status in [EvidenceRecord.Status.outcomeUnknown, .acceptedForProcessing] {
            let actions = EvidenceRegisterDetail.actions(for: row(status), currentMode: .test)
            XCTAssertFalse(actions.canSend, "\(status)")
            XCTAssertTrue(actions.canVerify, "\(status)")
        }

        let otherMode = EvidenceRegisterDetail.actions(for: row(.queuedForSubmission, mode: .demo), currentMode: .test)
        XCTAssertFalse(otherMode.canSend)
        XCTAssertEqual(otherMode.note, EZZKStatusChecker.recordFromOtherModeMessage)

        let production = EvidenceRegisterDetail.actions(for: row(.queuedForSubmission, mode: .production),
                                                         currentMode: .production)
        XCTAssertFalse(production.canSend)
        XCTAssertEqual(production.note, EZZKError.submissionUnavailable.errorDescription)

        let unsigned = EvidenceRegisterDetail.actions(for: row(.recordUnsigned), currentMode: .test)
        XCTAssertFalse(unsigned.canSend)
        XCTAssertFalse(unsigned.canVerify)
        XCTAssertEqual(unsigned.note, "Záznam podpíšte znova novou konverziou; opakovaný podpis z Registra príde neskôr.")
    }

    func testDeadlineColumn() {
        XCTAssertEqual(EvidenceRegisterDetail.deadline(for: row(.late), now: now).text, EZZKRecordPresentation.lateWarning)
        XCTAssertEqual(EvidenceRegisterDetail.deadline(for: row(.processed), now: now).text, "Spracovaný v EZZK")
        XCTAssertEqual(EvidenceRegisterDetail.deadline(for: row(.acceptedForProcessing), now: now).tone, .success)

        let today = EvidenceRegisterDetail.deadline(for: row(.queuedForSubmission), now: now)
        XCTAssertEqual(today.text, "Odoslať ešte dnes, do polnoci")
        XCTAssertEqual(today.tone, .warning)

        let unknown = EvidenceRegisterDetail.deadline(for: row(.outcomeUnknown), now: now.addingTimeInterval(2 * 86400))
        XCTAssertEqual(unknown.text, "Najprv overte v EZZK")
        XCTAssertFalse(unknown.text.contains("\u{2014}"), "no em dash")
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
