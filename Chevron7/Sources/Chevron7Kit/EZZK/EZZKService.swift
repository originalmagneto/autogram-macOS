// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation
import os

public struct ConversionRecordEnvelope: Codable, Sendable, Identifiable {
    public var id: UUID
    public var evidenceNumber: String
    public var direction: ConversionDirection
    public var originalName: String
    public var newDocumentName: String
    public var attestationXML: String
    public var fingerprintSHA256Hex: String
    public var conversionTime: Date
    public var signedAt: Date?
    public var submittedToCEZZKAt: Date?
    public var formPack: FormPackStamp?
    public var securityReview: SecurityReviewStamp?
    /// The signed record container (ASiC-E) `ReceiveConversionRecord` sends as the attachment.
    /// Not part of any persisted record: it is produced right before submission.
    public var signedRecordContainer: Data?

    public init(id: UUID = UUID(), evidenceNumber: String, direction: ConversionDirection,
                originalName: String, newDocumentName: String,
                attestationXML: String, fingerprintSHA256Hex: String,
                conversionTime: Date) {
        self.id = id
        self.evidenceNumber = evidenceNumber
        self.direction = direction
        self.originalName = originalName
        self.newDocumentName = newDocumentName
        self.attestationXML = attestationXML
        self.fingerprintSHA256Hex = fingerprintSHA256Hex
        self.conversionTime = conversionTime
        self.signedAt = nil
        self.submittedToCEZZKAt = nil
        self.formPack = nil
        self.securityReview = nil
        self.signedRecordContainer = nil
    }

    public init(id: UUID = UUID(), evidenceNumber: String, direction: ConversionDirection,
                originalName: String, newDocumentName: String,
                attestationXML: String, fingerprintSHA256Hex: String,
                conversionTime: Date, formPack: FormPackStamp?,
                securityReview: SecurityReviewStamp? = nil) {
        self.init(id: id, evidenceNumber: evidenceNumber, direction: direction,
                  originalName: originalName, newDocumentName: newDocumentName,
                  attestationXML: attestationXML,
                  fingerprintSHA256Hex: fingerprintSHA256Hex,
                  conversionTime: conversionTime)
        self.formPack = formPack
        self.securityReview = securityReview
    }
}

public enum EZZKError: LocalizedError, Equatable, Sendable {
    case notConfigured
    /// EZZK still rejects the token after one fresh login (also used by the dormant OAuth client).
    case authenticationFailed
    case invalidResponse
    case serverRejected(String)
    case networkFailure(String)
    case credentialsRejected(code: String)
    case accountLocked
    case serviceRejected(code: Int, message: String)
    case invalidRequest(String)
    case untrustedCertificate
    case productionAllocationDisabled
    case submissionUnavailable
    case evidenceNumberExpired
    case evidenceNumberFromOtherMode
    case outcomeUnknown

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Prístupové údaje do EZZK nie sú nastavené. Zadajte ich v Nastaveniach."
        case .authenticationFailed:
            return "Prihlásenie do EZZK zlyhalo. Prihláste sa znova v Nastaveniach."
        case .invalidResponse:
            return "Nečitateľná odpoveď EZZK servera."
        case .serverRejected(let reason):
            return "EZZK zamietlo operáciu: \(reason)"
        case .networkFailure(let detail):
            return "Sieťová chyba pri spojení s EZZK: \(detail)"
        case .credentialsRejected(let code):
            return code == "CORE-003"
                ? "Nesprávne prihlasovacie meno alebo heslo."
                : "EZZK odmietlo prihlásenie (\(code))."
        case .accountLocked:
            return "Účet v EZZK je zablokovaný."
        case .serviceRejected(let code, let message):
            return "EZZK odmietlo požiadavku (kód \(code)): \(message)"
        case .invalidRequest(let detail):
            return "EZZK nerozumie požiadavke aplikácie Chevron7 (\(detail)). Ide o chybu aplikácie."
        case .untrustedCertificate:
            return "Certifikát testovacieho prostredia EZZK sa zmenil. Aktualizujte odtlačok v aplikácii."
        case .productionAllocationDisabled:
            return "Pridelenie čísel na produkcii sa zapne spolu s odosielaním záznamov."
        case .submissionUnavailable:
            return "Odosielanie záznamov do EZZK zatiaľ nie je dostupné. Príde v ďalšej verzii."
        case .evidenceNumberExpired:
            return "Evidenčné číslo bolo pridelené v iný deň a EZZK ho o polnoci spotreboval. Získajte nové číslo."
        case .evidenceNumberFromOtherMode:
            return "Evidenčné číslo bolo získané v inom režime EZZK. Získajte nové číslo."
        case .outcomeUnknown:
            return "Spojenie s EZZK sa prerušilo a nie je isté, či EZZK požiadavku spracovalo. Pred opakovaním overte stav v EZZK."
        }
    }
}

public protocol EZZKServerClock: Sendable {
    func serverTime() async throws -> Date
}

public protocol EZZKEvidenceNumberProvider: Sendable {
    func requestEvidenceNumbers(count: Int) async throws -> [String]
}

public protocol EZZKSubmissionTransport: Sendable {
    func submit(_ envelope: ConversionRecordEnvelope) async throws -> EZZKSOAPSubmissionReceipt
}

public protocol EZZKServicing: EZZKServerClock, EZZKEvidenceNumberProvider, EZZKSubmissionTransport {}

public final class MockEZZKService: EZZKServicing, @unchecked Sendable {
    private struct State {
        var counter: Int
        var submitted: [ConversionRecordEnvelope] = []
    }
    private let state = OSAllocatedUnfairLock(initialState: State(counter: 0))
    public let registryCode: String

    public init(registryCode: String = "1563", startingNumber: Int = 1) {
        self.registryCode = registryCode
        _ = state.withLock { $0.counter = startingNumber }
    }

    public func serverTime() async throws -> Date { Date() }

    public func requestEvidenceNumbers(count: Int) async throws -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyMMdd"
        let dayStamp = formatter.string(from: Date())
        return state.withLock { st -> [String] in
            var numbers: [String] = []
            for _ in 0..<count {
                numbers.append(String(format: "%@-%@-%d", registryCode, dayStamp, st.counter))
                st.counter += 1
            }
            return numbers
        }
    }

    public func submit(_ envelope: ConversionRecordEnvelope) async throws -> EZZKSOAPSubmissionReceipt {
        state.withLock { $0.submitted.append(envelope) }
        return EZZKSOAPSubmissionReceipt(messageID: UUID().uuidString.lowercased(), submittedAt: Date())
    }

    public var submittedRecords: [ConversionRecordEnvelope] {
        state.withLock { $0.submitted }
    }
}

