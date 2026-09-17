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

    func testFailedKeychainDeleteOnSignOutStillDropsTheLiveToken() async throws {
        let store = MemoryCredentialStore()
        try store.save(EZZKSOAPCredentials(login: "ucet", password: "heslo"), environment: .sandbox)
        store.deleteFailure = EZZKTokenStoreError.keychainFailure(status: -25308)
        let transport = ScriptedTransport([loginSucceeded, numbersReply, loginSucceeded, numbersReply])
        let controller = makeController(mode: .test, store: store, factory: { _ in transport })
        _ = try await controller.requestTestNumbers()

        controller.signOut()

        XCTAssertEqual(controller.state, .failed("Bezpečné úložisko (Keychain) nie je dostupné (kód -25308)."))
        XCTAssertEqual(controller.storedLogin, "ucet")
        _ = try await controller.requestTestNumbers()
        XCTAssertEqual(transport.operations,
                       ["LogIn", "GetConversionRecordEvidenceNumber", "LogIn", "GetConversionRecordEvidenceNumber"])
    }

    func testFirstCallAfterSignInLogsInWithTheStoredCredentials() async throws {
        let store = MemoryCredentialStore()
        let transport = ScriptedTransport([loginSucceeded, loginSucceeded, numbersReply])
        let controller = makeController(mode: .test, store: store, factory: { _ in transport })
        await controller.signIn(login: "ucet", password: "heslo")
        // Replacing the Keychain item proves the next login reads the store, not the password
        // the verification kept in memory.
        try store.save(EZZKSOAPCredentials(login: "ulozeny-ucet", password: "ulozene-heslo"), environment: .sandbox)

        let numbers = try await controller.requestTestNumbers()

        XCTAssertEqual(numbers, ["260917-A"])
        XCTAssertEqual(transport.operations, ["LogIn", "LogIn", "GetConversionRecordEvidenceNumber"])
        XCTAssertTrue(transport.bodies[1].contains("ulozeny-ucet"))
        XCTAssertTrue(transport.bodies[1].contains("ulozene-heslo"))
        XCTAssertFalse(transport.bodies[1].contains(">heslo<"))
    }

    func testOneTransportPerEnvironmentAcrossSignIns() async throws {
        let environments = EnvironmentLog()
        let transport = ScriptedTransport([loginSucceeded, loginSucceeded, loginSucceeded, numbersReply])
        let controller = makeController(mode: .test, store: MemoryCredentialStore(), factory: {
            environments.append($0)
            return transport
        })

        await controller.signIn(login: "ucet", password: "heslo")
        await controller.signIn(login: "ucet", password: "heslo")
        _ = try await controller.requestTestNumbers()
        XCTAssertEqual(environments.values, [.sandbox])

        controller.setMode(.production)
        _ = try? await controller.lookUp(evidenceNumber: "1563-260824-1")
        XCTAssertEqual(environments.values, [.sandbox, .production])
    }

    private func makeController(mode: AppSettings.EZZKMode, store: MemoryCredentialStore,
                                factory: @escaping @Sendable (EZZKEnvironment) -> any EZZKHTTPTransport)
        -> EZZKAccountController {
        let controller = EZZKAccountController(mode: mode, credentialStore: store, transportFactory: factory)
        controller.configure(person: { EZZKPerson(corporateBodyFullName: "Advokátska kancelária Test", ico: "12345678") },
                             usedEvidenceNumbers: { [] })
        return controller
    }

    private let numbersReply = #"<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body><GetConversionRecordEvidenceNumberResponse xmlns="http://www.ditec.sk/IEZZKService"><GetConversionRecordEvidenceNumberResult><Container xmlns="http://schemas.datacontract.org/2004/07/Ditec.IOM.EZZK.Dol"><Result><Code>0</Code><Description>OK</Description><Object><Data><ConversionRecordEvidenceNumberList><ConversionRecordEvidenceNumber>260917-A</ConversionRecordEvidenceNumber></ConversionRecordEvidenceNumberList></Data></Object></Result></Container></GetConversionRecordEvidenceNumberResult></GetConversionRecordEvidenceNumberResponse></s:Body></s:Envelope>"#

    private let loginSucceeded = #"<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body><OutputMessageOf_LogInOutput xmlns="http://ditec/2017/06/iam/core"><Content xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><ErrorCode i:nil="true"/><Account><Id>1</Id><Name>ucet-test</Name></Account><TokenDescriptor>token-1</TokenDescriptor></Content></OutputMessageOf_LogInOutput></s:Body></s:Envelope>"#

    private let loginRejected = #"<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body><OutputMessageOf_LogInOutput xmlns="http://ditec/2017/06/iam/core"><Content xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><ErrorCode>CORE-003</ErrorCode><Account i:nil="true"/><TokenDescriptor i:nil="true"/></Content></OutputMessageOf_LogInOutput></s:Body></s:Envelope>"#
}

final class MemoryCredentialStore: EZZKSOAPCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [EZZKEnvironment: EZZKSOAPCredentials] = [:]
    private var failureOnDelete: Error?

    var deleteFailure: Error? {
        get { lock.withLock { failureOnDelete } }
        set { lock.withLock { failureOnDelete = newValue } }
    }

    func load(environment: EZZKEnvironment) throws -> EZZKSOAPCredentials? {
        lock.withLock { items[environment] }
    }

    func save(_ credentials: EZZKSOAPCredentials, environment: EZZKEnvironment) throws {
        lock.withLock { items[environment] = credentials }
    }

    func delete(environment: EZZKEnvironment) throws {
        try lock.withLock {
            if let failureOnDelete { throw failureOnDelete }
            items[environment] = nil
        }
    }
}

final class ScriptedTransport: EZZKHTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [String]
    private var recorded: [URLRequest] = []

    init(_ replies: [String]) {
        self.replies = replies
    }

    var requestCount: Int {
        lock.withLock { recorded.count }
    }

    /// SOAP operation of each request, read from the action in its Content-Type.
    var operations: [String] {
        lock.withLock { recorded }.compactMap { request in
            request.value(forHTTPHeaderField: "Content-Type")?
                .components(separatedBy: "/").last?
                .replacingOccurrences(of: "\"", with: "")
        }
    }

    /// Request bodies as text, in order.
    var bodies: [String] {
        lock.withLock { recorded }.map { String(decoding: $0.httpBody ?? Data(), as: UTF8.self) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body: String? = lock.withLock {
            recorded.append(request)
            return replies.isEmpty ? nil : replies.removeFirst()
        }
        guard let body else { throw URLError(.badServerResponse) }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!)
    }
}

private final class EnvironmentLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [EZZKEnvironment] = []

    var values: [EZZKEnvironment] {
        lock.withLock { recorded }
    }

    func append(_ environment: EZZKEnvironment) {
        lock.withLock { recorded.append(environment) }
    }
}
