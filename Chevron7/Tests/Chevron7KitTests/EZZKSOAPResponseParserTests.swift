// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation
import XCTest
@testable import Chevron7Kit

final class EZZKSOAPResponseParserTests: XCTestCase {
    func testLoginSucceededYieldsTokenAndAccount() throws {
        let outcome = EZZKSOAPResponseParser.login(in: try EZZKSOAPFixtures.document(EZZKSOAPFixtures.loginSucceeded()))
        XCTAssertEqual(outcome, EZZKLoginOutcome(errorCode: nil, token: "token-1", accountName: "ucet-test"))
    }

    func testLoginRejectedYieldsErrorCodeWithoutToken() throws {
        let outcome = EZZKSOAPResponseParser.login(in: try EZZKSOAPFixtures.document(EZZKSOAPFixtures.loginRejected()))
        XCTAssertEqual(outcome, EZZKLoginOutcome(errorCode: "CORE-003", token: nil, accountName: nil))
    }

    func testEvidenceNumbersKeepServerOrder() throws {
        let document = try EZZKSOAPFixtures.document(
            EZZKSOAPFixtures.evidenceNumbers(["260917-dD9DbFE4f7", "260917-dD85b642c8"]))
        XCTAssertEqual(EZZKSOAPResponseParser.evidenceNumbers(in: document), ["260917-dD9DbFE4f7", "260917-dD85b642c8"])
        XCTAssertEqual(try EZZKSOAPResponseParser.requireSuccess(document), 0)
    }

    func testResultCode101AsksForLogin() throws {
        let reply = try EZZKSOAPResponseParser.reply(data: Data(EZZKSOAPFixtures.unauthorized.utf8), statusCode: 200)
        guard case .authenticationRequired = reply else { return XCTFail("expected authenticationRequired") }
    }

    func testServiceNotInitializedFaultAsksForLogin() throws {
        let reply = try EZZKSOAPResponseParser.reply(data: Data(EZZKSOAPFixtures.serviceNotInitialized.utf8), statusCode: 500)
        guard case .authenticationRequired = reply else { return XCTFail("expected authenticationRequired") }
    }

    func testDeserializationFaultIsInvalidRequest() {
        XCTAssertThrowsError(try EZZKSOAPResponseParser.reply(
            data: Data(EZZKSOAPFixtures.deserializationFailed.utf8), statusCode: 500)) { error in
            XCTAssertEqual(error as? EZZKError, .invalidRequest("DeserializationFailed"))
        }
    }

    func testOtherFaultIsServiceRejectedWithReason() {
        let xml = EZZKSOAPFixtures.fault(subcode: "InternalServiceFault", reason: "Disk full")
        XCTAssertThrowsError(try EZZKSOAPResponseParser.reply(data: Data(xml.utf8), statusCode: 500)) { error in
            XCTAssertEqual(error as? EZZKError, .serviceRejected(code: 500, message: "Disk full"))
        }
    }

    func testUnparseableErrorPageIsNetworkFailure() {
        XCTAssertThrowsError(try EZZKSOAPResponseParser.reply(data: Data("<html><body>Bad".utf8), statusCode: 502)) { error in
            XCTAssertEqual(error as? EZZKError, .networkFailure("HTTP 502"))
        }
    }

    func testUnexpectedCodeCarriesServerText() throws {
        let document = try EZZKSOAPFixtures.document(EZZKSOAPFixtures.result(
            code: 110, description: "Dávka neobsahuje žiaden záznam o vykonanej zaručenej konverzii.",
            operation: "ReceiveConversionRecord"))
        XCTAssertThrowsError(try EZZKSOAPResponseParser.requireSuccess(document)) { error in
            XCTAssertEqual(error as? EZZKError, .serviceRejected(
                code: 110, message: "Dávka neobsahuje žiaden záznam o vykonanej zaručenej konverzii."))
        }
    }

    func testPublicRecordFieldsAreParsedAndEmptyValuesAreNil() throws {
        let document = try EZZKSOAPFixtures.document(EZZKSOAPFixtures.publicRecordFound())
        let info = try XCTUnwrap(EZZKSOAPResponseParser.recordInfo(in: document))
        XCTAssertEqual(info.evidenceNumber, "1563-260824-1")
        XCTAssertEqual(info.executionTime, Date(timeIntervalSince1970: 1_787_589_344))
        XCTAssertEqual(info.receiptTime, Date(timeIntervalSince1970: 1_787_589_463))
        XCTAssertEqual(info.personName, "Advokátska kancelária Test")
        XCTAssertEqual(info.originalDocumentName, "Dokument A")
        XCTAssertNil(info.originalDocumentFormat)
        XCTAssertEqual(info.originalDocumentSheets, 1)
        XCTAssertEqual(info.newDocumentName, "Dokument A.pdf")
        XCTAssertEqual(info.newDocumentFormat, "PDF/A-2")
        XCTAssertNil(info.newDocumentSheets)
    }

    func testPublicRecordNotFoundHasNoInfoAndRejects() throws {
        let document = try EZZKSOAPFixtures.document(EZZKSOAPFixtures.publicRecordNotFound)
        XCTAssertNil(EZZKSOAPResponseParser.recordInfo(in: document))
        XCTAssertThrowsError(try EZZKSOAPResponseParser.requireSuccess(document, accepting: [0, 1])) { error in
            XCTAssertEqual(error as? EZZKError, .serviceRejected(
                code: 105, message: "Evidenčné číslo záznamu o zaručenej konverzii nie je evidované"))
        }
    }

    func testErrorTextsAreSlovakAndHaveNoEmDash() {
        let errors: [EZZKError] = [
            .notConfigured, .authenticationFailed, .invalidResponse, .serverRejected("x"), .networkFailure("x"),
            .credentialsRejected(code: "CORE-003"), .credentialsRejected(code: "CORE-022"), .accountLocked,
            .serviceRejected(code: 110, message: "x"), .invalidRequest("x"), .untrustedCertificate,
            .productionAllocationDisabled, .submissionUnavailable, .evidenceNumberExpired, .evidenceNumberFromOtherMode,
            .outcomeUnknown
        ]
        for error in errors {
            let text = error.errorDescription ?? ""
            XCTAssertFalse(text.isEmpty, "\(error)")
            XCTAssertFalse(text.contains("\u{2014}"), "\(error)")
        }
        XCTAssertEqual(EZZKError.credentialsRejected(code: "CORE-003").errorDescription,
                       "Nesprávne prihlasovacie meno alebo heslo.")
    }
}
