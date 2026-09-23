// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

/// Looks up a conversion record in EZZK by its evidence number.
public protocol EZZKRecordLookingUp: Sendable {
    func publicRecord(evidenceNumber: String) async throws -> EZZKRecordLookup
}

/// Wraps a lookup closure, so the app can hand over the account controller's lookup.
public struct EZZKRecordLookupFunction: EZZKRecordLookingUp {
    private let lookup: @Sendable (String) async throws -> EZZKRecordLookup

    public init(_ lookup: @escaping @Sendable (String) async throws -> EZZKRecordLookup) {
        self.lookup = lookup
    }

    public func publicRecord(evidenceNumber: String) async throws -> EZZKRecordLookup {
        try await lookup(evidenceNumber)
    }
}

/// The one set of rules for how a conversion-register row moves between EZZK submission
/// states. The ZaKo flow, the Register screen and the periodic checker all go through it,
/// so a record whose outcome is unknown is never sent twice and a missed day is noticed.
/// Each method returns the row in its new state; the caller stores it. `updatedAt` is set
/// whenever something changes and left alone when the row is returned unchanged.
public struct EZZKSubmissionCoordinator: Sendable {
    /// Unknown evidence number: EZZK has no record under it.
    static let unknownRecordCode = 105
    static let firstStatusCheckDelay: TimeInterval = 5 * 60
    static let statusCheckInterval: TimeInterval = 60 * 60

    private let submitter: any EZZKSubmissionTransport
    private let lookup: any EZZKRecordLookingUp
    private let now: @Sendable () -> Date

    public init(submitter: any EZZKSubmissionTransport, lookup: any EZZKRecordLookingUp,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.submitter = submitter
        self.lookup = lookup
        self.now = now
    }

    /// Sends a pending row and returns it in its new state. Never resends an unknown outcome.
    public func submit(_ record: EvidenceRecord, container: Data?) async -> EvidenceRecord {
        switch record.status {
        case .signed, .queuedForSubmission, .submissionFailed, .late:
            break
        default:
            // `.outcomeUnknown` is resolved by lookup first; finished and unsigned rows stay.
            return record
        }
        var updated = record
        guard let container else {
            updated.status = .recordUnsigned
            updated.updatedAt = now()
            return updated
        }
        var envelope = record.envelope()
        envelope.signedRecordContainer = container
        do {
            let receipt = try await submitter.submit(envelope)
            updated.status = .acceptedForProcessing
            updated.submittedAt = receipt.submittedAt
            updated.submissionMessageID = receipt.messageID
            updated.ezzkResultCode = 0
            updated.ezzkResultDescription = nil
        } catch let error as EZZKError {
            apply(error, to: &updated)
        } catch {
            // Anything unexpected may have happened after the record reached EZZK.
            updated.status = .outcomeUnknown
            updated.ezzkResultCode = nil
            updated.ezzkResultDescription = EZZKError.outcomeUnknown.localizedDescription
        }
        updated.updatedAt = now()
        return updated
    }

    /// Resolves `.outcomeUnknown` by lookup: found -> accepted/processed, 105 -> queued, error -> unchanged.
    public func resolveUnknown(_ record: EvidenceRecord) async -> EvidenceRecord {
        guard record.status == .outcomeUnknown, let number = evidenceNumber(of: record) else { return record }
        var updated = record
        do {
            let result = try await lookup.publicRecord(evidenceNumber: number)
            // EZZK has the record, so the lost submission was accepted, as with a receipt.
            updated.status = result.isProcessed ? .processed : .acceptedForProcessing
            updated.ezzkResultCode = 0
            updated.ezzkResultDescription = nil
        } catch EZZKError.serviceRejected(let code, _) where code == Self.unknownRecordCode {
            // EZZK never got the record, so it may be sent again.
            updated.status = .queuedForSubmission
            updated.ezzkResultCode = nil
            updated.ezzkResultDescription = nil
        } catch {
            return record
        }
        let checkedAt = now()
        updated.lastLookupAt = checkedAt
        updated.updatedAt = checkedAt
        return updated
    }

    /// For `.acceptedForProcessing`: lookup code 0 -> `.processed`; code 1 -> unchanged with `lastLookupAt`.
    /// Any error, 105 included, leaves the row unchanged: EZZK accepted it, so a status
    /// check never moves it back to a state that would send it again.
    public func refreshStatus(_ record: EvidenceRecord) async -> EvidenceRecord {
        guard record.status == .acceptedForProcessing, let number = evidenceNumber(of: record) else { return record }
        guard let result = try? await lookup.publicRecord(evidenceNumber: number) else { return record }
        var updated = record
        if result.isProcessed {
            updated.status = .processed
            updated.ezzkResultCode = 0
        }
        let checkedAt = now()
        updated.lastLookupAt = checkedAt
        updated.updatedAt = checkedAt
        return updated
    }

    /// `.signed`/`.queuedForSubmission`/`.submissionFailed` rows whose allocation day (Bratislava) has passed become `.late`.
    /// A row without an allocation time is never judged.
    public func markLateIfNeeded(_ record: EvidenceRecord) -> EvidenceRecord {
        switch record.status {
        case .signed, .queuedForSubmission, .submissionFailed:
            break
        default:
            return record
        }
        let current = now()
        guard let allocatedAt = record.evidenceNumberAllocatedAt,
              current > allocatedAt,
              !EZZKEvidenceNumberPolicy.isUsable(allocatedAt: allocatedAt, at: current) else { return record }
        var updated = record
        updated.status = .late
        updated.updatedAt = current
        return updated
    }

    /// When the next status check is due: 5 minutes after `submittedAt`, then hourly after `lastLookupAt`.
    /// Nil for every row that is not `.acceptedForProcessing`, and for one with neither time.
    public func nextStatusCheck(for record: EvidenceRecord) -> Date? {
        guard record.status == .acceptedForProcessing else { return nil }
        if let lastLookupAt = record.lastLookupAt {
            return lastLookupAt.addingTimeInterval(Self.statusCheckInterval)
        }
        return record.submittedAt?.addingTimeInterval(Self.firstStatusCheckDelay)
    }

    private func apply(_ error: EZZKError, to record: inout EvidenceRecord) {
        switch error {
        case .serviceRejected(let code, let message):
            record.status = .rejected
            record.ezzkResultCode = code
            record.ezzkResultDescription = message
        case .networkFailure, .notConfigured, .authenticationFailed, .credentialsRejected,
             .accountLocked, .submissionUnavailable, .invalidRequest:
            // Nothing reached EZZK: the row stays in the queue with the reason.
            record.status = .queuedForSubmission
            record.ezzkResultCode = nil
            record.ezzkResultDescription = error.localizedDescription
        case .outcomeUnknown, .invalidResponse, .serverRejected, .untrustedCertificate,
             .productionAllocationDisabled, .evidenceNumberExpired, .evidenceNumberFromOtherMode:
            // Not proven unsent (an unreadable reply may follow an accepted record), so the
            // row waits for a lookup instead of being sent again.
            record.status = .outcomeUnknown
            record.ezzkResultCode = nil
            record.ezzkResultDescription = error.localizedDescription
        }
    }

    private func evidenceNumber(of record: EvidenceRecord) -> String? {
        let number = record.evidenceNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return number.isEmpty ? nil : number
    }
}
