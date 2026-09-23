// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import CryptoKit
import Foundation

public struct EZZKOwnRecord: Sendable {
    public var lookup: EZZKRecordLookup
    /// The stored record object (base64 decoded) when EZZK returns one.
    public var object: Data?
}

/// What was handed to EZZK for one `ReceiveConversionRecord` call.
public struct EZZKSOAPSubmissionReceipt: Equatable, Sendable {
    /// The `MessageId` sent in the request body (lowercased UUID).
    public var messageID: String
    public var submittedAt: Date

    public init(messageID: String, submittedAt: Date) {
        self.messageID = messageID
        self.submittedAt = submittedAt
    }
}

/// Talks to one EZZK environment through the Ditec SOAP service. The token lives only
/// in this actor; the password is read from the credentials provider for each login.
/// Concurrent calls share one login, and credentials EZZK rejected are never sent again
/// by this client, so repeated attempts cannot lock the advocate's account.
public actor EZZKSOAPClient {
    public typealias CredentialsProvider = @Sendable () throws -> EZZKSOAPCredentials?

    public nonisolated let environment: EZZKEnvironment
    private let transport: any EZZKHTTPTransport
    private let credentialsProvider: CredentialsProvider
    private let now: @Sendable () -> Date
    private var token: String?
    private var loginTask: Task<String, Error>?
    /// SHA-256 of the credentials EZZK last rejected and the error it gave, in memory only.
    private var rejectedCredentials: (fingerprint: SHA256.Digest, error: EZZKError)?

    public init(environment: EZZKEnvironment, transport: any EZZKHTTPTransport,
                credentials: @escaping CredentialsProvider,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.environment = environment
        self.transport = transport
        self.credentialsProvider = credentials
        self.now = now
    }

    /// Logs in with the provided credentials and returns the account name EZZK reports.
    /// A call made while another login is in flight waits for that login instead of
    /// starting a second one.
    @discardableResult
    public func logIn() async throws -> String {
        if let loginTask { return try await loginTask.value }
        // An unstructured task: a caller that is cancelled while waiting does not cancel
        // the login the other callers wait for.
        let task = Task<String, Error> {
            defer { loginTask = nil }
            return try await performLogIn()
        }
        loginTask = task
        return try await task.value
    }

    /// Keeps the current token until the login ends: a call still using it must not see it
    /// vanish mid-flight. The token is replaced on success and dropped when the credentials
    /// are missing or rejected.
    private func performLogIn() async throws -> String {
        guard let credentials = try credentialsProvider(),
              !credentials.login.isEmpty, !credentials.password.isEmpty else {
            token = nil
            throw EZZKError.notConfigured
        }
        let fingerprint = SHA256.hash(data: Data((credentials.login + "\u{0}" + credentials.password).utf8))
        if let rejectedCredentials {
            if rejectedCredentials.fingerprint == fingerprint {
                token = nil
                throw rejectedCredentials.error
            }
            self.rejectedCredentials = nil
        }
        let (data, response) = try await send(.login(login: credentials.login, password: credentials.password))
        guard case let .document(document) = try EZZKSOAPResponseParser.reply(data: data, statusCode: response.statusCode) else {
            throw EZZKError.invalidResponse
        }
        let outcome = EZZKSOAPResponseParser.login(in: document)
        if let code = outcome.errorCode {
            let error = code == "CORE-018" ? EZZKError.accountLocked : EZZKError.credentialsRejected(code: code)
            rejectedCredentials = (fingerprint, error)
            token = nil
            throw error
        }
        guard let newToken = outcome.token else { throw EZZKError.invalidResponse }
        token = newToken
        return outcome.accountName ?? credentials.login
    }

    public func serverTime() async throws -> Date {
        let (data, response) = try await send(.serverTime())
        guard case .document = try EZZKSOAPResponseParser.reply(data: data, statusCode: response.statusCode) else {
            throw EZZKError.invalidResponse
        }
        guard let header = response.value(forHTTPHeaderField: "Date"), let date = Self.httpDate(header) else {
            throw EZZKError.networkFailure("Chýba hlavička Date.")
        }
        return date
    }

    public func evidenceNumbers(for person: EZZKPerson) async throws -> [String] {
        guard person.isComplete else { throw EZZKError.notConfigured }
        let document = try await perform(.evidenceNumbers(person: person))
        try EZZKSOAPResponseParser.requireSuccess(document)
        return EZZKSOAPResponseParser.evidenceNumbers(in: document)
    }

    public func consume(evidenceNumber: String?, person: EZZKPerson) async throws {
        guard person.isComplete else { throw EZZKError.notConfigured }
        let document = try await perform(.consume(evidenceNumber: evidenceNumber, person: person))
        try EZZKSOAPResponseParser.requireSuccess(document)
    }

    public func publicRecord(evidenceNumber: String, executionTime: Date? = nil) async throws -> EZZKRecordLookup {
        let document = try await perform(.publicRecord(evidenceNumber: evidenceNumber,
                                                       executionTime: executionTime, at: now()))
        let code = try EZZKSOAPResponseParser.requireSuccess(document, accepting: [0, 1])
        return EZZKRecordLookup(isProcessed: code == 0, info: EZZKSOAPResponseParser.recordInfo(in: document))
    }

    public func record(evidenceNumber: String, purpose: EZZKRecordPurpose,
                       executionTime: Date? = nil) async throws -> EZZKOwnRecord {
        let document = try await perform(.record(evidenceNumber: evidenceNumber, purpose: purpose,
                                                 executionTime: executionTime, at: now()))
        let code = try EZZKSOAPResponseParser.requireSuccess(document, accepting: [0, 1])
        return EZZKOwnRecord(
            lookup: EZZKRecordLookup(isProcessed: code == 0, info: EZZKSOAPResponseParser.recordInfo(in: document)),
            object: EZZKSOAPResponseParser.objectData(in: document))
    }

    /// Hands the records to EZZK. Only when EZZK accepts them does it return a receipt: the
    /// `MessageId` sent in the body and the time the reply arrived. A failure throws and
    /// carries no receipt.
    public func receive(records: [EZZKRecordAttachment], person: EZZKPerson) async throws -> EZZKSOAPSubmissionReceipt {
        guard person.isComplete else { throw EZZKError.notConfigured }
        let messageID = UUID()
        let document = try await perform(.receive(records: records, person: person, messageID: messageID))
        let submittedAt = now()
        try EZZKSOAPResponseParser.requireSuccess(document)
        return EZZKSOAPSubmissionReceipt(messageID: messageID.uuidString.lowercased(), submittedAt: submittedAt)
    }

    private func perform(_ request: EZZKSOAPRequest) async throws -> XMLDocument {
        // Consequential calls must be impossible by construction on production: no login,
        // no network use, regardless of what the transport would have replied.
        if request.isConsequential, environment == .production {
            throw request.operation == EZZKSOAPRequest.receiveOperation
                ? EZZKError.submissionUnavailable
                : EZZKError.productionAllocationDisabled
        }
        if request.requiresAuthentication, token == nil {
            try await logIn()
        }
        let sentToken = token
        if case let .document(document) = try await attempt(request, sessionToken: sentToken) {
            return document
        }
        guard request.requiresAuthentication else { throw EZZKError.authenticationFailed }
        // EZZK rejected the token before acting on the request, so one fresh login and
        // one repeat are safe even for consequential calls. Another call may already have
        // replaced the rejected token meanwhile; then the repeat uses the new one.
        if token == nil || token == sentToken {
            try await logIn()
        }
        let retryToken = token
        if case let .document(document) = try await attempt(request, sessionToken: retryToken) {
            return document
        }
        if token == retryToken { token = nil }
        throw EZZKError.authenticationFailed
    }

    private func attempt(_ request: EZZKSOAPRequest, sessionToken: String?) async throws -> EZZKSOAPReply {
        let (data, response) = try await send(request, sessionToken: sessionToken)
        do {
            return try EZZKSOAPResponseParser.reply(data: data, statusCode: response.statusCode)
        } catch EZZKError.networkFailure where request.isConsequential && response.statusCode >= 500 {
            // A gateway or backend timeout (502/504) may mean EZZK already processed a
            // consequential request even though no readable reply came back.
            throw EZZKError.outcomeUnknown
        }
    }

    /// Sends the request with the given token as cookie, so the caller knows exactly which
    /// token EZZK saw even when another call replaces `token` meanwhile.
    private func send(_ request: EZZKSOAPRequest, sessionToken: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var urlRequest = request.urlRequest(in: environment)
        if request.requiresAuthentication, let sessionToken {
            urlRequest.setValue("IamTokenDescriptor=\(sessionToken)", forHTTPHeaderField: "Cookie")
        }
        do {
            return try await transport.send(urlRequest)
        } catch let error as EZZKError {
            throw error
        } catch let error as URLError where Self.neverReachedServer(error) {
            // Only a failure to reach the host proves EZZK never saw the request. Any other
            // failure (a lost connection, the device going offline) may have happened after
            // the request was sent.
            throw EZZKError.networkFailure(error.localizedDescription)
        } catch is CancellationError where !request.isConsequential {
            // A cancelled read is not a network failure; the caller decides what to show.
            throw CancellationError()
        } catch {
            // A consequential request may have been processed although no reply arrived.
            if request.isConsequential { throw EZZKError.outcomeUnknown }
            throw EZZKError.networkFailure(error.localizedDescription)
        }
    }

    static func neverReachedServer(_ error: URLError) -> Bool {
        [.cannotFindHost, .cannotConnectToHost, .dnsLookupFailed].contains(error.code)
    }

    static func httpDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.date(from: value)
    }
}
