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
    /// The number is used by several records: EZZK stores duplicates rather than refusing
    /// them (ruling R17). As a submission result it does not say what became of this
    /// record, so the row waits for a lookup; as a lookup result EZZK holds a record.
    static let severalRecordsCode = 106
    /// The first check (of an accepted record, or of an unknown outcome) waits this long,
    /// so EZZK has registered a record it was still receiving.
    static let firstStatusCheckDelay: TimeInterval = 5 * 60
    static let statusCheckInterval: TimeInterval = 60 * 60
    static let missingEvidenceNumberReason = "Záznam nemá evidenčné číslo."
    static let unsignedRecordReason = "Záznam o konverzii nie je podpísaný, preto ho nemožno odoslať do EZZK."
    static let requeuedReason = "EZZK záznam nenašlo, záznam čaká na opätovné odoslanie."

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
    /// A row without an evidence number is never sent (only its description changes).
    public func submit(_ record: EvidenceRecord, container: Data?) async -> EvidenceRecord {
        switch record.status {
        case .signed, .queuedForSubmission, .submissionFailed, .late:
            break
        default:
            // `.outcomeUnknown` is resolved by lookup first; finished, rejected and unsigned
            // rows stay (a rejected row is only ever resent by hand, see `resend`).
            return record
        }
        return await send(record, container: container)
    }

    /// Whether the advocate may send a rejected row again (ruling R18): EZZK refused the
    /// record when it was submitted, so it stored nothing and a resend cannot duplicate it.
    /// A row refused after EZZK received it is never resent: after a receipt (`submittedAt`),
    /// or when a lookup answered with a refusal code (`lastLookupAt`, set by `resolveUnknown`
    /// and `refreshStatus`; a refusal at submission clears it).
    public static func canResend(_ record: EvidenceRecord) -> Bool {
        record.status == .rejected && record.submittedAt == nil && record.lastLookupAt == nil
    }

    /// "Odoslať znova" in the Register: sends a row `canResend` allows, exactly as `submit`
    /// sends a pending row. Any other row is returned unchanged. Only a manual action calls
    /// this; the periodic check never resends a rejected row.
    public func resend(_ record: EvidenceRecord, container: Data?) async -> EvidenceRecord {
        guard Self.canResend(record) else { return record }
        return await send(record, container: container)
    }

    private func send(_ record: EvidenceRecord, container: Data?) async -> EvidenceRecord {
        var updated = record
        guard evidenceNumber(of: record) != nil else {
            guard record.ezzkResultDescription != Self.missingEvidenceNumberReason else { return record }
            updated.ezzkResultDescription = Self.missingEvidenceNumberReason
            updated.updatedAt = now()
            return updated
        }
        guard let container else {
            updated.status = .recordUnsigned
            updated.ezzkResultCode = nil
            updated.ezzkResultDescription = Self.unsignedRecordReason
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
            // A lookup from an earlier attempt must not delay the first check of this one.
            updated.lastLookupAt = nil
        } catch let error as EZZKError {
            apply(error, to: &updated)
        } catch {
            // Anything unexpected may have happened after the record reached EZZK.
            markUnknown(&updated, description: EZZKError.outcomeUnknown.localizedDescription)
        }
        updated.updatedAt = now()
        return updated
    }

    /// Resolves `.outcomeUnknown` by lookup: found -> accepted/processed, 105 -> queued,
    /// 106 -> accepted (EZZK holds records under the number), error -> unchanged.
    /// Any other EZZK result code means EZZK processed and refused the record: `.rejected`
    /// with EZZK's code and description. Does nothing until five minutes after the row last changed, so EZZK has registered a
    /// record it may still have been receiving (a 105 before that could cause a duplicate).
    /// A failed lookup keeps the status and records the attempt in `lastLookupAt`.
    public func resolveUnknown(_ record: EvidenceRecord) async -> EvidenceRecord {
        guard record.status == .outcomeUnknown, let number = evidenceNumber(of: record) else { return record }
        let current = now()
        guard current >= record.updatedAt.addingTimeInterval(Self.firstStatusCheckDelay) else { return record }
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
            updated.ezzkResultDescription = Self.requeuedReason
        } catch EZZKError.serviceRejected(let code, let message) where code == Self.severalRecordsCode {
            // EZZK holds a record under the number (more than one), so the lost submission
            // was accepted; EZZK's code and text stay on the row.
            updated.status = .acceptedForProcessing
            updated.ezzkResultCode = code
            updated.ezzkResultDescription = message
        } catch EZZKError.serviceRejected(let code, let message) {
            markRejected(&updated, code: code, message: message)
        } catch {
            // Still unknown; only the attempt is recorded.
        }
        updated.lastLookupAt = current
        updated.updatedAt = current
        return updated
    }

    /// For `.acceptedForProcessing`: lookup code 0 -> `.processed`; code 1 -> unchanged with `lastLookupAt`;
    /// code 106 -> still accepted, with EZZK's code and text. A result code other than 0, 1, 105 and 106 means EZZK processed and refused the record
    /// (for example 12 "Neznámy obsah"): `.rejected` with EZZK's code and description.
    /// Every other error, 105 included, keeps the status: EZZK accepted the record, so a
    /// status check never moves it back to a state that would send it again. Every attempt,
    /// failed or not, is recorded in `lastLookupAt`, so the next check waits an hour.
    public func refreshStatus(_ record: EvidenceRecord) async -> EvidenceRecord {
        guard record.status == .acceptedForProcessing, let number = evidenceNumber(of: record) else { return record }
        var updated = record
        do {
            if try await lookup.publicRecord(evidenceNumber: number).isProcessed {
                updated.status = .processed
                updated.ezzkResultCode = 0
                // An earlier 106 text no longer describes the row.
                updated.ezzkResultDescription = nil
            }
        } catch EZZKError.serviceRejected(let code, let message) where code == Self.severalRecordsCode {
            // EZZK holds the record (under a number used more than once): still accepted,
            // with EZZK's code and text on the row.
            updated.ezzkResultCode = code
            updated.ezzkResultDescription = message
        } catch EZZKError.serviceRejected(let code, let message) where code != Self.unknownRecordCode {
            markRejected(&updated, code: code, message: message)
        } catch {
            // Try again later; only the attempt is recorded.
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
    /// For `.outcomeUnknown` (see `resolveUnknown`): 5 minutes after `updatedAt`, then hourly
    /// after `lastLookupAt`. Never earlier than the last attempt plus its interval; only a
    /// lookup at or after the submission counts. Nil for every other row, and for an accepted
    /// row with neither time.
    public func nextStatusCheck(for record: EvidenceRecord) -> Date? {
        switch record.status {
        case .acceptedForProcessing:
            let first = record.submittedAt?.addingTimeInterval(Self.firstStatusCheckDelay)
            guard let lastLookupAt = record.lastLookupAt,
                  record.submittedAt.map({ lastLookupAt >= $0 }) ?? true else { return first }
            return lastLookupAt.addingTimeInterval(Self.statusCheckInterval)
        case .outcomeUnknown:
            let first = record.updatedAt.addingTimeInterval(Self.firstStatusCheckDelay)
            guard let lastLookupAt = record.lastLookupAt else { return first }
            return max(first, lastLookupAt.addingTimeInterval(Self.statusCheckInterval))
        default:
            return nil
        }
    }

    private func apply(_ error: EZZKError, to record: inout EvidenceRecord) {
        switch error {
        case .serviceRejected(let code, let message) where code == Self.severalRecordsCode:
            // EZZK may have stored this record as one more under the number, so it waits for
            // a lookup instead of being refused or sent again.
            markUnknown(&record, description: "EZZK vrátilo kód \(code): \(message)")
        case .serviceRejected(let code, let message):
            markRejected(&record, code: code, message: message)
            // Refused at submission: a lookup of an earlier attempt does not describe it,
            // and `canResend` reads a set `lastLookupAt` as a refusal after receipt.
            record.lastLookupAt = nil
        case .networkFailure, .notConfigured, .authenticationFailed, .credentialsRejected,
             .accountLocked, .submissionUnavailable, .invalidRequest, .untrustedCertificate,
             .demoSignatureOutsideDemo:
            // Nothing reached EZZK: the host was unreachable, the login or the certificate
            // pin failed before the request was written, sending is disabled, or WCF refused
            // the body (DeserializationFailed, ActionMismatch) before the operation ran.
            // The row stays pending with the reason; a late row stays late.
            if record.status != .late { record.status = .queuedForSubmission }
            record.ezzkResultCode = nil
            record.ezzkResultDescription = error.localizedDescription
        case .outcomeUnknown, .invalidResponse, .serverRejected, .productionAllocationDisabled,
             .evidenceNumberExpired, .evidenceNumberFromOtherMode:
            // Not proven unsent (an unreadable reply may follow an accepted record), so the
            // row waits for a lookup instead of being sent again.
            markUnknown(&record, description: error.localizedDescription)
        }
    }

    private func markRejected(_ record: inout EvidenceRecord, code: Int, message: String) {
        record.status = .rejected
        record.ezzkResultCode = code
        record.ezzkResultDescription = message
    }

    private func markUnknown(_ record: inout EvidenceRecord, description: String) {
        record.status = .outcomeUnknown
        record.ezzkResultCode = nil
        record.ezzkResultDescription = description
        // A new check cycle starts: the first lookup waits five minutes after this attempt.
        record.lastLookupAt = nil
    }

    private func evidenceNumber(of record: EvidenceRecord) -> String? {
        let number = record.evidenceNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return number.isEmpty ? nil : number
    }
}
