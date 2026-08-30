import Foundation
import XCTest
import AutogramKit
@testable import AutogramApp

@MainActor
final class EZZKSessionControllerTests: XCTestCase {
    func testRefreshStartsOAuthLoginWhenSessionIsNotActive() async {
        let authentication = AuthenticationProbe()
        let tokenStore = TokenStoreProbe()
        let transport = EZZKTransportProbe()
        let controller = EZZKSessionController(
            tokenStore: tokenStore,
            transport: transport,
            authenticationSession: authentication)

        await controller.refresh()

        XCTAssertEqual(authentication.callCount, 1)
        XCTAssertTrue(controller.hasActiveSession)
        XCTAssertEqual(controller.availableEvidenceNumberCount, 1)
        XCTAssertEqual(tokenStore.savedToken?.accessToken, "access-token")
    }

    func testCancelDuringDiscoveryPreventsAuthenticationFromStarting() async throws {
        let gate = AuthenticationDiscoveryGate()
        let session = EZZKAuthenticationSession(requestData: { _, _ in
            await gate.wait()
            let response = HTTPURLResponse(
                url: URL(string: "https://ezzk.iomo.sk")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil)!
            let body = #"{"issuer":"https://ezzk.iomo.sk/sso/auth/realms/ezzk","authorization_endpoint":"https://ezzk.iomo.sk/auth","token_endpoint":"https://ezzk.iomo.sk/token"}"#
            return (Data(body.utf8), response)
        })
        let configuration = try EZZKOAuthConfiguration()
        let authenticationTask = Task { @MainActor in
            try await session.authenticate(configuration: configuration)
        }

        await gate.waitUntilStarted()
        session.cancelAuthentication()
        gate.release()

        do {
            _ = try await authenticationTask.value
            XCTFail("Cancelled authentication must not continue to the browser session")
        } catch let error as EZZKAuthenticationError {
            XCTAssertEqual(error, .cancelled)
        }
    }
}

private final class AuthenticationDiscoveryGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var started = false

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                started = true
                self.continuation = continuation
            }
        }
    }

    func waitUntilStarted() async {
        while !lock.withLock({ started }) {
            await Task.yield()
        }
    }

    func release() {
        let continuation = lock.withLock {
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume()
    }
}

@MainActor
private final class AuthenticationProbe: EZZKAuthenticationSessionRunning {
    private(set) var callCount = 0

    func authenticate(configuration: EZZKOAuthConfiguration) async throws -> EZZKTokenSet {
        callCount += 1
        return EZZKTokenSet(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiration: Date().addingTimeInterval(3600),
            tokenType: "Bearer")
    }
}

private final class TokenStoreProbe: EZZKTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: EZZKTokenSet?
    private(set) var savedToken: EZZKTokenSet?

    func load(environment: EZZKEnvironment) throws -> EZZKTokenSet? {
        lock.withLock { token }
    }

    func save(_ tokenSet: EZZKTokenSet, environment: EZZKEnvironment) throws {
        lock.withLock {
            token = tokenSet
            savedToken = tokenSet
        }
    }

    func delete(environment: EZZKEnvironment) throws {
        lock.withLock { token = nil }
    }
}

private final class EZZKTransportProbe: EZZKHTTPTransport, @unchecked Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://ezzk-test.iomo.sk")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil)!
        return (Data(#"{"availableEvidenceNumbers":["E-1"]}"#.utf8), response)
    }
}
