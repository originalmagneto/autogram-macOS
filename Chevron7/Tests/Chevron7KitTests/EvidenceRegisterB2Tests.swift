// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class EvidenceRegisterB2Tests: XCTestCase {
    func testDecodesARegisterWrittenBeforeB2() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
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
        XCTAssertNil(store.records.first?.deliveredFileName, "a row written before the single client output has none")
        XCTAssertNil(store.loadError)
    }

    /// The file ZaKo delivered to the client (the ASiC-E) is remembered on the row, so the
    /// Done screen exports that file and not a loose PDF/A that is no longer written.
    func testDeliveredFileNameRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalEvidenceStore(directory: directory)
        let record = EvidenceRecord(status: .signed, direction: .paperToElectronic, originalName: "a", newDocumentName: "a.pdf",
                                    evidenceNumber: "1563-260924-1", fingerprintSHA256Hex: "ab", attestationXML: "<x/>",
                                    conversionTime: Date(), performingPersonName: "M", securityElementCount: 0,
                                    totalPages: 1, totalSheets: 1, pdfFileName: "a.pdf",
                                    deliveredFileName: "a.asice")
        store.upsert(record)
        let loaded = try XCTUnwrap(LocalEvidenceStore(directory: directory).record(id: record.id))
        XCTAssertEqual(loaded.deliveredFileName, "a.asice")
        XCTAssertEqual(loaded.pdfFileName, "a.pdf")
    }

    func testNewStatesRoundTripAndKeepTheirRawStrings() throws {
        XCTAssertEqual(EvidenceRecord.Status.queuedForSubmission.rawValue, "Vo fronte odoslania")
        XCTAssertEqual(EvidenceRecord.Status.acceptedForProcessing.rawValue, "Prijatý na spracovanie v EZZK")
        XCTAssertEqual(EvidenceRecord.Status.processed.rawValue, "Spracovaný v EZZK")
        XCTAssertEqual(EvidenceRecord.Status.outcomeUnknown.rawValue, "Výsledok odoslania neznámy")
        XCTAssertEqual(EvidenceRecord.Status.rejected.rawValue, "Odmietnutý v EZZK")
        XCTAssertEqual(EvidenceRecord.Status.recordUnsigned.rawValue, "Záznam nepodpísaný")
        XCTAssertEqual(EvidenceRecord.Status.late.rawValue, "Oneskorený")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
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
        XCTAssertEqual(loaded.submissionMessageID, "m-1")
        XCTAssertEqual(reopened.recordContainerData(for: loaded), Data("zip".utf8))
        XCTAssertEqual(loaded.recordContainerPath, "records/\(record.id.uuidString).asice")
    }

    func testPendingStatesAndLabels() {
        XCTAssertTrue(EvidenceRecord.Status.outcomeUnknown.isSubmissionPendingState)
        XCTAssertFalse(EvidenceRecord.Status.recordUnsigned.isSubmissionPendingState)
        XCTAssertEqual(UXLabels.evidenceStatusLabel(for: .outcomeUnknown, isOverdue: false), "Výsledok neznámy, najprv overte v EZZK")
    }

    func testUnreadableRegisterIsNeverOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let evidence = directory.appendingPathComponent("Evidence")
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        // "Neznámy budúci stav" is not a status this build knows, simulating a register
        // written by a newer build (or otherwise corrupted).
        let corrupt = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","createdAt":"2026-09-20T10:00:00Z","updatedAt":"2026-09-20T10:00:00Z",
          "status":"Neznámy budúci stav","direction":"P→E","originalName":"a","newDocumentName":"a.pdf",
          "evidenceNumber":"1563-260920-1","fingerprintSHA256Hex":"ab","attestationXML":"<x/>","conversionTime":"2026-09-20T10:00:00Z",
          "performingPersonName":"M","securityElementCount":1,"totalPages":1,"totalSheets":1}]
        """
        let registerURL = evidence.appendingPathComponent("register.json")
        let originalData = Data(corrupt.utf8)
        try originalData.write(to: registerURL)

        let store = LocalEvidenceStore(directory: directory)
        XCTAssertEqual(store.records.count, 0)
        XCTAssertNotNil(store.loadError)

        let record = EvidenceRecord(status: .draft, direction: .paperToElectronic, originalName: "b", newDocumentName: "b.pdf",
                                    evidenceNumber: nil, fingerprintSHA256Hex: "cd", attestationXML: "<x/>",
                                    conversionTime: Date(), performingPersonName: "N", securityElementCount: 0,
                                    totalPages: 1, totalSheets: 1)
        store.upsert(record)
        store.delete(id: record.id)

        let afterData = try Data(contentsOf: registerURL)
        XCTAssertEqual(afterData, originalData, "The unreadable register.json must never be overwritten")

        let contents = try FileManager.default.contentsOfDirectory(at: evidence, includingPropertiesForKeys: nil)
        XCTAssertTrue(contents.contains { $0.lastPathComponent.hasPrefix("register.unreadable-") },
                      "Expected a register.unreadable-<timestamp>.json copy next to the original")
    }

    /// A register.json that exists but cannot be read at all (here a folder in its place,
    /// in real life a permission or disk error) is a load failure too: never treated as an
    /// empty register that the next write would replace.
    func testRegisterThatExistsButCannotBeReadIsALoadFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registerURL = directory.appendingPathComponent("Evidence/register.json")
        try FileManager.default.createDirectory(at: registerURL, withIntermediateDirectories: true)

        let store = LocalEvidenceStore(directory: directory)
        XCTAssertNotNil(store.loadError)
        XCTAssertTrue(store.records.isEmpty)

        let record = EvidenceRecord(status: .draft, direction: .paperToElectronic, originalName: "b", newDocumentName: "b.pdf",
                                    evidenceNumber: nil, fingerprintSHA256Hex: "cd", attestationXML: "<x/>",
                                    conversionTime: Date(), performingPersonName: "N", securityElementCount: 0,
                                    totalPages: 1, totalSheets: 1)
        store.upsert(record)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: registerURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue, "nothing may be written over an unreadable register")
    }

    /// The 24-hour "Po lehote" must not hide what the advocate has to do next: an unknown
    /// outcome is looked up first, and a late row carries its own warning.
    func testOverdueDoesNotHideUnknownOrLateLabels() {
        XCTAssertEqual(UXLabels.evidenceStatusLabel(for: .outcomeUnknown, isOverdue: true),
                       "Výsledok neznámy, najprv overte v EZZK")
        XCTAssertEqual(UXLabels.evidenceStatusLabel(for: .late, isOverdue: true), "Oneskorený")
        XCTAssertEqual(UXLabels.evidenceStatusLabel(for: .queuedForSubmission, isOverdue: true), "Po lehote")
    }

    func testReadableRegisterStillSaves() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalEvidenceStore(directory: directory)
        XCTAssertNil(store.loadError)

        let record = EvidenceRecord(status: .draft, direction: .paperToElectronic, originalName: "a", newDocumentName: "a.pdf",
                                    evidenceNumber: nil, fingerprintSHA256Hex: "ab", attestationXML: "<x/>",
                                    conversionTime: Date(), performingPersonName: "M", securityElementCount: 0,
                                    totalPages: 1, totalSheets: 1)
        store.upsert(record)

        let registerURL = directory.appendingPathComponent("Evidence/register.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: registerURL.path))

        let reopened = LocalEvidenceStore(directory: directory)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.records.count, 1)
    }

    func testFirstB2StatusWriteKeepsAPreB2Backup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalEvidenceStore(directory: directory)
        var record = EvidenceRecord(status: .submitted, direction: .paperToElectronic, originalName: "a", newDocumentName: "a.pdf",
                                    evidenceNumber: "1", fingerprintSHA256Hex: "ab", attestationXML: "<x/>",
                                    conversionTime: Date(), performingPersonName: "M", securityElementCount: 0,
                                    totalPages: 1, totalSheets: 1)
        store.upsert(record)

        let registerURL = directory.appendingPathComponent("Evidence/register.json")
        let backupURL = directory.appendingPathComponent("Evidence/register.backup-before-b2.json")
        let preB2Data = try Data(contentsOf: registerURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))

        record.status = .processed
        store.upsert(record)

        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertEqual(try Data(contentsOf: backupURL), preB2Data)

        // A second write that stores another new status must not disturb the backup.
        record.status = .acceptedForProcessing
        store.upsert(record)
        XCTAssertEqual(try Data(contentsOf: backupURL), preB2Data,
                       "An existing pre-B2 backup must never be overwritten")
    }

    func testRecordContainerDataRefusesPathEscapingRecordsFolder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A file sitting where "<Evidence>/../register.json" resolves to, so a store
        // that does not validate the path would happily read it back as if it were a
        // stored container.
        let escapedTarget = directory.appendingPathComponent("register.json")
        try Data("secret-outside-records-folder".utf8).write(to: escapedTarget)

        let store = LocalEvidenceStore(directory: directory)
        var record = EvidenceRecord(status: .signed, direction: .paperToElectronic, originalName: "a", newDocumentName: "a.pdf",
                                    evidenceNumber: nil, fingerprintSHA256Hex: "ab", attestationXML: "<x/>",
                                    conversionTime: Date(), performingPersonName: "M", securityElementCount: 0,
                                    totalPages: 1, totalSheets: 1)
        record.recordContainerPath = "../register.json"
        XCTAssertNil(store.recordContainerData(for: record),
                     "A stored path escaping the records folder must never be read back")
    }
}
