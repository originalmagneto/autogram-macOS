// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation
import XCTest
@testable import Chevron7Kit

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

    func testOfflineReadIsAPlainNetworkFailure() async {
        let transport = SOAPScriptedTransport([.fail(URLError(.notConnectedToInternet))])

        do {
            _ = try await makeClient(transport).publicRecord(evidenceNumber: "1563-260824-1")
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
            _ = try await self.makeClient(transport).receive(records: [], person: self.person)
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

    /// A WCF fault on HTTP 500 may come from the backend after the operation already ran,
    /// so a fault on a consequential request is not proof EZZK refused it.
    func testServerFaultOnReceiveIsOutcomeUnknownAndNotRepeated() async {
        let record = EZZKRecordAttachment(evidenceNumber: "1563-260924-1", mimeType: "application/vnd.etsi.asic-e+zip",
                                          data: Data("asic".utf8))
        let transport = SOAPScriptedTransport([
            .ok(EZZKSOAPFixtures.loginSucceeded()),
            .reply(status: 500, body: EZZKSOAPFixtures.fault(subcode: "InternalServiceFault",
                                                             reason: "Timeout expired."), headers: [:])
        ])

        await assertThrows(EZZKError.outcomeUnknown) {
            _ = try await self.makeClient(transport).receive(records: [record], person: self.person)
        }
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testServerFaultOnAReadKeepsTheServiceRejection() async {
        let transport = SOAPScriptedTransport([
            .reply(status: 500, body: EZZKSOAPFixtures.fault(subcode: "InternalServiceFault",
                                                             reason: "Timeout expired."), headers: [:])
        ])

        await assertThrows(EZZKError.serviceRejected(code: 500, message: "Timeout expired.")) {
            _ = try await self.makeClient(transport).publicRecord(evidenceNumber: "1563-260924-1")
        }
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

    /// Sending records is not available in this version, on production as anywhere else.
    func testReceiveOnProductionIsUnavailableWithoutAnyRequest() async {
        let transport = SOAPScriptedTransport([])
        let client = EZZKSOAPClient(environment: .production, transport: transport,
                                    credentials: { EZZKSOAPCredentials(login: "ucet", password: "heslo") },
                                    now: { Date(timeIntervalSince1970: 1_789_653_359) })
        let record = EZZKRecordAttachment(evidenceNumber: "1563-260917-1", mimeType: "application/vnd.etsi.asic-e+zip",
                                          data: Data("asic".utf8))

        await assertThrows(EZZKError.submissionUnavailable) {
            _ = try await client.receive(records: [record], person: self.person)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testCancelledReadStaysACancellation() async {
        let transport = SOAPScriptedTransport([.fail(CancellationError())])

        do {
            _ = try await makeClient(transport).serverTime()
            XCTFail("expected CancellationError")
        } catch {
            XCTAssertTrue(error is CancellationError, "expected CancellationError, got \(error)")
        }
    }

    func testCancelledConsequentialCallIsOutcomeUnknown() async {
        let transport = SOAPScriptedTransport([
            .ok(EZZKSOAPFixtures.loginSucceeded()),
            .fail(CancellationError())
        ])

        await assertThrows(EZZKError.outcomeUnknown) {
            try await self.makeClient(transport).consume(evidenceNumber: "a", person: self.person)
        }
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testReceiptTimeIsTakenAfterTheSend() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_789_653_359))
        let transport = SOAPHandlerTransport { operation, _, _ in
            if operation == "LogIn" { return .ok(EZZKSOAPFixtures.loginSucceeded()) }
            clock.value = Date(timeIntervalSince1970: 1_789_653_400)
            return .ok(EZZKSOAPFixtures.result(code: 0, description: "OK", operation: "ReceiveConversionRecord"))
        }
        let client = EZZKSOAPClient(environment: .sandbox, transport: transport,
                                    credentials: { EZZKSOAPCredentials(login: "ucet", password: "heslo") },
                                    now: { clock.value })

        let receipt = try await client.receive(records: [], person: person)

        XCTAssertEqual(receipt.submittedAt, Date(timeIntervalSince1970: 1_789_653_400))
    }

    func testReceiveReturnsTheMessageIDItSent() async throws {
        let transport = SOAPScriptedTransport([
            .ok(EZZKSOAPFixtures.loginSucceeded()),
            .ok(EZZKSOAPFixtures.result(code: 0, description: "OK", operation: "ReceiveConversionRecord"))
        ])
        let record = EZZKRecordAttachment(evidenceNumber: "1563-260917-1", mimeType: "application/vnd.etsi.asic-e+zip",
                                          data: Data("asic".utf8))

        let receipt = try await makeClient(transport).receive(records: [record], person: person)

        let body = try XCTUnwrap(transport.requests.last?.httpBody.map { String(decoding: $0, as: UTF8.self) })
        let sent = try XCTUnwrap(body.range(of: #"(?<=<w:MessageId>)[^<]+"#, options: .regularExpression))
        XCTAssertEqual(receipt.messageID, String(body[sent]))
        XCTAssertEqual(receipt.messageID, receipt.messageID.lowercased())
        XCTAssertNotNil(UUID(uuidString: receipt.messageID))
        XCTAssertEqual(receipt.submittedAt, Date(timeIntervalSince1970: 1_789_653_359))
        XCTAssertEqual(transport.operations, ["LogIn", "ReceiveConversionRecord"])
    }

    func testConcurrentAuthenticatedCallsShareOneLogin() async throws {
        let transport = SOAPHandlerTransport { operation, index, transport in
            if operation == "LogIn" {
                // Hold the reply while the second call starts: it must wait for this login
                // instead of sending its own. A second LogIn releases it at once.
                await transport.waitUntil(timeout: .milliseconds(300)) { transport.count(of: "LogIn") > 1 }
                return .ok(EZZKSOAPFixtures.loginSucceeded())
            }
            return .ok(EZZKSOAPFixtures.evidenceNumbers([index == 0 ? "a" : "b"]))
        }
        let client = makeClient(transport)
        let person = person

        let first = Task { try await client.evidenceNumbers(for: person) }
        await transport.waitUntil { transport.count(of: "LogIn") == 1 }
        let second = Task { try await client.evidenceNumbers(for: person) }
        let numbers = try await first.value + second.value

        XCTAssertEqual(Set(numbers), ["a", "b"])
        XCTAssertEqual(transport.count(of: "LogIn"), 1)
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testFailingSharedLoginReachesEveryWaiter() async {
        let transport = SOAPHandlerTransport { operation, _, transport in
            await transport.waitUntil(timeout: .milliseconds(300)) { transport.count(of: "LogIn") > 1 }
            return .ok(EZZKSOAPFixtures.loginRejected(code: "CORE-003"))
        }
        let client = makeClient(transport)
        let person = person

        let first = Task { try await client.evidenceNumbers(for: person) }
        await transport.waitUntil { transport.count(of: "LogIn") == 1 }
        let second = Task { try await client.evidenceNumbers(for: person) }

        for task in [first, second] {
            do {
                _ = try await task.value
                XCTFail("expected credentialsRejected")
            } catch {
                XCTAssertEqual(error as? EZZKError, .credentialsRejected(code: "CORE-003"))
            }
        }
        XCTAssertEqual(transport.operations, ["LogIn"])
    }

    /// Two calls sent with the same token both get 101. The first refreshes the token; the
    /// second, answered only after that refresh, must reuse the new token instead of logging
    /// in again (which used to drop the token under the first call's repeat).
    func testConcurrentUnauthorizedResultsRefreshTheTokenOnce() async throws {
        let transport = SOAPHandlerTransport { operation, index, transport in
            switch (operation, index) {
            case ("LogIn", let index):
                return .ok(EZZKSOAPFixtures.loginSucceeded(token: "token-\(index + 1)"))
            case (_, 0):
                return .ok(EZZKSOAPFixtures.unauthorized)
            case (_, 1):
                // Answer the second call only once the first call's repeat is on its way.
                await transport.waitUntil { transport.count(of: "GetConversionRecordEvidenceNumber") >= 3 }
                return .ok(EZZKSOAPFixtures.unauthorized)
            default:
                return .ok(EZZKSOAPFixtures.evidenceNumbers([index == 2 ? "a" : "b"]))
            }
        }
        let client = makeClient(transport)
        let person = person
        try await client.logIn()

        async let first = client.evidenceNumbers(for: person)
        async let second = client.evidenceNumbers(for: person)
        let numbers = try await first + second

        XCTAssertEqual(Set(numbers), ["a", "b"])
        XCTAssertEqual(transport.count(of: "LogIn"), 2)
        let cookies = transport.requests.filter { $0.url != EZZKEnvironment.sandbox.soapLoginURL }
            .map { $0.value(forHTTPHeaderField: "Cookie") }
        XCTAssertEqual(cookies, ["IamTokenDescriptor=token-1", "IamTokenDescriptor=token-1",
                                 "IamTokenDescriptor=token-2", "IamTokenDescriptor=token-2"])
    }

    func testRejectedPasswordStopsFurtherLoginsUntilCredentialsChange() async throws {
        let transport = SOAPScriptedTransport([
            .ok(EZZKSOAPFixtures.loginRejected(code: "CORE-003")),
            .ok(EZZKSOAPFixtures.loginSucceeded()),
            .ok(EZZKSOAPFixtures.evidenceNumbers(["a"]))
        ])
        let credentials = MutableCredentials(EZZKSOAPCredentials(login: "ucet", password: "zle-heslo"))
        let client = EZZKSOAPClient(environment: .sandbox, transport: transport,
                                    credentials: { credentials.value },
                                    now: { Date(timeIntervalSince1970: 1_789_653_359) })

        await assertThrows(EZZKError.credentialsRejected(code: "CORE-003")) {
            _ = try await client.evidenceNumbers(for: self.person)
        }
        XCTAssertEqual(transport.requests.count, 1)

        await assertThrows(EZZKError.credentialsRejected(code: "CORE-003")) {
            _ = try await client.evidenceNumbers(for: self.person)
        }
        XCTAssertEqual(transport.requests.count, 1)

        credentials.value = EZZKSOAPCredentials(login: "ucet", password: "heslo")
        let numbers = try await client.evidenceNumbers(for: person)

        XCTAssertEqual(numbers, ["a"])
        XCTAssertEqual(transport.operations, ["LogIn", "LogIn", "GetConversionRecordEvidenceNumber"])
    }

    func testLockedAccountStopsFurtherLoginsWithTheSameCredentials() async {
        let transport = SOAPScriptedTransport([.ok(EZZKSOAPFixtures.loginRejected(code: "CORE-018"))])
        let client = makeClient(transport)

        await assertThrows(EZZKError.accountLocked) {
            _ = try await client.evidenceNumbers(for: self.person)
        }
        await assertThrows(EZZKError.accountLocked) {
            try await client.logIn()
        }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testConnectionLostDuringReceiveIsOutcomeUnknown() async {
        let record = EZZKRecordAttachment(evidenceNumber: "1563-260917-1", mimeType: "application/vnd.etsi.asic-e+zip",
                                          data: Data("asic".utf8))
        for code in [URLError.Code.networkConnectionLost, .notConnectedToInternet] {
            let transport = SOAPScriptedTransport([.ok(EZZKSOAPFixtures.loginSucceeded()), .fail(URLError(code))])
            await assertThrows(EZZKError.outcomeUnknown, "\(code)") {
                _ = try await self.makeClient(transport).receive(records: [record], person: self.person)
            }
            XCTAssertEqual(transport.requests.count, 2, "\(code)")
        }

        let transport = SOAPScriptedTransport([.ok(EZZKSOAPFixtures.loginSucceeded()),
                                               .fail(URLError(.cannotConnectToHost))])
        do {
            _ = try await makeClient(transport).receive(records: [record], person: person)
            XCTFail("expected networkFailure")
        } catch {
            guard case .networkFailure = error as? EZZKError else {
                return XCTFail("expected networkFailure, got \(error)")
            }
        }
    }

    private func makeClient(_ transport: any EZZKHTTPTransport) -> EZZKSOAPClient {
        EZZKSOAPClient(environment: .sandbox, transport: transport,
                       credentials: { EZZKSOAPCredentials(login: "ucet", password: "heslo") },
                       now: { Date(timeIntervalSince1970: 1_789_653_359) })
    }

    private func assertThrows(_ expected: EZZKError, _ message: String = "", file: StaticString = #filePath,
                              line: UInt = #line, _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected \(expected) \(message)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? EZZKError, expected, message, file: file, line: line)
        }
    }
}

/// Credentials the test can change between calls, as a Keychain item changes after a new sign-in.
private final class MutableCredentials: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: EZZKSOAPCredentials

    init(_ credentials: EZZKSOAPCredentials) {
        stored = credentials
    }

    var value: EZZKSOAPCredentials {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// A settable clock for the client's `now`.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Date

    init(_ date: Date) {
        stored = date
    }

    var value: Date {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
