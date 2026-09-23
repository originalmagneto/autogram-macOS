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

        let unknown = await coordinator.submit(record(.queuedForSubmission), container: container)
        XCTAssertEqual(unknown.status, .outcomeUnknown)
        XCTAssertEqual(unknown.ezzkResultDescription, EZZKError.outcomeUnknown.localizedDescription)
        XCTAssertEqual(unknown.updatedAt, now)
        XCTAssertEqual(submitter.calls, 1)

        let again = await coordinator.submit(unknown, container: container)
        XCTAssertEqual(again.status, .outcomeUnknown)
        XCTAssertEqual(again.updatedAt, unknown.updatedAt)
        XCTAssertEqual(submitter.calls, 1, "an unknown outcome must be resolved by lookup, never resent")

        // An unreadable reply after sending may hide an accepted record: also unknown.
        let unreadable = FakeSubmitter(.failure(EZZKError.invalidResponse))
        let unreadableResult = await EZZKSubmissionCoordinator(submitter: unreadable, lookup: FakeLookup(), now: { now })
            .submit(record(.signed), container: container)
        XCTAssertEqual(unreadableResult.status, .outcomeUnknown)

        // Errors that prove nothing reached EZZK leave the row queued with the reason.
        let nothingSent: [EZZKError] = [
            .networkFailure("offline"), .notConfigured, .authenticationFailed,
            .credentialsRejected(code: "CORE-003"), .accountLocked, .submissionUnavailable,
            .invalidRequest("chýba podpísaný záznam"),
        ]
        for error in nothingSent {
            let failing = FakeSubmitter(.failure(error))
            let result = await EZZKSubmissionCoordinator(submitter: failing, lookup: FakeLookup(), now: { now })
                .submit(record(.submissionFailed), container: container)
            XCTAssertEqual(result.status, .queuedForSubmission, "\(error)")
            XCTAssertEqual(result.ezzkResultDescription, error.localizedDescription, "\(error)")
            XCTAssertEqual(result.updatedAt, now, "\(error)")
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
        XCTAssertNil(queued.ezzkResultDescription)

        let offline = FakeLookup(.failure(EZZKError.networkFailure("offline")))
        let before = record(.outcomeUnknown)
        let unchanged = await EZZKSubmissionCoordinator(submitter: submitter, lookup: offline, now: { now })
            .resolveUnknown(before)
        XCTAssertEqual(unchanged.status, .outcomeUnknown)
        XCTAssertEqual(unchanged.updatedAt, before.updatedAt)
        XCTAssertNil(unchanged.lastLookupAt)

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

        let missing = await coordinator.submit(record(.signed), container: nil)
        XCTAssertEqual(missing.status, .recordUnsigned)
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
            XCTAssertEqual(result.updatedAt, accepted.updatedAt, "\(error)")
            XCTAssertNil(result.lastLookupAt, "\(error)")
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

        XCTAssertNil(coordinator.nextStatusCheck(for: record(.acceptedForProcessing)))
        var processed = record(.processed)
        processed.submittedAt = submittedAt
        processed.lastLookupAt = submittedAt
        XCTAssertNil(coordinator.nextStatusCheck(for: processed))
        XCTAssertNil(coordinator.nextStatusCheck(for: record(.queuedForSubmission)))
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
