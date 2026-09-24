// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Chevron7Kit
import Chevron7TestSupport
import Foundation
import XCTest
@testable import Chevron7App

/// Register konverzií, ZaKo and the periodic check all move register rows through one
/// `EZZKStatusChecker`, which applies the submission coordinator's rules, keeps each row
/// to one action at a time and checks a row only against the EZZK that allocated it.
@MainActor
final class EvidenceSubmissionFlowTests: XCTestCase {
    private let container = Data("PK-signed-record".utf8)

    // MARK: - Register "Odoslať"

    /// The part A dashboard turned every error into "Odoslanie zlyhalo". A lost connection
    /// may have delivered the record, so it becomes an unknown outcome that is looked up,
    /// never resent and never marked failed.
    func testSubmitPendingNeverMarksUnknownAsFailed() async throws {
        let clock = TestClock("2026-09-24T08:00:00Z")
        let submitter = ScriptedSubmitter([.failure(EZZKError.outcomeUnknown),
                                           .failure(URLError(.networkConnectionLost))])
        let lookup = ScriptedLookup([.failure(EZZKError.networkFailure("offline"))])
        let (checker, store) = makeChecker(mode: .test, submitter: submitter, lookup: lookup, clock: clock)
        let signed = try addRow(.signed, number: "1563-260924-1", to: store, clock: clock)
        let queued = try addRow(.queuedForSubmission, number: "1563-260924-2", to: store, clock: clock)
        var recent = try addRow(.outcomeUnknown, number: "1563-260924-3", to: store, clock: clock)
        recent.updatedAt = clock.now.addingTimeInterval(-60)
        store.upsert(recent)

        let first = await checker.submitPending()

        XCTAssertEqual(store.record(id: signed.id)?.status, .outcomeUnknown)
        XCTAssertEqual(store.record(id: queued.id)?.status, .outcomeUnknown)
        XCTAssertEqual(store.record(id: recent.id)?.status, .outcomeUnknown)
        XCTAssertEqual(submitter.calls, 2, "the row whose outcome is already unknown is never resent")
        XCTAssertEqual(lookup.calls, 0, "an unknown outcome younger than five minutes is not looked up yet")
        XCTAssertEqual(first.unknown, 3)
        XCTAssertEqual(first.accepted, 0)

        // Ten minutes later the lookup runs; it fails, so the rows stay unknown and unsent.
        clock.advance(by: 10 * 60)
        let second = await checker.submitPending()

        XCTAssertEqual(submitter.calls, 2, "nothing is sent while the outcome is unknown")
        XCTAssertEqual(lookup.calls, 3)
        for row in store.records {
            XCTAssertEqual(row.status, .outcomeUnknown, "\(row.evidenceNumber ?? "")")
            XCTAssertNotEqual(row.status, .submissionFailed)
        }
        XCTAssertEqual(second.unknown, 3)
    }

    /// Accepted rows update the pool, and an unknown row the lookup finds is never sent again.
    func testSubmitPendingSendsQueuedRowsAndResolvesUnknownOnesByLookup() async throws {
        let clock = TestClock("2026-09-24T08:00:00Z")
        let receipt = EZZKSOAPSubmissionReceipt(messageID: "m-1", submittedAt: clock.now)
        let submitter = ScriptedSubmitter([.success(receipt)])
        let lookup = ScriptedLookup([.success(EZZKRecordLookup(isProcessed: false, info: nil))])
        let (checker, store) = makeChecker(mode: .test, submitter: submitter, lookup: lookup, clock: clock)
        pool.add(.init(number: "1563-260924-1", mode: .test, allocatedAt: clock.now))
        let queued = try addRow(.queuedForSubmission, number: "1563-260924-1", to: store, clock: clock)
        var unknown = try addRow(.outcomeUnknown, number: "1563-260924-2", to: store, clock: clock)
        unknown.updatedAt = clock.now.addingTimeInterval(-10 * 60)
        store.upsert(unknown)

        let summary = await checker.submitPending()

        XCTAssertEqual(store.record(id: queued.id)?.status, .acceptedForProcessing)
        XCTAssertEqual(store.record(id: queued.id)?.submissionMessageID, "m-1")
        XCTAssertEqual(store.record(id: unknown.id)?.status, .acceptedForProcessing)
        XCTAssertEqual(submitter.calls, 1, "the record EZZK already has is not sent again")
        XCTAssertEqual(summary.accepted, 2)
        XCTAssertNil(pool.reusable(mode: .test, at: clock.now, excluding: []),
                     "a consumed number is never offered again")
    }

    func testSubmitRefusesARowOfAnotherModeAndARowAlreadyInFlight() async throws {
        let clock = TestClock("2026-09-24T08:00:00Z")
        let submitter = SuspendingSubmitter(EZZKSOAPSubmissionReceipt(messageID: "m-2", submittedAt: clock.now))
        let (checker, store) = makeChecker(mode: .test, submitter: submitter, lookup: ScriptedLookup([]), clock: clock)
        let demoRow = try addRow(.queuedForSubmission, number: "1563-260924-5", mode: .demo, to: store, clock: clock)
        let row = try addRow(.queuedForSubmission, number: "1563-260924-6", to: store, clock: clock)

        let otherMode = await checker.submit(id: demoRow.id)
        XCTAssertEqual(otherMode.refusal, EZZKStatusChecker.recordFromOtherModeMessage)
        XCTAssertEqual(store.record(id: demoRow.id)?.status, .queuedForSubmission)

        let sending = Task { await checker.submit(id: row.id) }
        try await submitter.waitUntilSending()
        XCTAssertTrue(checker.isBusy(row.id))

        let second = await checker.submit(id: row.id)
        XCTAssertEqual(second.refusal, EZZKStatusChecker.rowBusyMessage)
        await checker.runOnce()
        XCTAssertEqual(submitter.calls, 1, "neither the Register nor the checker touches a row in flight")

        submitter.release()
        let first = await sending.value
        XCTAssertEqual(first.record?.status, .acceptedForProcessing)
        XCTAssertFalse(checker.isBusy(row.id))
    }

    /// ZaKo's "Odoslať do EZZK" and the Register go through the same send: a row whose
    /// allocation day ended is marked late before it is sent, and stays late when nothing
    /// reached EZZK.
    func testManualSubmitMarksAPastDayRowLateFirst() async throws {
        let clock = TestClock("2026-09-24T10:00:00Z")
        let submitter = ScriptedSubmitter([.failure(EZZKError.networkFailure("offline"))])
        let (checker, store) = makeChecker(mode: .test, submitter: submitter, lookup: ScriptedLookup([]), clock: clock)
        var row = try addRow(.queuedForSubmission, number: "1563-260923-2", to: store, clock: clock)
        row.evidenceNumberAllocatedAt = clock.now.addingTimeInterval(-24 * 3600)
        store.upsert(row)

        let result = await checker.submit(id: row.id)

        XCTAssertEqual(submitter.calls, 1, "a late row is still sent (ruling R12)")
        XCTAssertEqual(result.record?.status, .late)
        XCTAssertEqual(store.record(id: row.id)?.status, .late)
    }

    func testPendingSummaryFeedbackNamesEveryOutcome() {
        var summary = EZZKStatusChecker.PendingSummary()
        XCTAssertEqual(summary.feedback, "Žiadny záznam nečaká na odoslanie.")
        XCTAssertFalse(summary.isSuccess)

        summary.accepted = 2
        XCTAssertEqual(summary.feedback, "Prijaté na spracovanie v EZZK: 2.")
        XCTAssertTrue(summary.isSuccess)

        summary.unknown = 1
        summary.waiting = 1
        summary.rejected = 1
        summary.unsigned = 1
        summary.skipped = 1
        XCTAssertEqual(summary.feedback,
                       "Prijaté na spracovanie v EZZK: 2. Výsledok neznámy, overí sa v EZZK: 1. Čaká na odoslanie: 1. Odmietnuté v EZZK: 1. Záznam nepodpísaný: 1. Preskočené (iný režim EZZK alebo prebieha iná akcia): 1.")
        XCTAssertFalse(summary.isSuccess)

        summary.refusal = "Register konverzií sa nepodarilo načítať."
        XCTAssertEqual(summary.feedback, "Register konverzií sa nepodarilo načítať.")
        XCTAssertFalse(summary.isSuccess)
    }

    // MARK: - Periodic check

    func testStatusCheckerRefreshesDueAcceptedRows() async throws {
        let clock = TestClock("2026-09-24T10:00:00Z")
        let lookup = ScriptedLookup([.success(EZZKRecordLookup(isProcessed: true, info: nil))])
        let submitter = ScriptedSubmitter([])
        let (checker, store) = makeChecker(mode: .test, submitter: submitter, lookup: lookup, clock: clock)
        var due = try addRow(.acceptedForProcessing, number: "1563-260924-1", to: store, clock: clock)
        due.submittedAt = clock.now.addingTimeInterval(-10 * 60)
        store.upsert(due)
        var fresh = try addRow(.acceptedForProcessing, number: "1563-260924-2", to: store, clock: clock)
        fresh.submittedAt = clock.now.addingTimeInterval(-60)
        store.upsert(fresh)
        var checkedRecently = try addRow(.acceptedForProcessing, number: "1563-260924-3", to: store, clock: clock)
        checkedRecently.submittedAt = clock.now.addingTimeInterval(-2 * 3600)
        checkedRecently.lastLookupAt = clock.now.addingTimeInterval(-10 * 60)
        store.upsert(checkedRecently)
        let processed = try addRow(.processed, number: "1563-260924-4", to: store, clock: clock)

        await checker.runOnce()

        XCTAssertEqual(lookup.numbers, ["1563-260924-1"], "only the row whose check is due is looked up")
        XCTAssertEqual(store.record(id: due.id)?.status, .processed)
        XCTAssertEqual(store.record(id: due.id)?.lastLookupAt, clock.now)
        XCTAssertEqual(store.record(id: fresh.id)?.status, .acceptedForProcessing)
        XCTAssertNil(store.record(id: fresh.id)?.lastLookupAt)
        XCTAssertEqual(store.record(id: checkedRecently.id)?.lastLookupAt, checkedRecently.lastLookupAt)
        XCTAssertEqual(store.record(id: processed.id)?.status, .processed)
        XCTAssertEqual(submitter.calls, 0)
    }

    /// An unknown outcome is looked up once its check is due; EZZK does not know the number
    /// (105), so the row is queued again and the next pass sends it.
    func testStatusCheckerResolvesDueUnknownRowsAndSendsThemNextPass() async throws {
        let clock = TestClock("2026-09-24T10:00:00Z")
        let lookup = ScriptedLookup([.failure(EZZKError.serviceRejected(code: 105, message: "Neznáme evidenčné číslo"))])
        let submitter = ScriptedSubmitter([.success(EZZKSOAPSubmissionReceipt(messageID: "m-3", submittedAt: clock.now))])
        let (checker, store) = makeChecker(mode: .test, submitter: submitter, lookup: lookup, clock: clock)
        var unknown = try addRow(.outcomeUnknown, number: "1563-260924-1", to: store, clock: clock)
        unknown.updatedAt = clock.now.addingTimeInterval(-6 * 60)
        store.upsert(unknown)
        var notYet = try addRow(.outcomeUnknown, number: "1563-260924-2", to: store, clock: clock)
        notYet.updatedAt = clock.now.addingTimeInterval(-60)
        store.upsert(notYet)

        await checker.runOnce()

        XCTAssertEqual(lookup.numbers, ["1563-260924-1"])
        XCTAssertEqual(store.record(id: unknown.id)?.status, .queuedForSubmission)
        XCTAssertEqual(store.record(id: notYet.id)?.status, .outcomeUnknown)
        XCTAssertEqual(submitter.calls, 0, "a row is not sent in the pass that resolved it")

        clock.advance(by: 60)
        await checker.runOnce()
        XCTAssertEqual(store.record(id: unknown.id)?.status, .acceptedForProcessing)
        XCTAssertEqual(submitter.calls, 1)
    }

    func testCheckerSkipsRowsOfAnotherMode() async throws {
        let clock = TestClock("2026-09-24T10:00:00Z")
        let lookup = ScriptedLookup([])
        let submitter = ScriptedSubmitter([])
        let (checker, store) = makeChecker(mode: .test, submitter: submitter, lookup: lookup, clock: clock)
        var demoAccepted = try addRow(.acceptedForProcessing, number: "1563-260924-1", mode: .demo, to: store, clock: clock)
        demoAccepted.submittedAt = clock.now.addingTimeInterval(-3 * 3600)
        store.upsert(demoAccepted)
        var productionUnknown = try addRow(.outcomeUnknown, number: "1563-260924-2", mode: .production, to: store, clock: clock)
        productionUnknown.updatedAt = clock.now.addingTimeInterval(-3 * 3600)
        store.upsert(productionUnknown)
        _ = try addRow(.queuedForSubmission, number: "1563-260924-3", mode: .demo, to: store, clock: clock)
        // A row from before B2 has no mode: nobody knows which EZZK allocated its number.
        _ = try addRow(.queuedForSubmission, number: "1563-260924-4", mode: nil, to: store, clock: clock)
        var yesterday = try addRow(.queuedForSubmission, number: "1563-260923-5", mode: .demo, to: store, clock: clock)
        yesterday.evidenceNumberAllocatedAt = clock.now.addingTimeInterval(-36 * 3600)
        store.upsert(yesterday)
        let before = store.records

        await checker.runOnce()

        XCTAssertEqual(lookup.calls, 0)
        XCTAssertEqual(submitter.calls, 0)
        for row in before {
            let after = try XCTUnwrap(store.record(id: row.id))
            XCTAssertEqual(after.status, row.status, "\(row.evidenceNumber ?? "")")
            XCTAssertEqual(after.updatedAt, row.updatedAt, "\(row.evidenceNumber ?? "")")
        }
    }

    func testCheckerSkipsRowsWithoutEvidenceNumber() async throws {
        let clock = TestClock("2026-09-24T10:00:00Z")
        let submitter = ScriptedSubmitter([])
        let (checker, store) = makeChecker(mode: .test, submitter: submitter, lookup: ScriptedLookup([]), clock: clock)
        let row = try addRow(.queuedForSubmission, number: nil, to: store, clock: clock)

        await checker.runOnce()

        XCTAssertEqual(submitter.calls, 0)
        XCTAssertEqual(store.record(id: row.id)?.updatedAt, row.updatedAt)
    }

    /// A row whose allocation day ended becomes late and is still sent (EZZK accepted a
    /// late record for processing, ruling R12). Automatic resends stop after three a day;
    /// "Odoslať" in the Register still works.
    func testCheckerMarksLateRowsAndCapsAutomaticResends() async throws {
        let clock = TestClock("2026-09-24T10:00:00Z")
        let offline = Result<EZZKSOAPSubmissionReceipt, Error>.failure(EZZKError.networkFailure("offline"))
        let submitter = ScriptedSubmitter([offline, offline, offline,
                                           .success(EZZKSOAPSubmissionReceipt(messageID: "m-4", submittedAt: clock.now))])
        let (checker, store) = makeChecker(mode: .test, submitter: submitter, lookup: ScriptedLookup([]), clock: clock)
        var row = try addRow(.queuedForSubmission, number: "1563-260923-1", to: store, clock: clock)
        row.evidenceNumberAllocatedAt = clock.now.addingTimeInterval(-24 * 3600)
        store.upsert(row)

        for _ in 0..<5 {
            await checker.runOnce()
            clock.advance(by: 5 * 60)
        }

        XCTAssertEqual(submitter.calls, 3, "three automatic attempts a day, then the row waits for the advocate")
        XCTAssertEqual(store.record(id: row.id)?.status, .late)

        let manual = await checker.submit(id: row.id)
        XCTAssertEqual(manual.record?.status, .acceptedForProcessing)
        XCTAssertEqual(submitter.calls, 4)
    }

    func testStartPrunesLapsedNumbersAtLaunch() throws {
        let clock = TestClock("2026-09-24T10:00:00Z")
        let (checker, _) = makeChecker(mode: .test, submitter: ScriptedSubmitter([]), lookup: ScriptedLookup([]), clock: clock)
        pool.add(.init(number: "1563-260923-9", mode: .test, allocatedAt: clock.now.addingTimeInterval(-24 * 3600)))

        checker.start()
        checker.stop()

        let data = try Data(contentsOf: storeRoot.appendingPathComponent("Evidence/allocated-numbers.json"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("1563-260923-9"))
    }

    func testUnreadableRegisterStopsEveryAction() async throws {
        let settingsStore = try makeSettingsStoreWithUnreadableRegister()
        let checker = settingsStore.statusChecker
        let result = await checker.submit(id: UUID())
        XCTAssertEqual(result.refusal, settingsStore.evidenceStore.loadError)
        let summary = await checker.submitPending()
        XCTAssertEqual(summary.refusal, settingsStore.evidenceStore.loadError)
    }

    /// Demo (ruling R4): the local `MockEZZKService` accepts, and the Demo lookup answers
    /// processed, so nothing reaches EZZK.
    func testSettingsStoreCheckerUsesDemoServiceAndLookupInDemo() async throws {
        let settingsStore = makeSettingsStore()
        let store = settingsStore.evidenceStore
        var row = EvidenceRecord(status: .queuedForSubmission, direction: .paperToElectronic, originalName: "a",
                                 newDocumentName: "a.pdf", evidenceNumber: "1563-260924-1",
                                 fingerprintSHA256Hex: "ab", attestationXML: "<x/>", conversionTime: Date(),
                                 performingPersonName: "M", securityElementCount: 0, totalPages: 1, totalSheets: 1,
                                 ezzkMode: .demo, evidenceNumberAllocatedAt: Date())
        row.recordContainerPath = try store.storeRecordContainer(container, for: row.id)
        store.upsert(row)

        let sent = await settingsStore.statusChecker.submit(id: row.id)
        XCTAssertEqual(sent.record?.status, .acceptedForProcessing)
        let demoService = try XCTUnwrap(settingsStore.ezzkService as? MockEZZKService)
        XCTAssertEqual(demoService.submittedRecords.first?.signedRecordContainer, container)

        let verified = await settingsStore.statusChecker.verify(id: row.id)
        XCTAssertEqual(verified.record?.status, .processed)
    }

    /// Ruling R13: a Chevron7 started by Safari for a portal signature (accessory, no
    /// window) does not talk to EZZK in the background; the check starts once the app
    /// becomes a regular app.
    func testCheckerStartsOnlyInTheRegularLaunchMode() throws {
        XCTAssertTrue(EZZKStatusChecker.shouldRun(launchMode: .normal, isRegularApp: false))
        XCTAssertFalse(EZZKStatusChecker.shouldRun(launchMode: .webSigning, isRegularApp: false))
        XCTAssertTrue(EZZKStatusChecker.shouldRun(launchMode: .webSigning, isRegularApp: true))

        let clock = TestClock("2026-09-24T10:00:00Z")
        let (checker, _) = makeChecker(mode: .test, submitter: ScriptedSubmitter([]), lookup: ScriptedLookup([]), clock: clock)
        pool.add(.init(number: "1563-260923-9", mode: .test, allocatedAt: clock.now.addingTimeInterval(-24 * 3600)))
        defer { checker.stop() }

        checker.startIfAllowed(launchMode: .webSigning, isRegularApp: false)
        XCTAssertFalse(checker.isRunning)
        XCTAssertTrue(try poolFileText().contains("1563-260923-9"), "not started, so nothing was pruned")

        checker.startIfAllowed(launchMode: .webSigning, isRegularApp: true)
        XCTAssertTrue(checker.isRunning)
        XCTAssertFalse(try poolFileText().contains("1563-260923-9"))
    }

    func testStartIsIdempotent() throws {
        let clock = TestClock("2026-09-24T10:00:00Z")
        let (checker, _) = makeChecker(mode: .test, submitter: ScriptedSubmitter([]), lookup: ScriptedLookup([]), clock: clock)
        defer { checker.stop() }
        checker.start()
        pool.add(.init(number: "1563-260923-8", mode: .test, allocatedAt: clock.now.addingTimeInterval(-24 * 3600)))

        checker.start()

        XCTAssertTrue(checker.isRunning)
        XCTAssertTrue(try poolFileText().contains("1563-260923-8"), "a second start neither prunes nor starts a second loop")
    }

    /// Ruling R15: a row written before B2 has no EZZK mode and no signed record, so no
    /// path sends or looks it up.
    func testRowsWrittenBeforeB2AreNeverSent() async throws {
        let clock = TestClock("2026-09-24T10:00:00Z")
        let submitter = ScriptedSubmitter([])
        let lookup = ScriptedLookup([])
        let (checker, store) = makeChecker(mode: .test, submitter: submitter, lookup: lookup, clock: clock)
        let legacy = try addRow(.queuedForSubmission, number: "1563-260920-1", mode: nil, to: store, clock: clock)

        let summary = await checker.submitPending()
        XCTAssertEqual(summary.legacy, 1)
        XCTAssertEqual(summary.waiting, 0)
        XCTAssertTrue(summary.feedback.contains(EZZKStatusChecker.preB2RowMessage), summary.feedback)
        let submitted = await checker.submit(id: legacy.id)
        XCTAssertEqual(submitted.refusal, EZZKStatusChecker.preB2RowMessage)
        let verified = await checker.verify(id: legacy.id)
        XCTAssertEqual(verified.refusal, EZZKStatusChecker.preB2RowMessage)
        await checker.runOnce()

        XCTAssertEqual(submitter.calls, 0)
        XCTAssertEqual(lookup.calls, 0)
        XCTAssertEqual(store.record(id: legacy.id)?.status, .queuedForSubmission)
        XCTAssertEqual(store.record(id: legacy.id)?.updatedAt, legacy.updatedAt)
    }

    /// Switching the EZZK mode while a pass waits on a lookup: the rest of the pass leaves
    /// the old mode's rows alone, and every coordinator targeted the row's own mode.
    func testModeSwitchDuringAPassStopsTheRestOfThePass() async throws {
        let clock = TestClock("2026-09-24T10:00:00Z")
        let lookup = SuspendingLookup(EZZKRecordLookup(isProcessed: true, info: nil))
        let submitter = ScriptedSubmitter([])
        let (checker, store) = makeChecker(mode: .test, submitter: submitter, lookup: lookup, clock: clock)
        _ = try addRow(.queuedForSubmission, number: "1563-260924-3", to: store, clock: clock)
        var second = try addRow(.acceptedForProcessing, number: "1563-260924-2", to: store, clock: clock)
        second.submittedAt = clock.now.addingTimeInterval(-10 * 60)
        store.upsert(second)
        var first = try addRow(.acceptedForProcessing, number: "1563-260924-1", to: store, clock: clock)
        first.submittedAt = clock.now.addingTimeInterval(-10 * 60)
        store.upsert(first)
        XCTAssertEqual(store.records.first?.id, first.id, "the pass starts with the row whose lookup waits")

        let pass = Task { await checker.runOnce() }
        try await lookup.waitUntilLooking()
        currentMode = .demo
        lookup.release()
        await pass.value

        XCTAssertEqual(lookup.numbers, ["1563-260924-1"], "no lookup after the switch")
        XCTAssertEqual(submitter.calls, 0, "no send after the switch")
        XCTAssertEqual(store.record(id: second.id)?.lastLookupAt, nil)
        XCTAssertEqual(Set(coordinatorModes), [.test], "every coordinator targets the row's own mode")
    }

    /// A row the advocate deletes while it is being sent is not brought back, but the
    /// number EZZK consumed is still dropped from the pool.
    func testDeletedRowStillReleasesItsConsumedNumber() async throws {
        let clock = TestClock("2026-09-24T10:00:00Z")
        let submitter = SuspendingSubmitter(EZZKSOAPSubmissionReceipt(messageID: "m-9", submittedAt: clock.now))
        let (checker, store) = makeChecker(mode: .test, submitter: submitter, lookup: ScriptedLookup([]), clock: clock)
        pool.add(.init(number: "1563-260924-9", mode: .test, allocatedAt: clock.now))
        let row = try addRow(.queuedForSubmission, number: "1563-260924-9", to: store, clock: clock)

        let sending = Task { await checker.submit(id: row.id) }
        try await submitter.waitUntilSending()
        store.delete(id: row.id)
        submitter.release()
        _ = await sending.value

        XCTAssertNil(store.record(id: row.id))
        XCTAssertNil(pool.reusable(mode: .test, at: clock.now, excluding: []))
    }

    /// ZaKo holds its row while it signs the record: no path touches it. Once released, a
    /// `.signed` row still without a record container is a crash orphan, and the check
    /// marks it unsigned exactly as it treats any row without a signed record.
    func testHeldRowIsLeftAloneAndAnOrphanBecomesUnsignedAfterRelease() async throws {
        let clock = TestClock("2026-09-24T10:00:00Z")
        let submitter = ScriptedSubmitter([])
        let (checker, store) = makeChecker(mode: .test, submitter: submitter, lookup: ScriptedLookup([]), clock: clock)
        var row = try addRow(.signed, number: "1563-260924-4", to: store, clock: clock)
        row.recordContainerPath = nil
        store.upsert(row)

        checker.hold(row.id)
        await checker.runOnce()
        let manual = await checker.submit(id: row.id)

        XCTAssertEqual(store.record(id: row.id)?.status, .signed)
        XCTAssertEqual(manual.refusal, EZZKStatusChecker.rowBusyMessage)

        checker.release(row.id)
        await checker.runOnce()

        XCTAssertEqual(store.record(id: row.id)?.status, .recordUnsigned)
        XCTAssertEqual(submitter.calls, 0)
    }

    /// A deleted row's number is never offered again: the pool forgets it with the row.
    func testDeletingARowDropsItsNumberFromThePool() async throws {
        let clock = TestClock("2026-09-24T10:00:00Z")
        let (checker, store) = makeChecker(mode: .test, submitter: ScriptedSubmitter([]),
                                           lookup: ScriptedLookup([]), clock: clock)
        pool.add(.init(number: "1563-260924-5", mode: .test, allocatedAt: clock.now))
        let row = try addRow(.recordUnsigned, number: "1563-260924-5", to: store, clock: clock)
        let changes = checker.changeCount

        checker.delete(id: row.id)

        XCTAssertNil(store.record(id: row.id))
        XCTAssertNil(pool.reusable(mode: .test, at: clock.now, excluding: []))
        XCTAssertGreaterThan(checker.changeCount, changes)
    }

    /// "Odoslať znova" sends a record EZZK refused at submission through the coordinator;
    /// the periodic check and "Odoslať" never resend a rejected row.
    func testRejectedRowIsResentOnlyByHand() async throws {
        let clock = TestClock("2026-09-24T10:00:00Z")
        let receipt = EZZKSOAPSubmissionReceipt(messageID: "m-7", submittedAt: clock.now)
        let submitter = ScriptedSubmitter([.success(receipt)])
        let (checker, store) = makeChecker(mode: .test, submitter: submitter, lookup: ScriptedLookup([]), clock: clock)
        pool.add(.init(number: "1563-260924-6", mode: .test, allocatedAt: clock.now))
        var row = try addRow(.rejected, number: "1563-260924-6", to: store, clock: clock)
        row.ezzkResultCode = 203
        row.ezzkResultDescription = "Neplatný podpis záznamu"
        store.upsert(row)

        await checker.runOnce()
        let summary = await checker.submitPending()
        XCTAssertEqual(submitter.calls, 0)
        XCTAssertEqual(summary.feedback, "Žiadny záznam nečaká na odoslanie.")

        let result = await checker.resend(id: row.id)

        XCTAssertEqual(submitter.calls, 1)
        XCTAssertEqual(result.record?.status, .acceptedForProcessing)
        XCTAssertEqual(store.record(id: row.id)?.submissionMessageID, "m-7")
        XCTAssertNil(pool.reusable(mode: .test, at: clock.now, excluding: []))
    }

    /// Production submission is still refused (B3), so production rows are neither sent
    /// nor counted as waiting; they carry the production reason.
    func testProductionRowsAreNeverSentWhileProductionIsRefused() async throws {
        let clock = TestClock("2026-09-24T10:00:00Z")
        let submitter = ScriptedSubmitter([])
        let lookup = ScriptedLookup([])
        let (checker, store) = makeChecker(mode: .production, submitter: submitter, lookup: lookup, clock: clock)
        let row = try addRow(.queuedForSubmission, number: "1563-260924-1", mode: .production, to: store, clock: clock)

        await checker.runOnce()
        let summary = await checker.submitPending()
        let manual = await checker.submit(id: row.id)

        XCTAssertEqual(submitter.calls, 0)
        XCTAssertEqual(lookup.calls, 0)
        XCTAssertEqual(summary.production, 1)
        XCTAssertEqual(summary.waiting, 0)
        let reason = try XCTUnwrap(EZZKError.submissionUnavailable.errorDescription)
        XCTAssertTrue(summary.feedback.contains(reason), summary.feedback)
        XCTAssertEqual(manual.refusal, reason)
        XCTAssertEqual(store.record(id: row.id)?.updatedAt, row.updatedAt)
    }

    // MARK: - Fixtures

    private var storeRoot: URL!
    private var pool: EvidenceNumberPool!
    /// The controller's mode as the checker sees it; tests switch it mid-pass.
    private var currentMode: AppSettings.EZZKMode = .test
    /// The mode of every coordinator the checker built, in order.
    private var coordinatorModes: [AppSettings.EZZKMode] = []

    private func makeChecker(mode: AppSettings.EZZKMode, submitter: any EZZKSubmissionTransport,
                             lookup: any EZZKRecordLookingUp,
                             clock: TestClock) -> (EZZKStatusChecker, LocalEvidenceStore) {
        storeRoot = makeTemporaryDirectory("submission-flow")
        let store = LocalEvidenceStore(directory: storeRoot)
        pool = EvidenceNumberPool(directory: storeRoot)
        currentMode = mode
        coordinatorModes = []
        let now: @Sendable () -> Date = { clock.now }
        let checker = EZZKStatusChecker(
            evidenceStore: store,
            numberPool: pool,
            currentMode: { [unowned self] in self.currentMode },
            makeCoordinator: { [unowned self] rowMode in
                self.coordinatorModes.append(rowMode)
                return EZZKSubmissionCoordinator(submitter: submitter, lookup: lookup, now: now)
            },
            now: now)
        return (checker, store)
    }

    private func poolFileText() throws -> String {
        let data = try Data(contentsOf: storeRoot.appendingPathComponent("Evidence/allocated-numbers.json"))
        return String(decoding: data, as: UTF8.self)
    }

    @discardableResult
    private func addRow(_ status: EvidenceRecord.Status, number: String?,
                        mode: AppSettings.EZZKMode? = .test,
                        to store: LocalEvidenceStore, clock: TestClock) throws -> EvidenceRecord {
        var row = EvidenceRecord(createdAt: clock.now, status: status, direction: .paperToElectronic,
                                 originalName: "Zmluva", newDocumentName: "Zmluva.pdf",
                                 evidenceNumber: number, fingerprintSHA256Hex: "ab", attestationXML: "<x/>",
                                 conversionTime: clock.now, performingPersonName: "JUDr. Test Testovací",
                                 securityElementCount: 0, totalPages: 1, totalSheets: 1,
                                 ezzkMode: mode, evidenceNumberAllocatedAt: clock.now)
        row.recordContainerPath = try store.storeRecordContainer(container, for: row.id)
        store.upsert(row)
        return row
    }
}

/// A clock tests move by hand.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ iso: String) {
        current = ISO8601DateFormatter().date(from: iso)!
    }

    var now: Date { lock.withLock { current } }

    func advance(by interval: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(interval) }
    }
}

/// Answers each submission with the next scripted result and counts the calls.
private final class ScriptedSubmitter: EZZKSubmissionTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<EZZKSOAPSubmissionReceipt, Error>]
    private var count = 0

    init(_ results: [Result<EZZKSOAPSubmissionReceipt, Error>]) {
        self.results = results
    }

    var calls: Int { lock.withLock { count } }

    func submit(_ envelope: ConversionRecordEnvelope) async throws -> EZZKSOAPSubmissionReceipt {
        let next: Result<EZZKSOAPSubmissionReceipt, Error> = lock.withLock {
            count += 1
            return results.isEmpty ? .failure(EZZKError.networkFailure("no scripted reply")) : results.removeFirst()
        }
        return try next.get()
    }
}

/// Holds a submission until the test releases it, so a test can act while a row is in flight.
private final class SuspendingSubmitter: EZZKSubmissionTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let receipt: EZZKSOAPSubmissionReceipt
    private var waiting: CheckedContinuation<Void, Never>?
    private var count = 0

    init(_ receipt: EZZKSOAPSubmissionReceipt) {
        self.receipt = receipt
    }

    var calls: Int { lock.withLock { count } }

    func submit(_ envelope: ConversionRecordEnvelope) async throws -> EZZKSOAPSubmissionReceipt {
        await withCheckedContinuation { continuation in
            lock.withLock {
                count += 1
                waiting = continuation
            }
        }
        return receipt
    }

    func waitUntilSending() async throws {
        for _ in 0..<1000 {
            if lock.withLock({ waiting != nil }) { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("the submission never started")
    }

    func release() {
        let continuation: CheckedContinuation<Void, Never>? = lock.withLock {
            defer { waiting = nil }
            return waiting
        }
        continuation?.resume()
    }
}

/// Answers each lookup with the next scripted result and records the numbers asked for.
private final class ScriptedLookup: EZZKRecordLookingUp, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<EZZKRecordLookup, Error>]
    private var asked: [String] = []

    init(_ results: [Result<EZZKRecordLookup, Error>]) {
        self.results = results
    }

    var calls: Int { lock.withLock { asked.count } }
    var numbers: [String] { lock.withLock { asked } }

    func publicRecord(evidenceNumber: String, executionTime: Date?) async throws -> EZZKRecordLookup {
        let next: Result<EZZKRecordLookup, Error> = lock.withLock {
            asked.append(evidenceNumber)
            // The last scripted reply repeats, so a test states only what differs.
            guard let first = results.first else { return .failure(EZZKError.networkFailure("no scripted reply")) }
            if results.count > 1 { results.removeFirst() }
            return first
        }
        return try next.get()
    }
}

/// Holds the first lookup until the test releases it; later lookups answer at once.
private final class SuspendingLookup: EZZKRecordLookingUp, @unchecked Sendable {
    private let lock = NSLock()
    private let answer: EZZKRecordLookup
    private var waiting: CheckedContinuation<Void, Never>?
    private var held = false
    private var asked: [String] = []

    init(_ answer: EZZKRecordLookup) {
        self.answer = answer
    }

    var numbers: [String] { lock.withLock { asked } }

    func publicRecord(evidenceNumber: String, executionTime: Date?) async throws -> EZZKRecordLookup {
        let hold: Bool = lock.withLock {
            asked.append(evidenceNumber)
            defer { held = true }
            return !held
        }
        if hold {
            await withCheckedContinuation { continuation in
                lock.withLock { waiting = continuation }
            }
        }
        return answer
    }

    func waitUntilLooking() async throws {
        for _ in 0..<1000 {
            if lock.withLock({ waiting != nil }) { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("the lookup never started")
    }

    func release() {
        let continuation: CheckedContinuation<Void, Never>? = lock.withLock {
            defer { waiting = nil }
            return waiting
        }
        continuation?.resume()
    }
}
