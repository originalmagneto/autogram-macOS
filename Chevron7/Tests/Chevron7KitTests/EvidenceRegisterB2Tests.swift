// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class EvidenceRegisterB2Tests: XCTestCase {
    func testDecodesARegisterWrittenBeforeB2() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let evidence = directory.appendingPathComponent("Evidence")
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let legacy = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","createdAt":"2026-09-20T10:00:00Z","updatedAt":"2026-09-20T10:00:00Z",
          "status":"Vo fronte odoslania","direction":"P→E","originalName":"a","newDocumentName":"a.pdf",
          "evidenceNumber":"1563-260920-1","fingerprintSHA256Hex":"ab","attestationXML":"<x/>","conversionTime":"2026-09-20T10:00:00Z",
          "performingPersonName":"M","securityElementCount":1,"totalPages":1,"totalSheets":1}]
        """
        try Data(legacy.utf8).write(to: evidence.appendingPathComponent("register.json"))
        let store = LocalEvidenceStore(directory: directory)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.status, .queuedForSubmission)
        XCTAssertNil(store.records.first?.submittedAt)
    }

    func testNewStatesRoundTripAndKeepTheirRawStrings() throws {
        XCTAssertEqual(EvidenceRecord.Status.queuedForSubmission.rawValue, "Vo fronte odoslania")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LocalEvidenceStore(directory: directory)
        var record = EvidenceRecord(status: .signed, direction: .paperToElectronic, originalName: "a", newDocumentName: "a.pdf",
                                    evidenceNumber: "1563-260923-1", fingerprintSHA256Hex: "ab", attestationXML: "<x/>",
                                    conversionTime: Date(), performingPersonName: "M", securityElementCount: 0,
                                    totalPages: 1, totalSheets: 1)
        record.status = .outcomeUnknown
        record.ezzkMode = .test
        record.submissionMessageID = "m-1"
        record.recordContainerPath = try store.storeRecordContainer(Data("zip".utf8), for: record.id)
        store.upsert(record)
        let reopened = LocalEvidenceStore(directory: directory)
        let loaded = try XCTUnwrap(reopened.record(id: record.id))
        XCTAssertEqual(loaded.status, .outcomeUnknown)
        XCTAssertEqual(loaded.ezzkMode, .test)
        XCTAssertEqual(reopened.recordContainerData(for: loaded), Data("zip".utf8))
        XCTAssertEqual(loaded.recordContainerPath, "records/\(record.id.uuidString).asice")
    }

    func testPendingStatesAndLabels() {
        XCTAssertTrue(EvidenceRecord.Status.outcomeUnknown.isSubmissionPendingState)
        XCTAssertFalse(EvidenceRecord.Status.recordUnsigned.isSubmissionPendingState)
        XCTAssertEqual(UXLabels.evidenceStatusLabel(for: .outcomeUnknown, isOverdue: false), "Výsledok neznámy, najprv overte v EZZK")
    }
}
