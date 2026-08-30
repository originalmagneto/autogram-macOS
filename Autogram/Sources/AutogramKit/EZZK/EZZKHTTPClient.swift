import Foundation

public protocol EZZKHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionEZZKHTTPTransport: EZZKHTTPTransport, Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EZZKError.invalidResponse
        }
        return (data, httpResponse)
    }
}

public actor EZZKClient: EZZKServerClock, EZZKEvidenceNumberProvider {
    private static let asiceMIMEType = "application/vnd.etsi.asic-e+zip"
    private static let refreshSafetyWindow: TimeInterval = 30
    private static let maximumReadAttempts = 4
    private static let retryDelayNanoseconds: [UInt64] = [50_000_000, 100_000_000, 200_000_000]

    private let environment: EZZKEnvironment
    private let oauth: EZZKOAuthConfiguration
    private let tokenStore: any EZZKTokenStoring
    private let transport: any EZZKHTTPTransport
    private var cachedToken: EZZKTokenSet?
    private var operationInProgress = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        environment: EZZKEnvironment,
        oauth: EZZKOAuthConfiguration,
        tokenStore: any EZZKTokenStoring,
        transport: any EZZKHTTPTransport
    ) {
        self.environment = environment
        self.oauth = oauth
        self.tokenStore = tokenStore
        self.transport = transport
    }

    public func availableEvidenceNumbers() async throws -> EZZKAvailableEvidenceResponse {
        try await withSerializedOperation {
            let (data, _) = try await self.perform(method: "GET", path: "ec", body: nil, readOnly: true)
            do {
                return try JSONDecoder().decode(EZZKAvailableEvidenceResponse.self, from: data)
            } catch {
                throw EZZKError.invalidResponse
            }
        }
    }

    public func consumedEvidenceNumbers() async throws -> Data {
        try await withSerializedOperation {
            try await self.perform(method: "GET", path: "ec/consumed", body: nil, readOnly: true).data
        }
    }

    public func record(evidenceNumber: String) async throws -> Data {
        try await withSerializedOperation {
            try await self.perform(method: "GET", path: self.recordPath(evidenceNumber, suffix: nil), body: nil, readOnly: true).data
        }
    }

    public func original(evidenceNumber: String) async throws -> Data {
        try await withSerializedOperation {
            try await self.perform(method: "GET", path: self.recordPath(evidenceNumber, suffix: "original"), body: nil, readOnly: true).data
        }
    }

    public func history(query: [URLQueryItem]) async throws -> Data {
        try await withSerializedOperation {
            guard query.allSatisfy(self.isSafeQueryItem) else { throw EZZKError.invalidResponse }
            let (data, _) = try await self.perform(method: "GET", path: "zzk", query: query, body: nil, readOnly: true)
            return data
        }
    }

    public func serverTime() async throws -> Date {
        try await withSerializedOperation {
            let (_, response) = try await self.perform(method: "GET", path: "ec", body: nil, readOnly: true)
            guard let value = response.value(forHTTPHeaderField: "Date"),
                  let date = Self.httpDateFormatter.date(from: value) else {
                throw EZZKError.invalidResponse
            }
            return date
        }
    }

    public func requestEvidenceNumbers(count: Int) async throws -> [String] {
        try await withSerializedOperation {
            guard count > 0 else { throw EZZKError.invalidResponse }
            let body: Data
            do {
                body = try JSONEncoder().encode(["count": count])
            } catch {
                throw EZZKError.invalidResponse
            }
            let (data, _) = try await self.perform(method: "POST", path: "ec", body: body, readOnly: false)
            if let numbers = try? JSONDecoder().decode([String].self, from: data), !numbers.isEmpty {
                return numbers
            }
            if let response = try? JSONDecoder().decode(EZZKEvidenceNumberResponse.self, from: data),
               !response.evidenceNumbers.isEmpty {
                return response.evidenceNumbers
            }
            throw EZZKError.invalidResponse
        }
    }

    public func submit(files: EZZKFilesRequest) async throws -> EZZKSubmissionReceipt {
        try await withSerializedOperation {
            guard self.isValid(files: files) else { throw EZZKError.invalidResponse }
            let body: Data
            do {
                body = try JSONEncoder().encode(files)
            } catch {
                throw EZZKError.invalidResponse
            }
            let (data, _) = try await self.perform(method: "POST", path: "zzk", body: body, readOnly: false)
            do {
                return try JSONDecoder().decode(EZZKSubmissionReceipt.self, from: data)
            } catch {
                throw EZZKError.invalidResponse
            }
        }
    }

    private func withSerializedOperation<T>(
        _ operation: () async throws -> T
    ) async rethrows -> T {
        await acquireOperation()
        defer { releaseOperation() }
        return try await operation()
    }

    private func acquireOperation() async {
        guard operationInProgress else {
            operationInProgress = true
            return
        }
        await withCheckedContinuation { continuation in
            operationWaiters.append(continuation)
        }
    }

    private func releaseOperation() {
        if let waiter = operationWaiters.first {
            operationWaiters.removeFirst()
            waiter.resume()
        } else {
            operationInProgress = false
        }
    }

    private func perform(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Data?,
        readOnly: Bool
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        let initialToken = try await usableToken()
        var token = initialToken.token
        var hasRefreshed = initialToken.didRefresh

        while true {
            let request = try makeRequest(method: method, path: path, query: query, body: body, token: token)
            let response: (Data, HTTPURLResponse)
            do {
                response = try await send(request, readOnly: readOnly)
            } catch let error as EZZKError {
                throw error
            } catch {
                throw EZZKError.networkFailure(error.localizedDescription)
            }

            guard isValidAPIResponseURL(response.1.url) else {
                throw EZZKError.invalidResponse
            }
            if response.1.statusCode == 401 {
                guard !hasRefreshed else { throw EZZKError.authenticationFailed }
                token = try await refresh(using: token)
                hasRefreshed = true
                continue
            }
            guard (200..<300).contains(response.1.statusCode) else {
                throw map(statusCode: response.1.statusCode)
            }
            return response
        }
    }

    private func usableToken() async throws -> (token: EZZKTokenSet, didRefresh: Bool) {
        let token: EZZKTokenSet
        if let cachedToken {
            token = cachedToken
        } else {
            do {
                guard let loaded = try tokenStore.load(environment: environment) else {
                    throw EZZKError.authenticationFailed
                }
                cachedToken = loaded
                token = loaded
            } catch let error as EZZKError {
                throw error
            } catch {
                throw EZZKError.networkFailure("Token storage unavailable")
            }
        }

        guard isValidTokenValue(token.accessToken),
              token.tokenType.caseInsensitiveCompare("bearer") == .orderedSame else {
            throw EZZKError.authenticationFailed
        }
        guard Date().addingTimeInterval(Self.refreshSafetyWindow) >= token.expiration else {
            return (token, false)
        }
        let refreshed = try await refresh(using: token)
        return (refreshed, true)
    }

    private func refresh(using token: EZZKTokenSet) async throws -> EZZKTokenSet {
        guard let refreshToken = token.refreshToken,
              !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let endpoint = refreshEndpoint(),
              isSecureIssuerEndpoint(endpoint) else {
            throw EZZKError.authenticationFailed
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formEncoded([
            ("grant_type", "refresh_token"),
            ("client_id", oauth.clientID),
            ("refresh_token", refreshToken)
        ])

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw EZZKError.authenticationFailed
        }
        guard isValidIssuerResponseURL(response.url), (200..<300).contains(response.statusCode) else {
            throw EZZKError.authenticationFailed
        }

        do {
            let decoded = try JSONDecoder().decode(RefreshTokenResponse.self, from: data)
            guard isValidTokenValue(decoded.accessToken),
                  decoded.tokenType.caseInsensitiveCompare("bearer") == .orderedSame,
                  decoded.expiresIn > 0,
                  decoded.refreshToken.map(isValidTokenValue) ?? true else {
                throw EZZKError.authenticationFailed
            }
            let refreshed = EZZKTokenSet(
                accessToken: decoded.accessToken,
                refreshToken: decoded.refreshToken ?? refreshToken,
                expiration: Date().addingTimeInterval(TimeInterval(decoded.expiresIn)),
                tokenType: decoded.tokenType)
            do {
                try tokenStore.save(refreshed, environment: environment)
            } catch {
                throw EZZKError.networkFailure("Token storage unavailable")
            }
            cachedToken = refreshed
            return refreshed
        } catch let error as EZZKError {
            throw error
        } catch {
            throw EZZKError.authenticationFailed
        }
    }

    private func send(_ request: URLRequest, readOnly: Bool) async throws -> (Data, HTTPURLResponse) {
        let attempts = readOnly ? Self.maximumReadAttempts : 1
        for attempt in 0..<attempts {
            do {
                let response = try await transport.send(request)
                if readOnly && isRetryable(response: response.1) && attempt + 1 < attempts {
                    try await Task.sleep(nanoseconds: Self.retryDelayNanoseconds[attempt])
                    continue
                }
                return response
            } catch let error as URLError where readOnly && error.code == .timedOut && attempt + 1 < attempts {
                try await Task.sleep(nanoseconds: Self.retryDelayNanoseconds[attempt])
            } catch {
                throw error
            }
        }
        throw EZZKError.networkFailure("Request failed")
    }

    private func makeRequest(
        method: String,
        path: String,
        query: [URLQueryItem],
        body: Data?,
        token: EZZKTokenSet
    ) throws -> URLRequest {
        guard let url = apiURL(path: path, query: query) else {
            throw EZZKError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }

    private func apiURL(path: String, query: [URLQueryItem]) -> URL? {
        guard let base = URL(string: environment.apiBaseURL.absoluteString),
              base.scheme?.caseInsensitiveCompare("https") == .orderedSame,
              base.host == environment.portalBaseURL.host,
              base.user == nil,
              base.password == nil else { return nil }
        var url = base
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            url.appendPathComponent(String(component), isDirectory: false)
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == environment.portalBaseURL.host,
              components.scheme?.caseInsensitiveCompare("https") == .orderedSame else { return nil }
        components.queryItems = query.isEmpty ? nil : query
        return components.url
    }

    private func recordPath(_ evidenceNumber: String, suffix: String?) throws -> String {
        guard !evidenceNumber.isEmpty,
              evidenceNumber.unicodeScalars.allSatisfy({ !$0.properties.isWhitespace && !CharacterSet.controlCharacters.contains($0) && $0 != "/" && $0 != "?" && $0 != "#" }) else {
            throw EZZKError.invalidResponse
        }
        return suffix.map { "zzk/\(evidenceNumber)/\($0)" } ?? "zzk/\(evidenceNumber)"
    }

    private func isValid(files: EZZKFilesRequest) -> Bool {
        !files.files.isEmpty && files.files.allSatisfy { file in
            file.fileType == Self.asiceMIMEType &&
            !file.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            file.fileName.lowercased().hasSuffix(".asice")
        }
    }

    private func isSafeQueryItem(_ item: URLQueryItem) -> Bool {
        let forbidden = ["password", "token", "access_token", "refresh_token", "client_secret", "username"]
        return !forbidden.contains(item.name.lowercased())
    }

    private func refreshEndpoint() -> URL? {
        oauth.issuerURL.appendingPathComponent("protocol/openid-connect/token")
    }

    private func isSecureIssuerEndpoint(_ url: URL) -> Bool {
        url.scheme?.caseInsensitiveCompare("https") == .orderedSame &&
        url.host == oauth.issuerURL.host &&
        url.user == nil &&
        url.password == nil
    }

    private func isValidAPIResponseURL(_ url: URL?) -> Bool {
        guard let url,
              url.scheme?.caseInsensitiveCompare("https") == .orderedSame,
              url.host == environment.portalBaseURL.host,
              normalizedPort(url) == normalizedPort(environment.portalBaseURL),
              url.user == nil,
              url.password == nil else {
            return false
        }
        let basePath = environment.apiBaseURL.path
        guard url.path == basePath || url.path.hasPrefix(basePath + "/") else {
            return false
        }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return queryItems.allSatisfy(isSafeQueryItem)
    }

    private func isValidIssuerResponseURL(_ url: URL?) -> Bool {
        guard let url, isSecureIssuerEndpoint(url) else { return false }
        let issuerPath = oauth.issuerURL.path
        return url.path == issuerPath || url.path.hasPrefix(issuerPath + "/")
    }

    private func normalizedPort(_ url: URL) -> Int? {
        url.port ?? (url.scheme?.caseInsensitiveCompare("https") == .orderedSame ? 443 : nil)
    }

    private func formEncoded(_ values: [(String, String)]) -> Data? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = values.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
        return Data(encoded.utf8)
    }

    private func isValidTokenValue(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            !$0.properties.isWhitespace && !CharacterSet.controlCharacters.contains($0)
        }
    }

    private func isRetryable(response: HTTPURLResponse) -> Bool {
        response.statusCode == 408 || response.statusCode == 429 || (500...599).contains(response.statusCode)
    }

    private func map(statusCode: Int) -> EZZKError {
        if statusCode == 401 { return .authenticationFailed }
        return .serverRejected("HTTP \(statusCode)")
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    private struct EZZKEvidenceNumberResponse: Decodable {
        let evidenceNumbers: [String]
    }

    private struct RefreshTokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int
        let tokenType: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case tokenType = "token_type"
        }
    }
}
