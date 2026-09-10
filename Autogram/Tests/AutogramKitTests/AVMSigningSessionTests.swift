import XCTest
@testable import AutogramKit

@MainActor
final class AVMSigningSessionTests: XCTestCase {
    private func response(status: Int, headers: [String: String] = [:], body: String = "") -> (Data, HTTPURLResponse) {
        let http = HTTPURLResponse(url: URL(string: "https://avm.test/api/v1/documents")!,
                                   statusCode: status, httpVersion: nil, headerFields: headers)!
        return (Data(body.utf8), http)
    }

    private func request() -> AVMUploadRequest {
        AVMUploadRequest(filename: "a.pdf", data: Data("PDF".utf8),
                         mimeType: AVMUploadRequest.pdfMimeType, level: .padesB)
    }

    private func session(_ transport: ScriptedAVMTransport,
                         timeout: Duration = .seconds(5)) -> AVMSigningSession {
        AVMSigningSession(client: AVMClient(baseURL: URL(string: "https://avm.test/api/v1")!, transport: transport),
                          pollInterval: .milliseconds(5), timeout: timeout, qrSide: 64)
    }

    func testRunUploadsPollsAndReturnsSignedDocument() async throws {
        let transport = ScriptedAVMTransport(responses: [
            .success(response(status: 200, headers: ["Last-Modified": "Fri, 11 Sep 2026 10:00:01 GMT"], body: #"{"guid":"g1"}"#)),
            .success(response(status: 304)),
            .success(response(status: 304)),
            .success(response(status: 200, body: #"{"filename":"a.pdf","mimeType":"application/pdf","content":"UERG","signers":[]}"#))
        ])
        let session = session(transport)

        let document = try await session.run(request())

        XCTAssertEqual(document.data, Data("PDF".utf8))
        XCTAssertEqual(session.state, .signed(document))
        XCTAssertEqual(transport.requests.count, 4)
        XCTAssertEqual(transport.requests[1].httpMethod, "GET")
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "If-Modified-Since"), "Fri, 11 Sep 2026 10:00:01 GMT")
        XCTAssertFalse(session.isActive)
    }

    func testStateShowsQRAfterUpload() async throws {
        let transport = ScriptedAVMTransport(responses: [
            .success(response(status: 200, body: #"{"guid":"g1"}"#))
        ], holdAfter: 1)
        let session = session(transport)
        let task = Task { try await session.run(request()) }

        try await waitUntil { if case .waitingForScan = session.state { return true } else { return false } }

        guard case .waitingForScan(let url) = session.state else { return XCTFail("expected waiting") }
        XCTAssertTrue(url.absoluteString.hasPrefix("https://avm.test/api/v1/qr-code?guid=g1&key="))
        XCTAssertNotNil(session.qrImage)
        XCTAssertNotNil(session.deadline)
        XCTAssertTrue(session.isActive)
        session.cancel()
        _ = await task.result
    }

    func testCancelDeletesDocumentAndThrowsCancelled() async throws {
        let transport = ScriptedAVMTransport(responses: [
            .success(response(status: 200, body: #"{"guid":"g1"}"#))
        ], holdAfter: 1, deleteResponse: .success(response(status: 200)))
        let session = session(transport)
        let task = Task { try await session.run(request()) }
        try await waitUntil { if case .waitingForScan = session.state { return true } else { return false } }

        session.cancel()
        let result = await task.result

        guard case .failure(let error as AVMError) = result else { return XCTFail("expected AVMError, got \(result)") }
        XCTAssertEqual(error, .cancelled)
        XCTAssertEqual(session.state, .cancelled)
        try await waitUntil { transport.requests.contains { $0.httpMethod == "DELETE" } }
        XCTAssertFalse(session.isActive)
    }

    func testTimeoutFailsAndDeletes() async throws {
        let transport = ScriptedAVMTransport(responses: [
            .success(response(status: 200, body: #"{"guid":"g1"}"#))
        ], pendingForever: true, deleteResponse: .success(response(status: 200)))
        let session = session(transport, timeout: .milliseconds(40))

        do {
            _ = try await session.run(request())
            XCTFail("expected timeout")
        } catch let error as AVMError {
            XCTAssertEqual(error, .timeout)
        }
        XCTAssertEqual(session.state, .failed(AVMError.timeout.localizedDescription))
        try await waitUntil { transport.requests.contains { $0.httpMethod == "DELETE" } }
    }

    func testUploadFailureReportsFailedState() async throws {
        let transport = ScriptedAVMTransport(responses: [
            .success(response(status: 422, body: #"{"code":"INVALID","message":"Document must be a PDF when using PAdES."}"#))
        ])
        let session = session(transport, timeout: .seconds(1))
        do {
            _ = try await session.run(request())
            XCTFail("expected failure")
        } catch let error as AVMError {
            guard case .server(let status, _, _) = error else { return XCTFail("unexpected \(error)") }
            XCTAssertEqual(status, 422)
        }
        guard case .failed(let message) = session.state else { return XCTFail("expected failed") }
        XCTAssertTrue(message.contains("422"), message)
    }

    private func waitUntil(timeout: Duration = .seconds(2), _ condition: @MainActor () -> Bool) async throws {
        let start = ContinuousClock.now
        while !condition() {
            if ContinuousClock.now - start > timeout { throw XCTSkip("condition not met in time") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

/// Serves scripted responses. After `holdAfter` requests it answers every further GET
/// with 304; `pendingForever` does the same from the first poll. DELETE is answered
/// from `deleteResponse`.
private final class ScriptedAVMTransport: AVMHTTPTransport, @unchecked Sendable {
    typealias Response = Result<(Data, HTTPURLResponse), Error>

    private let lock = NSLock()
    private var responses: [Response]
    private let holdAfter: Int?
    private let pendingForever: Bool
    private let deleteResponse: Response?
    private var recorded: [URLRequest] = []

    var requests: [URLRequest] { lock.withLock { recorded } }

    init(responses: [Response], holdAfter: Int? = nil, pendingForever: Bool = false, deleteResponse: Response? = nil) {
        self.responses = responses
        self.holdAfter = holdAfter
        self.pendingForever = pendingForever
        self.deleteResponse = deleteResponse
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let scripted: Response? = lock.withLock {
            recorded.append(request)
            if request.httpMethod == "DELETE" { return deleteResponse }
            let served = recorded.count - 1
            if let holdAfter, served >= holdAfter { return nil }
            if pendingForever, served >= 1 { return nil }
            return responses.isEmpty ? nil : responses.removeFirst()
        }
        if let scripted { return try scripted.get() }
        let http = HTTPURLResponse(url: request.url!, statusCode: 304, httpVersion: nil, headerFields: nil)!
        return (Data(), http)
    }
}
