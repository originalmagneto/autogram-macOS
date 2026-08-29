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
    case authenticationFailed
    case invalidResponse
    case serverRejected(String)
    case networkFailure(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Prístupové údaje do evidencie záznamov (EZZK) nie sú nastavené."
        case .authenticationFailed: return "Prihlásenie do EZZK zlyhalo — skontrolujte IČO, meno a heslo."
        case .invalidResponse: return "Nečitateľná odpoveď EZZK servera."
        case .serverRejected(let reason): return "EZZK zamietlo operáciu: \(reason)"
        case .networkFailure(let detail): return "Sieťová chyba pri spojení s EZZK: \(detail)"
        }
    }
}

public protocol EZZKServicing: Sendable {
    func serverTime() async throws -> Date
    func requestEvidenceNumbers(count: Int) async throws -> [String]
    func submit(_ envelope: ConversionRecordEnvelope) async throws
}

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

    public func submit(_ envelope: ConversionRecordEnvelope) async throws {
        state.withLock { $0.submitted.append(envelope) }
    }

    public var submittedRecords: [ConversionRecordEnvelope] {
        state.withLock { $0.submitted }
    }
}

public struct HTTPSEZZKService: EZZKServicing {
    public var baseURL: URL
    public var credentials: EZZKCredentials
    public var transport: any LLMTransport

    public init(baseURL: URL = URL(string: "https://ezzk.iomo.sk")!,
                credentials: EZZKCredentials,
                transport: any LLMTransport = URLSessionLLMTransport()) {
        self.baseURL = baseURL
        self.credentials = credentials
        self.transport = transport
    }

    public func serverTime() async throws -> Date {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  let dateString = http.value(forHTTPHeaderField: "Date"),
                  let date = Self.httpDateFormatter.date(from: dateString) else {
                throw EZZKError.networkFailure("Chýba hlavička Date.")
            }
            return date
        } catch let error as EZZKError {
            throw error
        } catch {
            throw EZZKError.networkFailure(error.localizedDescription)
        }
    }

    public func requestEvidenceNumbers(count: Int) async throws -> [String] {
        guard credentials.isConfigured else { throw EZZKError.notConfigured }
        let payload: [String: Any] = [
            "ico": credentials.ico,
            "username": credentials.username,
            "password": credentials.password,
            "count": count
        ]
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            let data = try await transport.post(
                url: baseURL.appendingPathComponent("portal/api/evidence-numbers"),
                headers: [:], body: body)
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let numbers = object["evidenceNumbers"] as? [String], !numbers.isEmpty else {
                throw EZZKError.invalidResponse
            }
            return numbers
        } catch let error as AIProviderError {
            if case .httpStatus(let code) = error, code == 401 || code == 403 {
                throw EZZKError.authenticationFailed
            }
            throw EZZKError.networkFailure("\(error)")
        } catch let error as EZZKError {
            throw error
        } catch {
            throw EZZKError.networkFailure(error.localizedDescription)
        }
    }

    public func submit(_ envelope: ConversionRecordEnvelope) async throws {
        guard credentials.isConfigured else { throw EZZKError.notConfigured }
        let payload: [String: Any] = [
            "ico": credentials.ico,
            "username": credentials.username,
            "password": credentials.password,
            "record": [
                "evidenceNumber": envelope.evidenceNumber,
                "fingerprint": envelope.fingerprintSHA256Hex,
                "conversionTime": AttestationClauseGenerator.isoFormatter.string(from: envelope.conversionTime),
                "attestationXml": envelope.attestationXML
            ]
        ]
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            _ = try await transport.post(url: baseURL.appendingPathComponent("portal/api/records"),
                                         headers: [:], body: body)
        } catch let error as AIProviderError {
            if case .httpStatus(409) = error {
                throw EZZKError.serverRejected("Záznam alebo evidenčné číslo už bolo použité.")
            }
            throw EZZKError.networkFailure("\(error)")
        } catch let error as EZZKError {
            throw error
        } catch {
            throw EZZKError.networkFailure(error.localizedDescription)
        }
    }

    static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter
    }()
}

public struct EZZKCredentials: Codable, Sendable, Equatable {
    public var ico: String
    public var username: String
    public var password: String
    public var notificationEmail: String
    public var edeskAddress: String

    public init(ico: String = "", username: String = "", password: String = "",
                notificationEmail: String = "", edeskAddress: String = "") {
        self.ico = ico
        self.username = username
        self.password = password
        self.notificationEmail = notificationEmail
        self.edeskAddress = edeskAddress
    }

    public var isConfigured: Bool { !ico.isEmpty && !username.isEmpty && !password.isEmpty }
}
