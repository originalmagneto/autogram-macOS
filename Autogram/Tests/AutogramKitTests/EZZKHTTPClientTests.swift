import XCTest
import AutogramKit

final class EZZKHTTPClientTests: XCTestCase {
    private let oauth: EZZKOAuthConfiguration = try! EZZKOAuthConfiguration()

    func testAvailableEvidenceBuildsFixedSandboxURLAndBearerHeaders() async throws {
        let transport = RecordingEZZKTransport(responses: [
            .success(response(statusCode: 200, body: #"{"availableEvidenceNumbers":[],"description":"empty"}"#))
        ])
        let token = tokenSet(accessToken: "access-token")
        let client = EZZKClient(
            environment: .sandbox,
            oauth: oauth,
            tokenStore: InMemoryEZZKTokenStore(token: token),
            transport: transport)

        let result = try await client.availableEvidenceNumbers()

        XCTAssertEqual(result.availableEvidenceNumbers, [])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://ezzk-test.iomo.sk/api/zzkservice/v1/ec")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(request.httpBody)
    }
    func testHTTPTransportDoesNotFollowRedirects() async throws {
        RedirectEZZKURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectEZZKURLProtocol.self]
        let transport = URLSessionEZZKHTTPTransport(
            session: URLSession(configuration: configuration))
        let request = URLRequest(url: URL(string: "https://ezzk-test.iomo.sk/api/zzkservice/v1/ec")!)

        let (_, response) = try await transport.send(request)

        XCTAssertEqual(response.statusCode, 302)
        XCTAssertEqual(RedirectEZZKURLProtocol.requestCount, 1)
    }


    func testFinalResponseHostMustRemainSelectedEnvironmentHost() async throws {
        let transport = RecordingEZZKTransport(responses: [
            .success(Self.response(
                url: URL(string: "https://attacker.example/api/zzkservice/v1/ec")!,
                statusCode: 200,
                body: #"{"availableEvidenceNumbers":[]}"#))
        ])
        let client = makeClient(transport: transport)

        do {
            _ = try await client.availableEvidenceNumbers()
            XCTFail("Expected invalid response for a redirected host")
        } catch let error as EZZKError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testServerTimeUsesAuthenticatedHTTPDateWithoutLocalFallback() async throws {
        let transport = RecordingEZZKTransport(responses: [
            .success(response(statusCode: 200, headers: ["Date": "Sun, 30 Aug 2026 12:34:56 GMT"], body: "{}"))
        ])
        let client = makeClient(transport: transport)

        let date = try await client.serverTime()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(calendar.component(.year, from: date), 2026)
        XCTAssertEqual(calendar.component(.hour, from: date), 12)
        XCTAssertEqual(calendar.component(.minute, from: date), 34)
    }

    func testServerTimeRejectsMissingOrInvalidHTTPDate() async throws {
        for headers in [[String: String](), ["Date": "not-a-date"]] {
            let transport = RecordingEZZKTransport(responses: [
                .success(response(statusCode: 200, headers: headers, body: "{}"))
            ])
            let client = makeClient(transport: transport)

            do {
                _ = try await client.serverTime()
                XCTFail("Expected invalid response for headers: \(headers)")
            } catch let error as EZZKError {
                XCTAssertEqual(error, .invalidResponse)
            }
        }
    }

    func testUnauthorizedRequestRefreshesOnceAndRetriesWithNewBearerToken() async throws {
        let oldToken = tokenSet(accessToken: "old-token", refreshToken: "refresh-token", expiration: Date().addingTimeInterval(3600))
        let newToken = tokenSet(accessToken: "new-token", refreshToken: "new-refresh", expiration: Date().addingTimeInterval(3600))
        let transport = RecordingEZZKTransport(responses: [
            .success(response(statusCode: 401, body: "{}")),
            .success(Self.response(url: oauth.issuerURL.appendingPathComponent("protocol/openid-connect/token"), statusCode: 200, body: #"{"access_token":"new-token","refresh_token":"new-refresh","expires_in":3600,"token_type":"Bearer"}"#)),
            .success(response(statusCode: 200, body: #"{"availableEvidenceNumbers":["E-1"]}"#))
        ])
        let store = InMemoryEZZKTokenStore(token: oldToken)
        let client = EZZKClient(environment: .sandbox, oauth: oauth, tokenStore: store, transport: transport)

        let result = try await client.availableEvidenceNumbers()

        XCTAssertEqual(result.availableEvidenceNumbers, ["E-1"])
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer old-token")
        XCTAssertEqual(transport.requests[1].url?.absoluteString, "https://ezzk.iomo.sk/sso/auth/realms/ezzk/protocol/openid-connect/token")
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(String(data: try XCTUnwrap(transport.requests[1].httpBody), encoding: .utf8), "grant_type=refresh_token&client_id=login-app&refresh_token=refresh-token")
        XCTAssertEqual(transport.requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer new-token")
        XCTAssertEqual(store.savedToken?.accessToken, newToken.accessToken)
        XCTAssertEqual(store.savedToken?.refreshToken, newToken.refreshToken)
        XCTAssertEqual(store.savedToken?.tokenType, newToken.tokenType)
    }
    func testRefreshUsesValidatedDiscoveredTokenEndpoint() async throws {
        let discoveredEndpoint = URL(string: "https://ezzk.iomo.sk/sso/auth/realms/ezzk/custom/token")!
        let oldToken = tokenSet(
            accessToken: "old-token",
            expiration: Date().addingTimeInterval(3600),
            tokenEndpoint: discoveredEndpoint)
        let transport = RecordingEZZKTransport(responses: [
            .success(response(statusCode: 401, body: "{}")),
            .success(Self.response(
                url: discoveredEndpoint,
                statusCode: 200,
                body: #"{"access_token":"new-token","refresh_token":"new-refresh","expires_in":3600,"token_type":"Bearer"}"#)),
            .success(response(statusCode: 200, body: #"{"availableEvidenceNumbers":[]}"#))
        ])
        let client = EZZKClient(
            environment: .sandbox,
            oauth: oauth,
            tokenStore: InMemoryEZZKTokenStore(token: oldToken),
            transport: transport)

        _ = try await client.availableEvidenceNumbers()

        XCTAssertEqual(transport.requests[1].url, discoveredEndpoint)
    }


    func testSecondUnauthorizedResponseDoesNotTriggerSecondRefresh() async throws {
        let transport = RecordingEZZKTransport(responses: [
            .success(response(statusCode: 401, body: "{}")),
            .success(Self.response(url: oauth.issuerURL.appendingPathComponent("protocol/openid-connect/token"), statusCode: 200, body: #"{"access_token":"new-token","refresh_token":"new-refresh","expires_in":3600,"token_type":"Bearer"}"#)),
            .success(response(statusCode: 401, body: "{}"))
        ])
        let client = makeClient(transport: transport)

        do {
            _ = try await client.availableEvidenceNumbers()
            XCTFail("Expected authentication failure")
        } catch let error as EZZKError {
            XCTAssertEqual(error, .authenticationFailed)
        }
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testRefreshRejectsIssuerResponseOnNonDefaultHTTPSPort() async throws {
        let nonDefaultPort = URL(string: "https://ezzk.iomo.sk:444/sso/auth/realms/ezzk/protocol/openid-connect/token")!
        let transport = RecordingEZZKTransport(responses: [
            .success(response(statusCode: 401, body: "{}")),
            .success(Self.response(
                url: nonDefaultPort,
                statusCode: 200,
                body: #"{"access_token":"new-token","refresh_token":"new-refresh","expires_in":3600,"token_type":"Bearer"}"#))
        ])
        let client = makeClient(transport: transport)

        do {
            _ = try await client.availableEvidenceNumbers()
            XCTFail("Expected authentication failure for an unexpected issuer port")
        } catch let error as EZZKError {
            XCTAssertEqual(error, .authenticationFailed)
        }
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testMissingTokenDoesNotFallBackToLegacyCredentials() async throws {
        let transport = RecordingEZZKTransport(responses: [])
        let client = EZZKClient(
            environment: .sandbox,
            oauth: oauth,
            tokenStore: InMemoryEZZKTokenStore(token: nil),
            transport: transport)

        do {
            _ = try await client.availableEvidenceNumbers()
            XCTFail("Expected authentication failure")
        } catch let error as EZZKError {
            XCTAssertEqual(error, .authenticationFailed)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testReadOnlyTimeoutRetriesOnceAndThenSucceeds() async throws {
        let transport = RecordingEZZKTransport(responses: [
            .failure(URLError(.timedOut)),
            .success(response(statusCode: 200, body: #"{"availableEvidenceNumbers":["E-2"]}"#))
        ])
        let client = makeClient(transport: transport)

        let result = try await client.availableEvidenceNumbers()

        XCTAssertEqual(result.availableEvidenceNumbers, ["E-2"])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testReadOnlyRateLimitRetriesWithBoundedBackoff() async throws {
        let transport = RecordingEZZKTransport(responses: [
            .success(response(statusCode: 429, body: "{}")),
            .success(response(statusCode: 200, body: #"{"availableEvidenceNumbers":[]}"#))
        ])
        let client = makeClient(transport: transport)

        _ = try await client.availableEvidenceNumbers()

        XCTAssertEqual(transport.requests.count, 2)
    }

    func testReadOnlyStatusMappingRejectsBadRequestForbiddenConflictAndServerFailure() async throws {
        for statusCode in [400, 403, 409, 500] {
            let responses: [RecordingEZZKTransport.Response] = [
                .success(response(statusCode: statusCode, body: "{}")),
                .success(response(statusCode: statusCode, body: "{}")),
                .success(response(statusCode: statusCode, body: "{}")),
                .success(response(statusCode: statusCode, body: "{}"))
            ]
            let transport = RecordingEZZKTransport(responses: responses)
            let client = makeClient(transport: transport)

            do {
                _ = try await client.availableEvidenceNumbers()
                XCTFail("Expected rejection for status \(statusCode)")
            } catch let error as EZZKError {
                XCTAssertEqual(error, .serverRejected("HTTP \(statusCode)"))
            }
        }
    }

    func testRequestEvidenceNumbersRejectsNonPositiveCountBeforeSending() async throws {
        let transport = RecordingEZZKTransport(responses: [])
        let client = makeClient(transport: transport)

        do {
            _ = try await client.requestEvidenceNumbers(count: 0)
            XCTFail("Expected invalid response")
        } catch let error as EZZKError {
            XCTAssertEqual(error, .invalidResponse)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testSubmitRejectsInvalidFilesBeforeSending() async throws {
        let transport = RecordingEZZKTransport(responses: [])
        let client = makeClient(transport: transport)
        let invalidRequests = [
            EZZKFilesRequest(files: []),
            EZZKFilesRequest(files: [EZZKFilePayload(fileName: "record.asice", fileType: "application/zip", value: "YWJj")]),
            EZZKFilesRequest(files: [EZZKFilePayload(fileName: "record.asice", fileType: "application/vnd.etsi.asic-e+zip", value: "")])
        ]

        for request in invalidRequests {
            do {
                _ = try await client.submit(files: request)
                XCTFail("Expected invalid response")
            } catch let error as EZZKError {
                XCTAssertEqual(error, .invalidResponse)
            }
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testSubmitDoesNotRetryAndUnknownSuccessfulBodyIsInvalidResponse() async throws {
        let transport = RecordingEZZKTransport(responses: [
            .success(response(statusCode: 500, body: "{}"))
        ])
        let client = makeClient(transport: transport)
        let files = EZZKFilesRequest(files: [
            EZZKFilePayload(fileName: "record.asice", fileType: "application/vnd.etsi.asic-e+zip", value: "YWJj")
        ])

        do {
            _ = try await client.submit(files: files)
            XCTFail("Expected server rejection")
        } catch let error as EZZKError {
            XCTAssertEqual(error, .serverRejected("HTTP 500"))
        }
        XCTAssertEqual(transport.requests.count, 1)

        let unknownTransport = RecordingEZZKTransport(responses: [
            .success(response(statusCode: 200, body: #"{"message":"ok"}"#))
        ])
        let unknownClient = makeClient(transport: unknownTransport)
        do {
            _ = try await unknownClient.submit(files: files)
            XCTFail("Expected invalid response")
        } catch let error as EZZKError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testConfirmedReceiptRequiresExplicitLocalRecordTransition() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ezzk-receipt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalEvidenceStore(directory: directory)
        let record = makeLocalRecord()
        store.upsert(record)

        let transport = RecordingEZZKTransport(responses: [
            .success(response(statusCode: 200, body: #"{ "receipt": "accepted-4" }"#))
        ])
        let client = makeClient(transport: transport)
        let files = validFiles()

        let receipt = try await client.submit(files: files)

        XCTAssertEqual(receipt, EZZKSubmissionReceipt(receipt: "accepted-4"))
        XCTAssertEqual(store.record(id: record.id)?.status, .signed)

        var submitted = record
        submitted.status = .submitted
        store.upsert(submitted)
        XCTAssertEqual(store.record(id: record.id)?.status, .submitted)
    }

    func testUnknownSuccessfulSubmitResponseLeavesLocalRecordNonSubmitted() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ezzk-unknown-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalEvidenceStore(directory: directory)
        let record = makeLocalRecord()
        store.upsert(record)

        let transport = RecordingEZZKTransport(responses: [
            .success(response(statusCode: 200, body: #"{"message":"ok"}"#))
        ])
        let client = makeClient(transport: transport)

        do {
            _ = try await client.submit(files: validFiles())
            XCTFail("Expected invalid response")
        } catch let error as EZZKError {
            XCTAssertEqual(error, .invalidResponse)
        }
        XCTAssertEqual(store.record(id: record.id)?.status, .signed)
    }

    func testSubmitTransportTimeoutLeavesLocalRecordNonSubmitted() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ezzk-timeout-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalEvidenceStore(directory: directory)
        let record = makeLocalRecord()
        store.upsert(record)

        let transport = RecordingEZZKTransport(responses: [
            .failure(URLError(.timedOut))
        ])
        let client = makeClient(transport: transport)

        do {
            _ = try await client.submit(files: validFiles())
            XCTFail("Expected network failure")
        } catch let error as EZZKError {
            guard case .networkFailure = error else {
                return XCTFail("Expected network failure, got \(error)")
            }
        }
        XCTAssertEqual(store.record(id: record.id)?.status, .signed)
    }

    func testReadOnlyRoutesReturnOpaqueDataAndPreserveHistoryQuery() async throws {
        let transport = RecordingEZZKTransport(responses: [
            .success(response(statusCode: 200, body: "consumed")),
            .success(response(statusCode: 200, body: "record")),
            .success(response(statusCode: 200, body: "original")),
            .success(response(statusCode: 200, body: "history"))
        ])
        let client = makeClient(transport: transport)

        let consumed = try await client.consumedEvidenceNumbers()
        let record = try await client.record(evidenceNumber: "E-1")
        let original = try await client.original(evidenceNumber: "E-1")
        let history = try await client.history(query: [URLQueryItem(name: "page", value: "2")])
        XCTAssertEqual(consumed, Data("consumed".utf8))
        XCTAssertEqual(record, Data("record".utf8))
        XCTAssertEqual(original, Data("original".utf8))
        XCTAssertEqual(history, Data("history".utf8))

        XCTAssertEqual(transport.requests.map(\.url?.absoluteString), [
            "https://ezzk-test.iomo.sk/api/zzkservice/v1/ec/consumed",
            "https://ezzk-test.iomo.sk/api/zzkservice/v1/zzk/E-1",
            "https://ezzk-test.iomo.sk/api/zzkservice/v1/zzk/E-1/original",
            "https://ezzk-test.iomo.sk/api/zzkservice/v1/zzk?page=2"
        ])
    }

    func testConsequentialRequestsUseJSONAndDecodeConfirmedResults() async throws {
        let transport = RecordingEZZKTransport(responses: [
            .success(response(statusCode: 200, body: #"["E-3"]"#)),
            .success(response(statusCode: 200, body: #"{ "receipt": "accepted-3" }"#))
        ])
        let client = makeClient(transport: transport)
        let files = EZZKFilesRequest(files: [
            EZZKFilePayload(
                fileName: "record.asice",
                fileType: "application/vnd.etsi.asic-e+zip",
                value: "YWJj")
        ])

        let numbers = try await client.requestEvidenceNumbers(count: 1)
        let receipt = try await client.submit(files: files)
        XCTAssertEqual(numbers, ["E-3"])
        XCTAssertEqual(receipt, EZZKSubmissionReceipt(receipt: "accepted-3"))
        XCTAssertEqual(transport.requests[0].url?.absoluteString, "https://ezzk-test.iomo.sk/api/zzkservice/v1/ec")
        XCTAssertEqual(transport.requests[1].url?.absoluteString, "https://ezzk-test.iomo.sk/api/zzkservice/v1/zzk")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "Content-Type"), "application/json")
        let requestBody = try XCTUnwrap(transport.requests[0].httpBody)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: requestBody) as? [String: Int], ["count": 1])
    }

    private func validFiles() -> EZZKFilesRequest {
        EZZKFilesRequest(files: [
            EZZKFilePayload(
                fileName: "record.asice",
                fileType: "application/vnd.etsi.asic-e+zip",
                value: "YWJj")
        ])
    }

    private func makeLocalRecord() -> EvidenceRecord {
        EvidenceRecord(
            status: .signed,
            direction: .paperToElectronic,
            originalName: "source.pdf",
            newDocumentName: "converted.pdf",
            evidenceNumber: "1563-260830-1",
            fingerprintSHA256Hex: String(repeating: "a", count: 64),
            attestationXML: "<ConversionRecord/>",
            conversionTime: Date(),
            performingPersonName: "Test User",
            securityElementCount: 1,
            totalPages: 1,
            totalSheets: 1)
    }

    private func makeClient(transport: RecordingEZZKTransport) -> EZZKClient {
        EZZKClient(
            environment: .sandbox,
            oauth: oauth,
            tokenStore: InMemoryEZZKTokenStore(token: tokenSet(accessToken: "access-token")),
            transport: transport)
    }

    private func tokenSet(
        accessToken: String,
        refreshToken: String? = "refresh-token",
        expiration: Date = Date().addingTimeInterval(3600),
        tokenEndpoint: URL = URL(string: "https://ezzk.iomo.sk/sso/auth/realms/ezzk/protocol/openid-connect/token")!
    ) -> EZZKTokenSet {
        EZZKTokenSet(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiration: expiration,
            tokenType: "Bearer",
            tokenEndpoint: tokenEndpoint)
    }

    private static func response(
        statusCode: Int,
        headers: [String: String] = [:],
        body: String
    ) -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(
            url: URL(string: "https://ezzk-test.iomo.sk/api/zzkservice/v1/ec")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers)!)
    }
    private static func response(
        url: URL,
        statusCode: Int,
        headers: [String: String] = [:],
        body: String
    ) -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers)!)
    }


    private func response(
        statusCode: Int,
        headers: [String: String] = [:],
        body: String
    ) -> (Data, HTTPURLResponse) {
        Self.response(statusCode: statusCode, headers: headers, body: body)
    }
}

private final class InMemoryEZZKTokenStore: EZZKTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: EZZKTokenSet?
    private(set) var savedToken: EZZKTokenSet?

    init(token: EZZKTokenSet?) {
        self.token = token
    }

    func load(environment: EZZKEnvironment) throws -> EZZKTokenSet? {
        lock.lock()
        defer { lock.unlock() }
        return token
    }

    func save(_ tokenSet: EZZKTokenSet, environment: EZZKEnvironment) throws {
        lock.lock()
        defer { lock.unlock() }
        token = tokenSet
        savedToken = tokenSet
    }

    func delete(environment: EZZKEnvironment) throws {
        lock.lock()
        defer { lock.unlock() }
        token = nil
    }
}

private final class RecordingEZZKTransport: EZZKHTTPTransport, @unchecked Sendable {
    typealias Response = Result<(Data, HTTPURLResponse), Error>

    private let lock = NSLock()
    private var responses: [Response]
    private(set) var requests: [URLRequest] = []

    init(responses: [Response]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response: Response? = lock.withLock {
            requests.append(request)
            return responses.isEmpty ? nil : responses.removeFirst()
        }

        guard let response else {
            throw URLError(.badServerResponse)
        }
        return try response.get()
    }
}
private final class RedirectEZZKURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var count = 0

    static var requestCount: Int {
        lock.withLock { count }
    }

    static func reset() {
        lock.withLock { count = 0 }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.withLock { Self.count += 1 }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 302,
            httpVersion: nil,
            headerFields: ["Location": "https://attacker.example/steal"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
