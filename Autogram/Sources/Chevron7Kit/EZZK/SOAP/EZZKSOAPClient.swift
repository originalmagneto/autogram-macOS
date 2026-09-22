import Foundation

public struct EZZKOwnRecord: Sendable {
    public var lookup: EZZKRecordLookup
    /// The stored record object (base64 decoded) when EZZK returns one.
    public var object: Data?
}

/// Talks to one EZZK environment through the Ditec SOAP service. The token lives only
/// in this actor; the password is read from the credentials provider for each login.
public actor EZZKSOAPClient {
    public typealias CredentialsProvider = @Sendable () throws -> EZZKSOAPCredentials?

    public nonisolated let environment: EZZKEnvironment
    private let transport: any EZZKHTTPTransport
    private let credentialsProvider: CredentialsProvider
    private let now: @Sendable () -> Date
    private var token: String?

    public init(environment: EZZKEnvironment, transport: any EZZKHTTPTransport,
                credentials: @escaping CredentialsProvider,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.environment = environment
        self.transport = transport
        self.credentialsProvider = credentials
        self.now = now
    }

    /// Logs in with the provided credentials and returns the account name EZZK reports.
    @discardableResult
    public func logIn() async throws -> String {
        token = nil
        guard let credentials = try credentialsProvider(),
              !credentials.login.isEmpty, !credentials.password.isEmpty else {
            throw EZZKError.notConfigured
        }
        let (data, response) = try await send(.login(login: credentials.login, password: credentials.password))
        guard case let .document(document) = try EZZKSOAPResponseParser.reply(data: data, statusCode: response.statusCode) else {
            throw EZZKError.invalidResponse
        }
        let outcome = EZZKSOAPResponseParser.login(in: document)
        if let code = outcome.errorCode {
            throw code == "CORE-018" ? EZZKError.accountLocked : EZZKError.credentialsRejected(code: code)
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

    public func receive(records: [EZZKRecordAttachment], person: EZZKPerson) async throws {
        guard person.isComplete else { throw EZZKError.notConfigured }
        let document = try await perform(.receive(records: records, person: person))
        try EZZKSOAPResponseParser.requireSuccess(document)
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
        if case let .document(document) = try await attempt(request) {
            return document
        }
        guard request.requiresAuthentication else { throw EZZKError.authenticationFailed }
        // EZZK rejected the token before acting on the request, so one fresh login and
        // one repeat are safe even for consequential calls.
        try await logIn()
        if case let .document(document) = try await attempt(request) {
            return document
        }
        token = nil
        throw EZZKError.authenticationFailed
    }

    private func attempt(_ request: EZZKSOAPRequest) async throws -> EZZKSOAPReply {
        let (data, response) = try await send(request)
        do {
            return try EZZKSOAPResponseParser.reply(data: data, statusCode: response.statusCode)
        } catch EZZKError.networkFailure where request.isConsequential && response.statusCode >= 500 {
            // A gateway or backend timeout (502/504) may mean EZZK already processed a
            // consequential request even though no readable reply came back.
            throw EZZKError.outcomeUnknown
        }
    }

    private func send(_ request: EZZKSOAPRequest) async throws -> (Data, HTTPURLResponse) {
        var urlRequest = request.urlRequest(in: environment)
        if request.requiresAuthentication, let token {
            urlRequest.setValue("IamTokenDescriptor=\(token)", forHTTPHeaderField: "Cookie")
        }
        do {
            return try await transport.send(urlRequest)
        } catch let error as EZZKError {
            throw error
        } catch let error as URLError where Self.neverReachedServer(error) {
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
        [.notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed].contains(error.code)
    }

    static func httpDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.date(from: value)
    }
}
