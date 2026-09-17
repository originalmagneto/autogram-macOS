import Foundation
import XCTest
@testable import AutogramKit

final class EZZKSOAPServiceAdapterTests: XCTestCase {
    private let person = EZZKPerson(corporateBodyFullName: "Advokátska kancelária Test", ico: "12345678")

    func testProductionRefusesAllocationWithoutCallingEZZK() async {
        let transport = SOAPScriptedTransport([])
        let adapter = makeAdapter(.production, transport, used: [])

        do {
            _ = try await adapter.requestEvidenceNumbers(count: 1)
            XCTFail("expected productionAllocationDisabled")
        } catch {
            XCTAssertEqual(error as? EZZKError, .productionAllocationDisabled)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testSkipsNumbersAlreadyUsedByLocalRecords() async throws {
        let transport = SOAPScriptedTransport([
            .ok(EZZKSOAPFixtures.loginSucceeded()),
            .ok(EZZKSOAPFixtures.evidenceNumbers(["260917-A", "260917-B", "260917-C"]))
        ])
        let adapter = makeAdapter(.sandbox, transport, used: ["260917-A"])

        let numbers = try await adapter.requestEvidenceNumbers(count: 1)

        XCTAssertEqual(numbers, ["260917-B"])
    }

    func testAllNumbersUsedIsAnExplicitRejection() async {
        let transport = SOAPScriptedTransport([
            .ok(EZZKSOAPFixtures.loginSucceeded()),
            .ok(EZZKSOAPFixtures.evidenceNumbers(["260917-A"]))
        ])
        let adapter = makeAdapter(.sandbox, transport, used: ["260917-A"])

        do {
            _ = try await adapter.requestEvidenceNumbers(count: 1)
            XCTFail("expected serviceRejected")
        } catch {
            XCTAssertEqual(error as? EZZKError,
                           .serviceRejected(code: 0, message: "EZZK nevrátilo žiadne nepoužité evidenčné číslo."))
        }
    }

    func testZeroCountAsksNothing() async throws {
        let transport = SOAPScriptedTransport([])
        let numbers = try await makeAdapter(.sandbox, transport, used: []).requestEvidenceNumbers(count: 0)
        XCTAssertEqual(numbers, [])
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testSubmitIsUnavailableInPartA() async {
        let transport = SOAPScriptedTransport([])
        let envelope = ConversionRecordEnvelope(evidenceNumber: "1", direction: .paperToElectronic,
                                                originalName: "a", newDocumentName: "a.pdf",
                                                attestationXML: "<x/>", fingerprintSHA256Hex: "00",
                                                conversionTime: Date())
        do {
            try await makeAdapter(.sandbox, transport, used: []).submit(envelope)
            XCTFail("expected submissionUnavailable")
        } catch {
            XCTAssertEqual(error as? EZZKError, .submissionUnavailable)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testServerTimePassesThroughOnProduction() async throws {
        let transport = SOAPScriptedTransport([
            .ok(EZZKSOAPFixtures.options, headers: ["Date": "Thu, 17 Sep 2026 13:55:59 GMT"])
        ])
        let time = try await makeAdapter(.production, transport, used: []).serverTime()
        XCTAssertEqual(time, Date(timeIntervalSince1970: 1_789_653_359))
    }

    private func makeAdapter(_ environment: EZZKEnvironment, _ transport: SOAPScriptedTransport,
                             used: Set<String>) -> EZZKSOAPServiceAdapter {
        let client = EZZKSOAPClient(environment: environment, transport: transport,
                                    credentials: { EZZKSOAPCredentials(login: "ucet", password: "heslo") })
        return EZZKSOAPServiceAdapter(client: client, person: person, usedEvidenceNumbers: used)
    }
}
