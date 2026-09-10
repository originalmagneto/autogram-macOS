import XCTest
import AutogramKit
@testable import AutogramApp

@MainActor
final class MobileSigningCoordinatorTests: XCTestCase {
    func testSignPresentsSheetAndDismissesOnCompletion() async throws {
        let transport = OneShotAVMTransport(bodies: [
            (200, ["Last-Modified": "Fri, 11 Sep 2026 10:00:01 GMT"], #"{"guid":"g1"}"#),
            (200, [:], #"{"filename":"a.pdf","mimeType":"application/pdf","content":"UERG","signers":[]}"#)
        ])
        let coordinator = MobileSigningCoordinator(clientFactory: {
            AVMClient(baseURL: URL(string: "https://avm.test/api/v1")!, transport: transport)
        }, pollInterval: .milliseconds(5))

        let document = try await coordinator.sign(
            AVMUploadRequest(filename: "a.pdf", data: Data("PDF".utf8), mimeType: AVMUploadRequest.pdfMimeType, level: .padesB))

        XCTAssertEqual(document.data, Data("PDF".utf8))
        XCTAssertFalse(coordinator.isPresented)
        XCTAssertNil(coordinator.session)
    }

    func testCancelDismissesAndThrowsCancelled() async throws {
        let transport = OneShotAVMTransport(bodies: [(200, [:], #"{"guid":"g1"}"#)])
        let coordinator = MobileSigningCoordinator(clientFactory: {
            AVMClient(baseURL: URL(string: "https://avm.test/api/v1")!, transport: transport)
        }, pollInterval: .milliseconds(5))
        let task = Task {
            try await coordinator.sign(AVMUploadRequest(filename: "a.pdf", data: Data(), mimeType: "application/pdf", level: .padesB))
        }
        while !coordinator.isPresented { try await Task.sleep(for: .milliseconds(5)) }

        coordinator.cancel()
        let result = await task.result

        guard case .failure(let error as AVMError) = result else { return XCTFail("expected AVMError, got \(result)") }
        XCTAssertEqual(error, .cancelled)
        XCTAssertFalse(coordinator.isPresented)
    }
}

private final class OneShotAVMTransport: AVMHTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [(Int, [String: String], String)]

    init(bodies: [(Int, [String: String], String)]) { self.bodies = bodies }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let next: (Int, [String: String], String)? = lock.withLock { bodies.isEmpty ? nil : bodies.removeFirst() }
        if request.httpMethod == "DELETE" || next == nil {
            let status = request.httpMethod == "DELETE" ? 200 : 304
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        let (status, headers, body) = next!
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
}
