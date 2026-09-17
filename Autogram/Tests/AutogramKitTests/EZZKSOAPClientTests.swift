import Foundation
import XCTest
@testable import AutogramKit

final class EZZKSOAPClientTests: XCTestCase {
    private let person = EZZKPerson(corporateBodyFullName: "Advokátska kancelária Test", ico: "12345678")

    func testAuthenticatedCallLogsInFirstAndSendsTokenCookie() async throws {
        let transport = SOAPScriptedTransport([
            .ok(EZZKSOAPFixtures.loginSucceeded(token: "token-1")),
            .ok(EZZKSOAPFixtures.evidenceNumbers(["260917-dD9DbFE4f7"]))
        ])
        let client = makeClient(transport)

        let numbers = try await client.evidenceNumbers(for: person)

        XCTAssertEqual(numbers, ["260917-dD9DbFE4f7"])
        XCTAssertEqual(transport.operations, ["LogIn", "GetConversionRecordEvidenceNumber"])
        XCTAssertEqual(transport.requests[0].url, EZZKEnvironment.sandbox.soapLoginURL)
        XCTAssertNil(transport.requests[0].value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "Cookie"), "IamTokenDescriptor=token-1")
    }

    func testTokenIsReusedAcrossCalls() async throws {
        let transport = SOAPScriptedTransport([
            .ok(EZZKSOAPFixtures.loginSucceeded()),
            .ok(EZZKSOAPFixtures.evidenceNumbers(["a"])),
            .ok(EZZKSOAPFixtures.result(code: 0, description: "OK"))
        ])
        let client = makeClient(transport)

        _ = try await client.evidenceNumbers(for: person)
        try await client.consume(evidenceNumber: "a", person: person)

        XCTAssertEqual(transport.operations, ["LogIn", "GetConversionRecordEvidenceNumber", "ConsumeConversionRecordEvidenceNumber"])
    }

    func testUnauthorizedResultTriggersOneFreshLoginAndRepeat() async throws {
        let transport = SOAPScriptedTransport([
            .ok(EZZKSOAPFixtures.loginSucceeded(token: "token-1")),
            .ok(EZZKSOAPFixtures.unauthorized),
            .ok(EZZKSOAPFixtures.loginSucceeded(token: "token-2")),
            .ok(EZZKSOAPFixtures.evidenceNumbers(["b"]))
        ])
        let client = makeClient(transport)

        let numbers = try await client.evidenceNumbers(for: person)

        XCTAssertEqual(numbers, ["b"])
        XCTAssertEqual(transport.requests.count, 4)
        XCTAssertEqual(transport.requests[3].value(forHTTPHeaderField: "Cookie"), "IamTokenDescriptor=token-2")
    }

    func testServiceNotInitializedFaultCountsAsUnauthorized() async throws {
        let transport = SOAPScriptedTransport([
            .ok(EZZKSOAPFixtures.loginSucceeded()),
            .reply(status: 500, body: EZZKSOAPFixtures.serviceNotInitialized, headers: [:]),
            .ok(EZZKSOAPFixtures.loginSucceeded(token: "token-2")),
            .ok(EZZKSOAPFixtures.evidenceNumbers(["c"]))
        ])

        let numbers = try await makeClient(transport).evidenceNumbers(for: person)

        XCTAssertEqual(numbers, ["c"])
    }

    func testSecondUnauthorizedResultFailsWithoutLooping() async {
        let transport = SOAPScriptedTransport([
            .ok(EZZKSOAPFixtures.loginSucceeded()),
            .ok(EZZKSOAPFixtures.unauthorized),
            .ok(EZZKSOAPFixtures.loginSucceeded()),
            .ok(EZZKSOAPFixtures.unauthorized)
        ])

        await assertThrows(EZZKError.authenticationFailed) {
            _ = try await self.makeClient(transport).evidenceNumbers(for: self.person)
        }
        XCTAssertEqual(transport.requests.count, 4)
    }

    func testRejectedCredentialsAndLockedAccount() async {
        let rejected = SOAPScriptedTransport([.ok(EZZKSOAPFixtures.loginRejected(code: "CORE-003"))])
        await assertThrows(EZZKError.credentialsRejected(code: "CORE-003")) {
            try await self.makeClient(rejected).logIn()
        }
        let locked = SOAPScriptedTransport([.ok(EZZKSOAPFixtures.loginRejected(code: "CORE-018"))])
        await assertThrows(EZZKError.accountLocked) {
            try await self.makeClient(locked).logIn()
        }
    }

    func testMissingCredentialsNeverCallEZZK() async {
        let transport = SOAPScriptedTransport([])
        let client = EZZKSOAPClient(environment: .sandbox, transport: transport, credentials: { nil })

        await assertThrows(EZZKError.notConfigured) {
            try await client.logIn()
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testIncompletePersonIsRejectedBeforeAnyRequest() async {
        let transport = SOAPScriptedTransport([])
        let incomplete = EZZKPerson(corporateBodyFullName: "Kancelária", ico: " ")

        await assertThrows(EZZKError.notConfigured) {
            _ = try await self.makeClient(transport).evidenceNumbers(for: incomplete)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testTimeoutOnConsequentialCallIsOutcomeUnknownAndNotRepeated() async {
        let transport = SOAPScriptedTransport([
            .ok(EZZKSOAPFixtures.loginSucceeded()),
            .fail(URLError(.timedOut))
        ])

        await assertThrows(EZZKError.outcomeUnknown) {
            _ = try await self.makeClient(transport).evidenceNumbers(for: self.person)
        }
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testUnreachableHostIsAPlainNetworkFailure() async {
        let transport = SOAPScriptedTransport([
            .ok(EZZKSOAPFixtures.loginSucceeded()),
            .fail(URLError(.cannotFindHost))
        ])

        do {
            _ = try await makeClient(transport).evidenceNumbers(for: person)
            XCTFail("expected networkFailure")
        } catch {
            guard case .networkFailure = error as? EZZKError else {
                return XCTFail("expected networkFailure, got \(error)")
            }
        }
    }

    func testServerTimeReadsDateHeaderWithoutLogin() async throws {
        let transport = SOAPScriptedTransport([
            .ok(EZZKSOAPFixtures.options, headers: ["Date": "Thu, 17 Sep 2026 13:55:59 GMT"])
        ])

        let time = try await makeClient(transport).serverTime()

        XCTAssertEqual(time, Date(timeIntervalSince1970: 1_789_653_359))
        XCTAssertEqual(transport.operations, ["GetOptions"])
        XCTAssertNil(transport.requests[0].value(forHTTPHeaderField: "Cookie"))
    }

    func testPublicRecordNeedsNoLoginAndReportsPendingProcessing() async throws {
        let transport = SOAPScriptedTransport([.ok(EZZKSOAPFixtures.publicRecordFound(code: 1))])

        let lookup = try await makeClient(transport).publicRecord(evidenceNumber: "1563-260824-1")

        XCTAssertFalse(lookup.isProcessed)
        XCTAssertEqual(lookup.info?.evidenceNumber, "1563-260824-1")
        XCTAssertEqual(transport.operations, ["GetConversionRecordInformationPurpose"])
    }

    func testRejectedBatchSurfacesServerText() async {
        let transport = SOAPScriptedTransport([
            .ok(EZZKSOAPFixtures.loginSucceeded()),
            .ok(EZZKSOAPFixtures.result(code: 110, description: "Dávka neobsahuje žiaden záznam.",
                                        operation: "ReceiveConversionRecord"))
        ])

        await assertThrows(EZZKError.serviceRejected(code: 110, message: "Dávka neobsahuje žiaden záznam.")) {
            try await self.makeClient(transport).receive(records: [], person: self.person)
        }
    }

    func testGatewayTimeoutOnConsequentialCallIsOutcomeUnknownAndNotRepeated() async {
        let transport = SOAPScriptedTransport([
            .ok(EZZKSOAPFixtures.loginSucceeded()),
            .reply(status: 504, body: "Gateway Timeout", headers: [:])
        ])

        await assertThrows(EZZKError.outcomeUnknown) {
            try await self.makeClient(transport).consume(evidenceNumber: "a", person: self.person)
        }
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testGatewayTimeoutOnPublicRecordStaysNetworkFailure() async {
        let transport = SOAPScriptedTransport([
            .reply(status: 504, body: "Gateway Timeout", headers: [:])
        ])

        do {
            _ = try await makeClient(transport).publicRecord(evidenceNumber: "1563-260824-1")
            XCTFail("expected networkFailure")
        } catch {
            guard case .networkFailure = error as? EZZKError else {
                return XCTFail("expected networkFailure, got \(error)")
            }
        }
    }

    /// Controller decision: consequential calls must be impossible by construction on
    /// production, regardless of what the transport would have replied.
    func testConsequentialCallOnProductionIsDisabledWithoutAnyRequest() async {
        let transport = SOAPScriptedTransport([])
        let client = EZZKSOAPClient(environment: .production, transport: transport,
                                    credentials: { EZZKSOAPCredentials(login: "ucet", password: "heslo") },
                                    now: { Date(timeIntervalSince1970: 1_789_653_359) })

        await assertThrows(EZZKError.productionAllocationDisabled) {
            _ = try await client.evidenceNumbers(for: self.person)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    private func makeClient(_ transport: SOAPScriptedTransport) -> EZZKSOAPClient {
        EZZKSOAPClient(environment: .sandbox, transport: transport,
                       credentials: { EZZKSOAPCredentials(login: "ucet", password: "heslo") },
                       now: { Date(timeIntervalSince1970: 1_789_653_359) })
    }

    private func assertThrows(_ expected: EZZKError, file: StaticString = #filePath, line: UInt = #line,
                              _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? EZZKError, expected, file: file, line: line)
        }
    }
}
