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
        // Production numbers are allocated only when the production policy allows sending,
        // because an unused production number lapses at midnight.
        if let refusal = client.productionPolicy.refusal(environment: client.environment, submitting: false) {
            throw refusal
        }
        guard count > 0 else { return [] }
        // EZZK allocates and returns one new number per call and never returns a number it
        // already gave out (Revision 5, verified live). Dropping numbers a local register row
        // already carries is a guard, not a rule: should EZZK ever repeat one, it is never
        // handed to a second conversion.
        let returned = try await client.evidenceNumbers(for: person)
        guard !returned.isEmpty else {
            throw EZZKError.serviceRejected(code: 0, message: Self.noNumberReturnedMessage)
        }
        let available = returned.filter { !usedEvidenceNumbers.contains($0) }
        guard !available.isEmpty else {
            throw EZZKError.serviceRejected(code: 0, message: Self.numbersAlreadyInRegisterMessage(returned))
        }
        return Array(available.prefix(count))
    }

    static let noNumberReturnedMessage =
        "EZZK odpovedalo úspešne, ale nevrátilo žiadne evidenčné číslo."
    /// EZZK never gives a number out twice, so this names a register row of the same mode
    /// that already carries it, for the person to check.
    static func numbersAlreadyInRegisterMessage(_ numbers: [String]) -> String {
        "EZZK pridelilo číslo \(numbers.joined(separator: ", ")), ale rovnaké číslo už nesie riadok v Registri konverzií. Skontrolujte ten riadok, aplikácia číslo nepoužila."
    }

    public func submit(_ envelope: ConversionRecordEnvelope) async throws -> EZZKSOAPSubmissionReceipt {
        // Refuse production before the container check: no caller sets
        // `signedRecordContainer` yet, and a missing container must not read as an
        // application bug (`invalidRequest`) when the real reason submission is
        // impossible today is that the production policy does not allow sending.
        if let refusal = client.productionPolicy.refusal(environment: client.environment, submitting: true) {
            throw refusal
        }
        guard let container = envelope.signedRecordContainer else {
            throw EZZKError.invalidRequest("chýba podpísaný záznam")
        }
        let attachment = EZZKRecordAttachment(evidenceNumber: envelope.evidenceNumber,
                                              mimeType: "application/vnd.etsi.asic-e+zip",
                                              data: container)
        return try await client.receive(records: [attachment], person: person)
    }
}
