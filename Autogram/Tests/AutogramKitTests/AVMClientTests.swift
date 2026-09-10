import XCTest
@testable import AutogramKit

final class AVMClientTests: XCTestCase {
    func testUploadRequestEncodesDocumentParametersAndMimeType() throws {
        let request = AVMUploadRequest(filename: "zmluva.pdf",
                                       data: Data("PDF".utf8),
                                       mimeType: AVMUploadRequest.pdfMimeType,
                                       level: .pades(timestamp: true),
                                       container: nil)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        let document = try XCTUnwrap(json?["document"] as? [String: Any])
        XCTAssertEqual(document["filename"] as? String, "zmluva.pdf")
        XCTAssertEqual(document["content"] as? String, Data("PDF".utf8).base64EncodedString())
        let parameters = try XCTUnwrap(json?["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["level"] as? String, "PAdES_BASELINE_T")
        XCTAssertNil(parameters["container"])
        XCTAssertEqual(json?["payloadMimeType"] as? String, "application/pdf")
    }

    func testSignedDocumentDecodesContentAndSigners() throws {
        let body = #"{"filename":"zmluva.pdf","mimeType":"application/pdf;base64","content":"UERG","signers":[{"signedBy":"Ján Novák","issuedBy":"SVK eID ACA2"}]}"#
        let document = try JSONDecoder().decode(AVMSignedDocument.self, from: Data(body.utf8))
        XCTAssertEqual(document.data, Data("PDF".utf8))
        XCTAssertEqual(document.signers?.first?.signedBy, "Ján Novák")
        XCTAssertEqual(document.signers?.first?.issuedBy, "SVK eID ACA2")
    }

    private func key() throws -> AVMDocumentKey {
        try AVMDocumentKey(bytes: Data(repeating: 0xAB, count: 32))
    }

    private func response(status: Int, headers: [String: String] = [:], body: String = "") -> (Data, HTTPURLResponse) {
        let http = HTTPURLResponse(url: URL(string: "https://avm.test/api/v1/documents")!,
                                   statusCode: status, httpVersion: nil, headerFields: headers)!
        return (Data(body.utf8), http)
    }

    func testUploadSendsKeyHeaderAndReturnsGuidWithLastModified() async throws {
        let transport = RecordingAVMTransport(responses: [
            .success(response(status: 200,
                              headers: ["Last-Modified": "Fri, 11 Sep 2026 10:00:01 GMT"],
                              body: #"{"guid":"abc-123"}"#))
        ])
        let client = AVMClient(baseURL: URL(string: "https://avm.test/api/v1")!, transport: transport)
        let request = AVMUploadRequest(filename: "a.pdf", data: Data("PDF".utf8),
                                       mimeType: AVMUploadRequest.pdfMimeType, level: .padesB)

        let reference = try await client.upload(request, key: try key())

        XCTAssertEqual(reference.guid, "abc-123")
        XCTAssertEqual(reference.lastModified, "Fri, 11 Sep 2026 10:00:01 GMT")
        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.url?.absoluteString, "https://avm.test/api/v1/documents")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Encryption-Key"), try key().base64)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNotNil(sent.httpBody)
    }

    func testUploadWithoutLastModifiedFallsBackToHTTPDateNow() async throws {
        let transport = RecordingAVMTransport(responses: [
            .success(response(status: 200, body: #"{"guid":"abc"}"#))
        ])
        let client = AVMClient(baseURL: URL(string: "https://avm.test/api/v1")!, transport: transport)
        let reference = try await client.upload(
            AVMUploadRequest(filename: "a.pdf", data: Data(), mimeType: "application/pdf", level: .padesB),
            key: try key())
        XCTAssertTrue(reference.lastModified.hasSuffix(" GMT"), reference.lastModified)
    }

    func testFetchSignedReturnsPendingOn304() async throws {
        let transport = RecordingAVMTransport(responses: [.success(response(status: 304))])
        let client = AVMClient(baseURL: URL(string: "https://avm.test/api/v1")!, transport: transport)
        let reference = AVMDocumentReference(guid: "g1", key: try key(), lastModified: "Fri, 11 Sep 2026 10:00:01 GMT")

        let result = try await client.fetchSigned(reference)

        XCTAssertEqual(result, .pending)
        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.httpMethod, "GET")
        XCTAssertEqual(sent.url?.absoluteString, "https://avm.test/api/v1/documents/g1")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "If-Modified-Since"), "Fri, 11 Sep 2026 10:00:01 GMT")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Encryption-Key"), try key().base64)
    }

    func testFetchSignedReturnsDocumentOn200() async throws {
        let transport = RecordingAVMTransport(responses: [
            .success(response(status: 200, body: #"{"filename":"a.pdf","mimeType":"application/pdf","content":"UERG","signers":[]}"#))
        ])
        let client = AVMClient(baseURL: URL(string: "https://avm.test/api/v1")!, transport: transport)
        let reference = AVMDocumentReference(guid: "g1", key: try key(), lastModified: "x")

        let result = try await client.fetchSigned(reference)

        guard case .signed(let document) = result else { return XCTFail("expected signed") }
        XCTAssertEqual(document.data, Data("PDF".utf8))
    }

    func testServerErrorBodyBecomesAVMError() async throws {
        let transport = RecordingAVMTransport(responses: [
            .success(response(status: 401, body: #"{"code":"ENCRYPTION_KEY_MISSING","message":"Encryption key not provided."}"#))
        ])
        let client = AVMClient(baseURL: URL(string: "https://avm.test/api/v1")!, transport: transport)
        let reference = AVMDocumentReference(guid: "g1", key: try key(), lastModified: "x")

        do {
            _ = try await client.fetchSigned(reference)
            XCTFail("expected throw")
        } catch let error as AVMError {
            XCTAssertEqual(error, .server(status: 401, code: "ENCRYPTION_KEY_MISSING", message: "Encryption key not provided."))
        }
    }

    func testTransportFailureBecomesAVMTransportError() async throws {
        let transport = RecordingAVMTransport(responses: [.failure(URLError(.notConnectedToInternet))])
        let client = AVMClient(baseURL: URL(string: "https://avm.test/api/v1")!, transport: transport)
        do {
            _ = try await client.fetchSigned(AVMDocumentReference(guid: "g", key: try key(), lastModified: "x"))
            XCTFail("expected throw")
        } catch let error as AVMError {
            guard case .transport = error else { return XCTFail("unexpected \(error)") }
        }
    }

    func testDeleteSendsDeleteWithKey() async throws {
        let transport = RecordingAVMTransport(responses: [.success(response(status: 200))])
        let client = AVMClient(baseURL: URL(string: "https://avm.test/api/v1")!, transport: transport)
        try await client.delete(AVMDocumentReference(guid: "g1", key: try key(), lastModified: "x"))
        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.httpMethod, "DELETE")
        XCTAssertEqual(sent.url?.absoluteString, "https://avm.test/api/v1/documents/g1")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Encryption-Key"), try key().base64)
    }

    func testQRCodeURLUsesBaseURLGuidAndEncodedKey() throws {
        let client = AVMClient(baseURL: URL(string: "https://avm.test/api/v1")!, transport: RecordingAVMTransport(responses: []))
        let reference = AVMDocumentReference(guid: "g1", key: try key(), lastModified: "x")
        let url = client.qrCodeURL(for: reference)
        XCTAssertEqual(url.absoluteString, "https://avm.test/api/v1/qr-code?guid=g1&key=\(try key().queryValue)")
    }
}

private final class RecordingAVMTransport: AVMHTTPTransport, @unchecked Sendable {
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
        guard let response else { throw URLError(.badServerResponse) }
        return try response.get()
    }
}
