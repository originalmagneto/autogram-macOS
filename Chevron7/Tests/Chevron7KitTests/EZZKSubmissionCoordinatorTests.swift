// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation
import os
import XCTest
@testable import Chevron7Kit

final class EZZKSubmissionCoordinatorTests: XCTestCase {
    private let container = Data("PK-signed-record".utf8)

    func testAcceptedSubmissionStoresTheReceipt() async throws {
        let sentAt = date("2026-09-23T10:00:05Z")
        let submitter = FakeSubmitter(.success(EZZKSOAPSubmissionReceipt(messageID: "0f1e2d3c", submittedAt: sentAt)))
        let now = date("2026-09-23T10:00:06Z")
        let coordinator = EZZKSubmissionCoordinator(submitter: submitter, lookup: FakeLookup(),
                                                    now: { now })
        var row = record(.signed)
        row.ezzkResultDescription = "Sieťová chyba pri spojení s EZZK: offline"

        let result = await coordinator.submit(row, container: container)

        XCTAssertEqual(result.status, .acceptedForProcessing)
        XCTAssertEqual(result.submittedAt, sentAt)
        XCTAssertEqual(result.submissionMessageID, "0f1e2d3c")
        XCTAssertEqual(result.ezzkResultCode, 0)
        XCTAssertNil(result.ezzkResultDescription)
        XCTAssertEqual(result.updatedAt, now)
        XCTAssertEqual(submitter.calls, 1)
        XCTAssertEqual(submitter.lastEnvelope?.signedRecordContainer, container)
        XCTAssertEqual(submitter.lastEnvelope?.evidenceNumber, "1563-260923-7")

        // A late row may still be sent.
        let late = await coordinator.submit(record(.late), container: container)
        XCTAssertEqual(late.status, .acceptedForProcessing)
        XCTAssertEqual(submitter.calls, 2)
    }

    func testLostConnectionBecomesUnknownAndIsNotResent() async throws {
        let submitter = FakeSubmitter(.failure(EZZKError.outcomeUnknown))
        let now = date("2026-09-23T10:00:06Z")
        let coordinator = EZZKSubmissionCoordinator(submitter: submitter, lookup: FakeLookup(),
                                                    now: { now })

        var queuedRow = record(.queuedForSubmission)
        queuedRow.lastLookupAt = date("2026-09-23T09:30:00Z")
        let unknown = await coordinator.submit(queuedRow, container: container)
        XCTAssertEqual(unknown.status, .outcomeUnknown)
        XCTAssertEqual(unknown.ezzkResultDescription, EZZKError.outcomeUnknown.localizedDescription)
        XCTAssertEqual(unknown.updatedAt, now)
        XCTAssertNil(unknown.lastLookupAt, "a new send starts a new check cycle")
        XCTAssertEqual(submitter.calls, 1)

        let again = await coordinator.submit(unknown, container: container)
        XCTAssertEqual(again.status, .outcomeUnknown)
        XCTAssertEqual(again.updatedAt, unknown.updatedAt)
        XCTAssertEqual(submitter.calls, 1, "an unknown outcome must be resolved by lookup, never resent")

        // Errors not proven to happen before sending (an unreadable reply may follow an
        // accepted record) also wait for a lookup.
        let maybeSent: [EZZKError] = [
            .invalidResponse, .serverRejected("chyba"), .productionAllocationDisabled,
            .evidenceNumberExpired, .evidenceNumberFromOtherMode,
        ]
        for error in maybeSent {
            let failing = FakeSubmitter(.failure(error))
            let result = await EZZKSubmissionCoordinator(submitter: failing, lookup: FakeLookup(), now: { now })
                .submit(record(.signed), container: container)
            XCTAssertEqual(result.status, .outcomeUnknown, "\(error)")
            XCTAssertEqual(result.ezzkResultDescription, error.localizedDescription, "\(error)")
        }

        // Errors that prove nothing reached EZZK leave the row queued with the reason.
        let nothingSent: [EZZKError] = [
            .networkFailure("offline"), .notConfigured, .authenticationFailed,
            .credentialsRejected(code: "CORE-003"), .accountLocked, .submissionUnavailable,
            .invalidRequest("chýba podpísaný záznam"), .untrustedCertificate,
        ]
        for error in nothingSent {
            let failing = FakeSubmitter(.failure(error))
            let result = await EZZKSubmissionCoordinator(submitter: failing, lookup: FakeLookup(), now: { now })
                .submit(record(.submissionFailed), container: container)
            XCTAssertEqual(result.status, .queuedForSubmission, "\(error)")
            XCTAssertEqual(result.ezzkResultDescription, error.localizedDescription, "\(error)")
            XCTAssertEqual(result.updatedAt, now, "\(error)")

            // A late row stays late.
            let late = await EZZKSubmissionCoordinator(submitter: failing, lookup: FakeLookup(), now: { now })
                .submit(record(.late), container: container)
            XCTAssertEqual(late.status, .late, "\(error)")
            XCTAssertEqual(late.ezzkResultDescription, error.localizedDescription, "\(error)")
        }
    }

    func testUnknownOutcomeIsResolvedByLookupBeforeAnyResend() async throws {
        let now = date("2026-09-23T10:20:00Z")
        let submitter = FakeSubmitter(.failure(EZZKError.outcomeUnknown))

        let found = FakeLookup(.success(EZZKRecordLookup(isProcessed: false, info: nil)))
        let accepted = await EZZKSubmissionCoordinator(submitter: submitter, lookup: found, now: { now })
            .resolveUnknown(record(.outcomeUnknown))
        XCTAssertEqual(accepted.status, .acceptedForProcessing)
        XCTAssertEqual(accepted.ezzkResultCode, 0)
        XCTAssertEqual(accepted.lastLookupAt, now)
        XCTAssertEqual(accepted.updatedAt, now)
        XCTAssertEqual(found.numbers, ["1563-260923-7"])

        let processedLookup = FakeLookup(.success(EZZKRecordLookup(isProcessed: true, info: nil)))
        let processed = await EZZKSubmissionCoordinator(submitter: submitter, lookup: processedLookup, now: { now })
            .resolveUnknown(record(.outcomeUnknown))
        XCTAssertEqual(processed.status, .processed)
        XCTAssertEqual(processed.ezzkResultCode, 0)

        let unknownNumber = FakeLookup(.failure(EZZKError.serviceRejected(code: 105, message: "Záznam neexistuje")))
        let queued = await EZZKSubmissionCoordinator(submitter: submitter, lookup: unknownNumber, now: { now })
            .resolveUnknown(record(.outcomeUnknown))
        XCTAssertEqual(queued.status, .queuedForSubmission)
        XCTAssertEqual(queued.lastLookupAt, now)
        XCTAssertEqual(queued.updatedAt, now)
        XCTAssertEqual(queued.ezzkResultDescription, "EZZK záznam nenašlo, záznam čaká na opätovné odoslanie.")

        // A failed lookup keeps the status but records the attempt, so the next check moves on.
        let offline = FakeLookup(.failure(EZZKError.networkFailure("offline")))
        let offlineCoordinator = EZZKSubmissionCoordinator(submitter: submitter, lookup: offline, now: { now })
        let stillUnknown = await offlineCoordinator.resolveUnknown(record(.outcomeUnknown))
        XCTAssertEqual(stillUnknown.status, .outcomeUnknown)
        XCTAssertEqual(stillUnknown.lastLookupAt, now)
        XCTAssertEqual(stillUnknown.updatedAt, now)
        XCTAssertEqual(offlineCoordinator.nextStatusCheck(for: stillUnknown), date("2026-09-23T11:20:00Z"))

        // No lookup until five minutes after the outcome became unknown.
        let early = FakeLookup(.success(EZZKRecordLookup(isProcessed: true, info: nil)))
        var fresh = record(.outcomeUnknown)
        fresh.updatedAt = date("2026-09-23T10:16:00Z")
        let tooEarly = await EZZKSubmissionCoordinator(submitter: submitter, lookup: early, now: { now })
            .resolveUnknown(fresh)
        XCTAssertEqual(tooEarly.status, .outcomeUnknown)
        XCTAssertEqual(tooEarly.updatedAt, fresh.updatedAt)
        XCTAssertNil(tooEarly.lastLookupAt)
        XCTAssertTrue(early.numbers.isEmpty)
        let later = date("2026-09-23T10:21:00Z")
        let onTime = await EZZKSubmissionCoordinator(submitter: submitter, lookup: early, now: { later })
            .resolveUnknown(fresh)
        XCTAssertEqual(onTime.status, .processed)
        XCTAssertEqual(early.numbers, ["1563-260923-7"])

        // Only unknown rows are resolved.
        let notUnknown = FakeLookup(.success(EZZKRecordLookup(isProcessed: true, info: nil)))
        let signed = await EZZKSubmissionCoordinator(submitter: submitter, lookup: notUnknown, now: { now })
            .resolveUnknown(record(.signed))
        XCTAssertEqual(signed.status, .signed)
        XCTAssertTrue(notUnknown.numbers.isEmpty)
        XCTAssertEqual(submitter.calls, 0, "resolving never sends")
    }

    func testRejectedSubmissionKeepsCodeAndDescription() async throws {
        let now = date("2026-09-23T10:00:06Z")
        let submitter = FakeSubmitter(.failure(EZZKError.serviceRejected(code: 203, message: "Neplatný podpis záznamu")))
        let result = await EZZKSubmissionCoordinator(submitter: submitter, lookup: FakeLookup(), now: { now })
            .submit(record(.signed), container: container)

        XCTAssertEqual(result.status, .rejected)
        XCTAssertEqual(result.ezzkResultCode, 203)
        XCTAssertEqual(result.ezzkResultDescription, "Neplatný podpis záznamu")
        XCTAssertEqual(result.updatedAt, now)
        XCTAssertNil(result.submittedAt)
    }

    func testRecordUnsignedRowIsNeverSubmitted() async throws {
        let now = date("2026-09-23T10:00:06Z")
        let submitter = FakeSubmitter(.success(EZZKSOAPSubmissionReceipt(messageID: "m", submittedAt: now)))
        let coordinator = EZZKSubmissionCoordinator(submitter: submitter, lookup: FakeLookup(), now: { now })

        var failedBefore = record(.submissionFailed)
        failedBefore.ezzkResultDescription = "Sieťová chyba pri spojení s EZZK: offline"
        let missing = await coordinator.submit(failedBefore, container: nil)
        XCTAssertEqual(missing.status, .recordUnsigned)
        XCTAssertEqual(missing.ezzkResultDescription,
                       "Záznam o konverzii nie je podpísaný, preto ho nemožno odoslať do EZZK.")
        XCTAssertEqual(missing.updatedAt, now)

        let unsigned = record(.recordUnsigned)
        let still = await coordinator.submit(unsigned, container: container)
        XCTAssertEqual(still.status, .recordUnsigned)
        XCTAssertEqual(still.updatedAt, unsigned.updatedAt)

        for status in [EvidenceRecord.Status.acceptedForProcessing, .processed, .rejected, .draft, .readyToSign] {
            let row = record(status)
            let result = await coordinator.submit(row, container: container)
            XCTAssertEqual(result.status, status)
            XCTAssertEqual(result.updatedAt, row.updatedAt)
        }
        XCTAssertEqual(submitter.calls, 0)
    }

    func testProcessedAfterLookupCodeZero() async throws {
        let now = date("2026-09-23T11:00:00Z")
        let submitter = FakeSubmitter(.failure(EZZKError.outcomeUnknown))
        var accepted = record(.acceptedForProcessing)
        accepted.submittedAt = date("2026-09-23T10:00:00Z")
        accepted.ezzkResultCode = 0

        let processedLookup = FakeLookup(.success(EZZKRecordLookup(isProcessed: true, info: nil)))
        let processed = await EZZKSubmissionCoordinator(submitter: submitter, lookup: processedLookup, now: { now })
            .refreshStatus(accepted)
        XCTAssertEqual(processed.status, .processed)
        XCTAssertEqual(processed.ezzkResultCode, 0)
        XCTAssertEqual(processed.lastLookupAt, now)
        XCTAssertEqual(processed.updatedAt, now)

        let pendingLookup = FakeLookup(.success(EZZKRecordLookup(isProcessed: false, info: nil)))
        let pending = await EZZKSubmissionCoordinator(submitter: submitter, lookup: pendingLookup, now: { now })
            .refreshStatus(accepted)
        XCTAssertEqual(pending.status, .acceptedForProcessing)
        XCTAssertEqual(pending.lastLookupAt, now)
        XCTAssertEqual(pending.updatedAt, now)

        // A status check never downgrades an accepted row, not even on 105.
        for error in [EZZKError.serviceRejected(code: 105, message: "Záznam neexistuje"), .networkFailure("offline")] {
            let failing = FakeLookup(.failure(error))
            let result = await EZZKSubmissionCoordinator(submitter: submitter, lookup: failing, now: { now })
                .refreshStatus(accepted)
            XCTAssertEqual(result.status, .acceptedForProcessing, "\(error)")
            XCTAssertEqual(result.submittedAt, accepted.submittedAt, "\(error)")
            // The attempt is recorded, so the checker does not retry at once.
            XCTAssertEqual(result.lastLookupAt, now, "\(error)")
            XCTAssertEqual(result.updatedAt, now, "\(error)")
            XCTAssertEqual(EZZKSubmissionCoordinator(submitter: submitter, lookup: failing, now: { now })
                .nextStatusCheck(for: result), date("2026-09-23T12:00:00Z"), "\(error)")
        }

        // Only accepted rows are checked.
        let unused = FakeLookup(.success(EZZKRecordLookup(isProcessed: true, info: nil)))
        let queued = await EZZKSubmissionCoordinator(submitter: submitter, lookup: unused, now: { now })
            .refreshStatus(record(.queuedForSubmission))
        XCTAssertEqual(queued.status, .queuedForSubmission)
        XCTAssertTrue(unused.numbers.isEmpty)
        XCTAssertEqual(submitter.calls, 0)
    }

    func testRowBecomesLateAfterBratislavaMidnightOfItsAllocationDay() {
        // 21:30Z is 23:30 in Bratislava (CEST); Bratislava midnight is 22:00Z.
        let allocatedAt = date("2026-09-23T21:30:00Z")
        func coordinator(at now: Date) -> EZZKSubmissionCoordinator {
            EZZKSubmissionCoordinator(submitter: FakeSubmitter(.failure(EZZKError.outcomeUnknown)),
                                      lookup: FakeLookup(), now: { now })
        }
        let afterMidnight = date("2026-09-23T22:10:00Z")
        let beforeMidnight = date("2026-09-23T21:50:00Z")

        for status in [EvidenceRecord.Status.signed, .queuedForSubmission, .submissionFailed] {
            var row = record(status)
            row.evidenceNumberAllocatedAt = allocatedAt

            let late = coordinator(at: afterMidnight).markLateIfNeeded(row)
            XCTAssertEqual(late.status, .late, "\(status)")
            XCTAssertEqual(late.updatedAt, afterMidnight, "\(status)")

            let onTime = coordinator(at: beforeMidnight).markLateIfNeeded(row)
            XCTAssertEqual(onTime.status, status, "\(status)")
            XCTAssertEqual(onTime.updatedAt, row.updatedAt, "\(status)")
        }

        // Without an allocation time a row is never judged.
        let unknownDay = coordinator(at: afterMidnight).markLateIfNeeded(record(.signed))
        XCTAssertEqual(unknownDay.status, .signed)

        // A clock behind the allocation time is not a later day.
        var skewed = record(.signed)
        skewed.evidenceNumberAllocatedAt = allocatedAt
        XCTAssertEqual(coordinator(at: date("2026-09-22T21:50:00Z")).markLateIfNeeded(skewed).status, .signed)

        // Rows that may already be in EZZK, or are finished, are never marked late.
        for status in [EvidenceRecord.Status.outcomeUnknown, .acceptedForProcessing, .processed,
                       .rejected, .recordUnsigned] {
            var row = record(status)
            row.evidenceNumberAllocatedAt = allocatedAt
            XCTAssertEqual(coordinator(at: afterMidnight).markLateIfNeeded(row).status, status)
        }
    }

    func testNextStatusCheckIsFiveMinutesThenHourly() {
        let coordinator = EZZKSubmissionCoordinator(submitter: FakeSubmitter(.failure(EZZKError.outcomeUnknown)),
                                                    lookup: FakeLookup())
        let submittedAt = date("2026-09-23T10:00:00Z")
        var row = record(.acceptedForProcessing)
        row.submittedAt = submittedAt
        XCTAssertEqual(coordinator.nextStatusCheck(for: row), date("2026-09-23T10:05:00Z"))

        row.lastLookupAt = date("2026-09-23T10:05:30Z")
        XCTAssertEqual(coordinator.nextStatusCheck(for: row), date("2026-09-23T11:05:30Z"))

        // Resolved from an unknown outcome: no receipt time, only the lookup.
        var resolved = record(.acceptedForProcessing)
        resolved.lastLookupAt = date("2026-09-23T12:00:00Z")
        XCTAssertEqual(coordinator.nextStatusCheck(for: resolved), date("2026-09-23T13:00:00Z"))

        // A lookup older than the receipt (from an earlier unknown outcome) does not count.
        var resent = record(.acceptedForProcessing)
        resent.submittedAt = submittedAt
        resent.lastLookupAt = date("2026-09-23T09:40:00Z")
        XCTAssertEqual(coordinator.nextStatusCheck(for: resent), date("2026-09-23T10:05:00Z"))

        // An unknown outcome: five minutes after it arose, then hourly after each lookup.
        var unknown = record(.outcomeUnknown)
        XCTAssertEqual(coordinator.nextStatusCheck(for: unknown), date("2026-09-23T09:05:00Z"))
        unknown.lastLookupAt = date("2026-09-23T09:06:00Z")
        unknown.updatedAt = date("2026-09-23T09:06:00Z")
        XCTAssertEqual(coordinator.nextStatusCheck(for: unknown), date("2026-09-23T10:06:00Z"))
        unknown.lastLookupAt = date("2026-09-23T08:00:00Z")
        XCTAssertEqual(coordinator.nextStatusCheck(for: unknown), date("2026-09-23T09:11:00Z"))

        XCTAssertNil(coordinator.nextStatusCheck(for: record(.acceptedForProcessing)))
        var processed = record(.processed)
        processed.submittedAt = submittedAt
        processed.lastLookupAt = submittedAt
        XCTAssertNil(coordinator.nextStatusCheck(for: processed))
        XCTAssertNil(coordinator.nextStatusCheck(for: record(.queuedForSubmission)))
    }

    func testResubmissionAfterUnknownNumberIsCheckedFiveMinutesAfterItsReceipt() async throws {
        let clock = TestClock(date("2026-09-23T10:00:00Z"))
        let lostSubmitter = FakeSubmitter(.failure(EZZKError.outcomeUnknown))
        let notFound = FakeLookup(.failure(EZZKError.serviceRejected(code: 105, message: "Záznam neexistuje")))
        let first = EZZKSubmissionCoordinator(submitter: lostSubmitter, lookup: notFound, now: { clock.now })

        let unknown = await first.submit(record(.signed), container: container)
        XCTAssertEqual(unknown.status, .outcomeUnknown)
        clock.now = date("2026-09-23T10:05:00Z")
        let queued = await first.resolveUnknown(unknown)
        XCTAssertEqual(queued.status, .queuedForSubmission)
        XCTAssertEqual(queued.lastLookupAt, date("2026-09-23T10:05:00Z"))

        clock.now = date("2026-09-23T10:30:00Z")
        let receipt = EZZKSOAPSubmissionReceipt(messageID: "second", submittedAt: date("2026-09-23T10:30:00Z"))
        let second = EZZKSubmissionCoordinator(submitter: FakeSubmitter(.success(receipt)), lookup: notFound,
                                               now: { clock.now })
        let accepted = await second.submit(queued, container: container)
        XCTAssertEqual(accepted.status, .acceptedForProcessing)
        XCTAssertNil(accepted.lastLookupAt)
        XCTAssertEqual(second.nextStatusCheck(for: accepted), date("2026-09-23T10:35:00Z"))
    }

    func testRowWithoutEvidenceNumberIsNeverSent() async throws {
        let now = date("2026-09-23T10:00:06Z")
        let submitter = FakeSubmitter(.success(EZZKSOAPSubmissionReceipt(messageID: "m", submittedAt: now)))
        let coordinator = EZZKSubmissionCoordinator(submitter: submitter, lookup: FakeLookup(), now: { now })
        for number in [nil, "", "  "] as [String?] {
            var row = record(.signed)
            row.evidenceNumber = number
            let result = await coordinator.submit(row, container: container)
            XCTAssertEqual(result.status, .signed)
            XCTAssertEqual(result.ezzkResultDescription, "Záznam nemá evidenčné číslo.")
            XCTAssertEqual(result.updatedAt, now)
        }
        XCTAssertEqual(submitter.calls, 0)
    }

    func testLateRuleFollowsBratislavaAcrossTheSummerTimeChange() {
        func coordinator(at now: Date) -> EZZKSubmissionCoordinator {
            EZZKSubmissionCoordinator(submitter: FakeSubmitter(.failure(EZZKError.outcomeUnknown)),
                                      lookup: FakeLookup(), now: { now })
        }
        // 2026-10-24 23:30 CEST is late at 00:30 CEST on 25 October (still summer time).
        var summer = record(.signed)
        summer.evidenceNumberAllocatedAt = date("2026-10-24T23:30:00+02:00")
        XCTAssertEqual(coordinator(at: date("2026-10-25T00:30:00+02:00")).markLateIfNeeded(summer).status, .late)
        XCTAssertEqual(coordinator(at: date("2026-10-24T23:50:00+02:00")).markLateIfNeeded(summer).status, .signed)

        // 25 October has 25 hours: 02:30 CET and 23:00 CET are the same Bratislava day.
        var winter = record(.queuedForSubmission)
        winter.evidenceNumberAllocatedAt = date("2026-10-25T02:30:00+01:00")
        XCTAssertEqual(coordinator(at: date("2026-10-25T23:00:00+01:00")).markLateIfNeeded(winter).status,
                       .queuedForSubmission)
        XCTAssertEqual(coordinator(at: date("2026-10-26T00:10:00+01:00")).markLateIfNeeded(winter).status, .late)
    }

    func testLookupFunctionPassesTheNumberThrough() async throws {
        let lookup = EZZKRecordLookupFunction { number in
            EZZKRecordLookup(isProcessed: number == "1563-260923-7", info: nil)
        }
        let result = try await lookup.publicRecord(evidenceNumber: "1563-260923-7")
        XCTAssertTrue(result.isProcessed)
    }

    // MARK: - Helpers

    private func record(_ status: EvidenceRecord.Status) -> EvidenceRecord {
        EvidenceRecord(createdAt: date("2026-09-23T09:00:00Z"), status: status,
                       direction: .paperToElectronic, originalName: "zmluva.pdf",
                       newDocumentName: "zmluva-konverzia.pdf", evidenceNumber: "1563-260923-7",
                       fingerprintSHA256Hex: String(repeating: "a", count: 64),
                       attestationXML: "<Dolozka/>", conversionTime: date("2026-09-23T09:00:00Z"),
                       performingPersonName: "JUDr. Ján Novák", securityElementCount: 0,
                       totalPages: 1, totalSheets: 1, ezzkMode: .test)
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }
}

private final class TestClock: @unchecked Sendable {
    private let state: OSAllocatedUnfairLock<Date>

    init(_ start: Date) {
        state = OSAllocatedUnfairLock(initialState: start)
    }

    var now: Date {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}

private final class FakeSubmitter: EZZKSubmissionTransport, @unchecked Sendable {
    private struct State {
        var calls = 0
        var lastEnvelope: ConversionRecordEnvelope?
    }
    private let result: Result<EZZKSOAPSubmissionReceipt, EZZKError>
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(_ result: Result<EZZKSOAPSubmissionReceipt, EZZKError>) {
        self.result = result
    }

    var calls: Int { state.withLock { $0.calls } }
    var lastEnvelope: ConversionRecordEnvelope? { state.withLock { $0.lastEnvelope } }

    func submit(_ envelope: ConversionRecordEnvelope) async throws -> EZZKSOAPSubmissionReceipt {
        state.withLock {
            $0.calls += 1
            $0.lastEnvelope = envelope
        }
        return try result.get()
    }
}

private final class FakeLookup: EZZKRecordLookingUp, @unchecked Sendable {
    private let result: Result<EZZKRecordLookup, EZZKError>
    private let state = OSAllocatedUnfairLock(initialState: [String]())

    init(_ result: Result<EZZKRecordLookup, EZZKError> = .failure(.networkFailure("not scripted"))) {
        self.result = result
    }

    var numbers: [String] { state.withLock { $0 } }

    func publicRecord(evidenceNumber: String) async throws -> EZZKRecordLookup {
        state.withLock { $0.append(evidenceNumber) }
        return try result.get()
    }
}
