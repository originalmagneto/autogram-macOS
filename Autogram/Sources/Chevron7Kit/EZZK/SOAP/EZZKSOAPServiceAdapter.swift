// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

/// `EZZKServicing` for ZaKo on top of the SOAP client. Built per use with a snapshot of
/// the person from Settings and the numbers already used by local records.
public struct EZZKSOAPServiceAdapter: EZZKServicing {
    public let client: EZZKSOAPClient
    private let person: EZZKPerson
    private let usedEvidenceNumbers: Set<String>

    public init(client: EZZKSOAPClient, person: EZZKPerson, usedEvidenceNumbers: Set<String>) {
        self.client = client
        self.person = person
        self.usedEvidenceNumbers = usedEvidenceNumbers
    }

    public func serverTime() async throws -> Date {
        try await client.serverTime()
    }

    public func requestEvidenceNumbers(count: Int) async throws -> [String] {
        // Records cannot be sent yet. A production number would be consumed at midnight
        // without a record, which breaks the 24-hour duty to report the conversion.
        guard client.environment != .production else { throw EZZKError.productionAllocationDisabled }
        guard count > 0 else { return [] }
        // EZZK returns every unconsumed number of the person, including ones already
        // written into a local record that has not been sent.
        let available = try await client.evidenceNumbers(for: person).filter { !usedEvidenceNumbers.contains($0) }
        guard !available.isEmpty else {
            throw EZZKError.serviceRejected(code: 0, message: "EZZK nevrátilo žiadne nepoužité evidenčné číslo.")
        }
        return Array(available.prefix(count))
    }

    public func submit(_ envelope: ConversionRecordEnvelope) async throws {
        throw EZZKError.submissionUnavailable
    }
}
