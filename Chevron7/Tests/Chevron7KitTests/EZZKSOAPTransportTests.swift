// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation
import XCTest
@testable import Chevron7Kit

final class EZZKSOAPTransportTests: XCTestCase {
    override func tearDown() {
        StubSOAPURLProtocol.reset()
        super.tearDown()
    }

    func testPinDigestIsLowercaseSHA256Hex() {
        XCTAssertEqual(EZZKCertificatePin.sha256Hex(of: Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testPinMatchIgnoresCaseAndColons() {
        let der = Data("certificate".utf8)
        let hex = EZZKCertificatePin.sha256Hex(of: der)
        var colonSeparated: [String] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            colonSeparated.append(String(hex[index..<next]).uppercased())
            index = next
        }
        XCTAssertTrue(EZZKCertificatePin.matches(leafCertificateDER: der, expectedSHA256Hex: hex))
        XCTAssertTrue(EZZKCertificatePin.matches(leafCertificateDER: der,
                                                 expectedSHA256Hex: colonSeparated.joined(separator: ":")))
        XCTAssertFalse(EZZKCertificatePin.matches(leafCertificateDER: Data("other".utf8), expectedSHA256Hex: hex))
    }

    func testTransportDoesNotFollowRedirects() async throws {
        StubSOAPURLProtocol.mode = .redirect
        let transport = URLSessionEZZKSOAPTransport(pinnedSHA256: nil, configuration: stubConfiguration())

        let (_, response) = try await transport.send(URLRequest(url: EZZKEnvironment.production.soapServiceURL))

        XCTAssertEqual(response.statusCode, 302)
        XCTAssertEqual(StubSOAPURLProtocol.requestCount, 1)
    }

    func testCancelledLoadOnPinnedEnvironmentMeansUntrustedCertificate() async {
        StubSOAPURLProtocol.mode = .fail(.cancelled)
        let transport = URLSessionEZZKSOAPTransport(pinnedSHA256: "00", configuration: stubConfiguration())

        do {
            _ = try await transport.send(URLRequest(url: EZZKEnvironment.sandbox.soapServiceURL))
            XCTFail("expected untrustedCertificate")
        } catch {
            XCTAssertEqual(error as? EZZKError, .untrustedCertificate)
        }
    }

    func testCancelledLoadWithoutPinStaysAURLError() async {
        StubSOAPURLProtocol.mode = .fail(.cancelled)
        let transport = URLSessionEZZKSOAPTransport(pinnedSHA256: nil, configuration: stubConfiguration())

        do {
            _ = try await transport.send(URLRequest(url: EZZKEnvironment.production.soapServiceURL))
            XCTFail("expected URLError")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .cancelled)
        }
    }

    /// A real Swift task cancellation (not a certificate challenge refusal) must surface as
    /// `CancellationError`, never as `.untrustedCertificate`, even with a pin configured.
    /// `.hang` never calls back into the client, so the only way the load finishes is
    /// `stopLoading()`, which `URLSession.data(for:)` invokes when it notices the wrapping
    /// Swift task was cancelled (cooperative cancellation) and cancels the underlying task.
    func testTrueTaskCancellationOnPinnedEnvironmentStaysCancellationError() async throws {
        StubSOAPURLProtocol.mode = .hang
        let transport = URLSessionEZZKSOAPTransport(pinnedSHA256: "00", configuration: stubConfiguration())

        let task = Task {
            try await transport.send(URLRequest(url: EZZKEnvironment.sandbox.soapServiceURL))
        }
        await StubSOAPURLProtocol.waitForLoadToStart()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("expected CancellationError")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    // Live checks of the real handshake against ezzk-test.iomo.sk, gated on `EZZK_LIVE=1`
    // so runs without network skip them. Both send only the unauthenticated GetOptions.
    func testLivePinnedTestCertificateIsTrusted() async throws {
        guard ProcessInfo.processInfo.environment["EZZK_LIVE"] == "1" else { throw XCTSkip("EZZK_LIVE not set") }
        let transport = URLSessionEZZKSOAPTransport(environment: .sandbox)

        let (_, response) = try await transport.send(EZZKSOAPRequest.serverTime().urlRequest(in: .sandbox))

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertNotNil(response.value(forHTTPHeaderField: "Date"))
    }

    func testLiveWrongPinIsRefused() async throws {
        guard ProcessInfo.processInfo.environment["EZZK_LIVE"] == "1" else { throw XCTSkip("EZZK_LIVE not set") }
        let transport = URLSessionEZZKSOAPTransport(pinnedSHA256: "00", configuration: .ephemeral)

        do {
            _ = try await transport.send(EZZKSOAPRequest.serverTime().urlRequest(in: .sandbox))
            XCTFail("expected untrustedCertificate")
        } catch {
            XCTAssertEqual(error as? EZZKError, .untrustedCertificate)
        }
    }

    private func stubConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubSOAPURLProtocol.self]
        return configuration
    }
}

private final class StubSOAPURLProtocol: URLProtocol {
    enum Mode {
        case redirect
        case fail(URLError.Code)
        /// Never calls back into the client; the load only ends via `stopLoading()`.
        case hang
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var storedMode: Mode = .redirect
    nonisolated(unsafe) private static var count = 0
    nonisolated(unsafe) private static var loadStartedContinuation: CheckedContinuation<Void, Never>?
    /// Set when `.hang`'s `startLoading()` runs before anyone is waiting yet, so
    /// `waitForLoadToStart()` can resume immediately instead of waiting forever.
    nonisolated(unsafe) private static var loadAlreadyStarted = false

    static var mode: Mode {
        get { lock.withLock { storedMode } }
        set { lock.withLock { storedMode = newValue } }
    }

    static var requestCount: Int {
        lock.withLock { count }
    }

    static func reset() {
        lock.withLock {
            storedMode = .redirect
            count = 0
            loadStartedContinuation = nil
            loadAlreadyStarted = false
        }
    }

    /// Suspends until a `.hang` load has called `startLoading()`, so the caller can cancel the
    /// wrapping task only once the request is actually in flight (deterministic, no sleeps).
    /// Correct regardless of which of `startLoading()` or this call happens first: whichever
    /// arrives first records that it happened, and whichever arrives second resolves the
    /// rendezvous, all under the same lock.
    static func waitForLoadToStart() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if loadAlreadyStarted {
                    loadAlreadyStarted = false
                    continuation.resume()
                } else {
                    loadStartedContinuation = continuation
                }
            }
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self.count += 1 }
        switch Self.mode {
        case .redirect:
            let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil,
                                           headerFields: ["Location": "https://attacker.example/steal"])!
            var redirectRequest = request
            redirectRequest.url = URL(string: "https://attacker.example/steal")!
            client?.urlProtocol(self, wasRedirectedTo: redirectRequest, redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        case .fail(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .hang:
            let continuation = Self.lock.withLock { () -> CheckedContinuation<Void, Never>? in
                if let pending = Self.loadStartedContinuation {
                    Self.loadStartedContinuation = nil
                    return pending
                }
                Self.loadAlreadyStarted = true
                return nil
            }
            continuation?.resume()
        }
    }

    override func stopLoading() {}
}
