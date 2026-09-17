import Foundation
import XCTest
import AutogramKit
@testable import AutogramApp

@MainActor
final class EZZKAccountControllerTests: XCTestCase {
    func testDemoModeUsesTheLocalMock() {
        let controller = EZZKAccountController(mode: .demo, credentialStore: MemoryCredentialStore(),
                                               transportFactory: { _ in ScriptedTransport([]) })
        XCTAssertTrue(controller.isDemoMode)
        XCTAssertNil(controller.environment)
        XCTAssertTrue(controller.service is MockEZZKService)
    }

    func testSignInVerifiesWithEZZKBeforeSaving() async throws {
        let store = MemoryCredentialStore()
        let transport = ScriptedTransport([loginSucceeded])
        let controller = EZZKAccountController(mode: .test, credentialStore: store,
                                               transportFactory: { _ in transport })

        await controller.signIn(login: " ucet ", password: "heslo")

        guard case let .signedIn(accountName, _) = controller.state else {
            return XCTFail("expected signedIn, got \(controller.state)")
        }
        XCTAssertEqual(accountName, "ucet-test")
        XCTAssertEqual(try store.load(environment: .sandbox), EZZKSOAPCredentials(login: "ucet", password: "heslo"))
        XCTAssertEqual(controller.storedLogin, "ucet")
        XCTAssertTrue(controller.hasStoredCredentials)
    }

    func testRejectedSignInSavesNothing() async throws {
        let store = MemoryCredentialStore()
        let transport = ScriptedTransport([loginRejected])
        let controller = EZZKAccountController(mode: .test, credentialStore: store,
                                               transportFactory: { _ in transport })

        await controller.signIn(login: "ucet", password: "zle")

        XCTAssertEqual(controller.state, .failed("Nesprávne prihlasovacie meno alebo heslo."))
        XCTAssertNil(try store.load(environment: .sandbox))
        XCTAssertFalse(controller.hasStoredCredentials)
    }

    func testEmptyFieldsFailWithoutNetwork() async {
        let transport = ScriptedTransport([])
        let controller = EZZKAccountController(mode: .test, credentialStore: MemoryCredentialStore(),
                                               transportFactory: { _ in transport })

        await controller.signIn(login: "", password: "heslo")

        XCTAssertEqual(controller.state, .failed("Zadajte prihlasovacie meno aj heslo."))
        XCTAssertEqual(transport.requestCount, 0)
    }

    func testSignOutDeletesStoredCredentials() throws {
        let store = MemoryCredentialStore()
        try store.save(EZZKSOAPCredentials(login: "ucet", password: "heslo"), environment: .production)
        let controller = EZZKAccountController(mode: .production, credentialStore: store,
                                               transportFactory: { _ in ScriptedTransport([]) })
        XCTAssertEqual(controller.storedLogin, "ucet")

        controller.signOut()

        XCTAssertNil(try store.load(environment: .production))
        XCTAssertEqual(controller.state, .signedOut)
        XCTAssertFalse(controller.hasStoredCredentials)
    }

    func testProductionServiceRefusesAllocationWithoutNetwork() async {
        let transport = ScriptedTransport([])
        let controller = EZZKAccountController(mode: .production, credentialStore: MemoryCredentialStore(),
                                               transportFactory: { _ in transport })

        do {
            _ = try await controller.service.requestEvidenceNumbers(count: 1)
            XCTFail("expected productionAllocationDisabled")
        } catch {
            XCTAssertEqual(error as? EZZKError, .productionAllocationDisabled)
        }
        XCTAssertEqual(transport.requestCount, 0)
    }

    func testModeChangeResetsStateAndLoadsThatEnvironmentsLogin() throws {
        let store = MemoryCredentialStore()
        try store.save(EZZKSOAPCredentials(login: "testovaci", password: "x"), environment: .sandbox)
        let controller = EZZKAccountController(mode: .production, credentialStore: store,
                                               transportFactory: { _ in ScriptedTransport([]) })
        XCTAssertEqual(controller.storedLogin, "")

        controller.setMode(.test)

        XCTAssertEqual(controller.mode, .test)
        XCTAssertEqual(controller.environment, .sandbox)
        XCTAssertEqual(controller.storedLogin, "testovaci")
        XCTAssertEqual(controller.state, .signedOut)
    }

    private let loginSucceeded = #"<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body><OutputMessageOf_LogInOutput xmlns="http://ditec/2017/06/iam/core"><Content xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><ErrorCode i:nil="true"/><Account><Id>1</Id><Name>ucet-test</Name></Account><TokenDescriptor>token-1</TokenDescriptor></Content></OutputMessageOf_LogInOutput></s:Body></s:Envelope>"#

    private let loginRejected = #"<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body><OutputMessageOf_LogInOutput xmlns="http://ditec/2017/06/iam/core"><Content xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><ErrorCode>CORE-003</ErrorCode><Account i:nil="true"/><TokenDescriptor i:nil="true"/></Content></OutputMessageOf_LogInOutput></s:Body></s:Envelope>"#
}

private final class MemoryCredentialStore: EZZKSOAPCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [EZZKEnvironment: EZZKSOAPCredentials] = [:]

    func load(environment: EZZKEnvironment) throws -> EZZKSOAPCredentials? {
        lock.withLock { items[environment] }
    }

    func save(_ credentials: EZZKSOAPCredentials, environment: EZZKEnvironment) throws {
        lock.withLock { items[environment] = credentials }
    }

    func delete(environment: EZZKEnvironment) throws {
        lock.withLock { items[environment] = nil }
    }
}

private final class ScriptedTransport: EZZKHTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [String]
    private var count = 0

    init(_ bodies: [String]) {
        self.bodies = bodies
    }

    var requestCount: Int {
        lock.withLock { count }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body: String? = lock.withLock {
            count += 1
            return bodies.isEmpty ? nil : bodies.removeFirst()
        }
        guard let body else { throw URLError(.badServerResponse) }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!)
    }
}
