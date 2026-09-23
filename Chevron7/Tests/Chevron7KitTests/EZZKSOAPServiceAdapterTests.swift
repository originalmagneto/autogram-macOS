// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation
import XCTest
@testable import Chevron7Kit

final class EZZKSOAPServiceAdapterTests: XCTestCase {
    private let person = EZZKPerson(corporateBodyFullName: "Advokátska kancelária Test", ico: "12345678")

    func testProductionRefusesAllocationWithoutCallingEZZK() async {
        // An incomplete person makes the client's own `evidenceNumbers(for:)` throw
        // `.notConfigured` before it ever reaches its production guard. Only the
        // adapter's own guard in `requestEvidenceNumbers` can produce
        // `.productionAllocationDisabled` here, so this discriminates the adapter's
        // guard from the client's independent one.
        let incompletePerson = EZZKPerson(corporateBodyFullName: "", ico: "")
        let transport = SOAPScriptedTransport([])
        let client = EZZKSOAPClient(environment: .production, transport: transport,
                                    credentials: { EZZKSOAPCredentials(login: "ucet", password: "heslo") })
        let adapter = EZZKSOAPServiceAdapter(client: client, person: incompletePerson, usedEvidenceNumbers: [])

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

    func testSubmitSendsTheSignedContainerAsAsicAttachment() async throws {
        let transport = SOAPScriptedTransport([
            .ok(EZZKSOAPFixtures.loginSucceeded()),
            .ok(EZZKSOAPFixtures.result(code: 0, description: "OK", operation: "ReceiveConversionRecord"))
        ])
        let containerData = Data("asic-e-container-bytes".utf8)
        var envelope = ConversionRecordEnvelope(evidenceNumber: "1563-260917-1", direction: .paperToElectronic,
                                                originalName: "a", newDocumentName: "a.pdf",
                                                attestationXML: "<x/>", fingerprintSHA256Hex: "00",
                                                conversionTime: Date())
        envelope.signedRecordContainer = containerData

        let receipt = try await makeAdapter(.sandbox, transport, used: []).submit(envelope)

        let body = try XCTUnwrap(transport.requests.last?.httpBody.map { String(decoding: $0, as: UTF8.self) })
        XCTAssertTrue(body.contains("<d:Mimetype>application/vnd.etsi.asic-e+zip</d:Mimetype>"))
        XCTAssertTrue(body.contains(containerData.base64EncodedString()))
        XCTAssertTrue(body.contains("<w:MessageId>\(receipt.messageID)</w:MessageId>"))
        XCTAssertNotNil(UUID(uuidString: receipt.messageID))
    }

    func testSubmitWithoutContainerOnProductionIsStillUnavailable() async {
        let transport = SOAPScriptedTransport([])
        let envelope = ConversionRecordEnvelope(evidenceNumber: "1", direction: .paperToElectronic,
                                                originalName: "a", newDocumentName: "a.pdf",
                                                attestationXML: "<x/>", fingerprintSHA256Hex: "00",
                                                conversionTime: Date())

        do {
            _ = try await makeAdapter(.production, transport, used: []).submit(envelope)
            XCTFail("expected submissionUnavailable")
        } catch {
            XCTAssertEqual(error as? EZZKError, .submissionUnavailable)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testSubmitWithoutContainerIsARequestError() async {
        let transport = SOAPScriptedTransport([])
        let envelope = ConversionRecordEnvelope(evidenceNumber: "1", direction: .paperToElectronic,
                                                originalName: "a", newDocumentName: "a.pdf",
                                                attestationXML: "<x/>", fingerprintSHA256Hex: "00",
                                                conversionTime: Date())

        do {
            _ = try await makeAdapter(.sandbox, transport, used: []).submit(envelope)
            XCTFail("expected invalidRequest")
        } catch {
            XCTAssertEqual(error as? EZZKError, .invalidRequest("chýba podpísaný záznam"))
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testSubmitOnProductionIsStillRefusedWithoutAnyRequest() async {
        let transport = SOAPScriptedTransport([])
        var envelope = ConversionRecordEnvelope(evidenceNumber: "1", direction: .paperToElectronic,
                                                originalName: "a", newDocumentName: "a.pdf",
                                                attestationXML: "<x/>", fingerprintSHA256Hex: "00",
                                                conversionTime: Date())
        envelope.signedRecordContainer = Data("asic-e-container-bytes".utf8)

        do {
            _ = try await makeAdapter(.production, transport, used: []).submit(envelope)
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
