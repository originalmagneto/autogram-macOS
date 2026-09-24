// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation
import XCTest
@testable import Chevron7Kit

final class EvidenceNumberPoolTests: XCTestCase {
    func testEntriesFromAnEarlierBratislavaDayAreNotReused() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pool = EvidenceNumberPool(directory: directory)
        // 21:30Z is 23:30 CEST; 22:10Z the same evening is 00:10 CEST the next Bratislava day.
        let allocatedAt = Date(timeIntervalSince1970: 1_789_680_600)
        let afterMidnight = Date(timeIntervalSince1970: 1_789_683_000)
        pool.add(.init(number: "1563-260917-1", mode: .test, allocatedAt: allocatedAt))

        XCTAssertNil(pool.reusable(mode: .test, at: afterMidnight, excluding: []))
    }

    func testUsedNumbersAreNotReused() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pool = EvidenceNumberPool(directory: directory)
        let allocatedAt = Date()
        pool.add(.init(number: "1563-260917-1", mode: .test, allocatedAt: allocatedAt))

        XCTAssertNil(pool.reusable(mode: .test, at: allocatedAt, excluding: ["1563-260917-1"]))
        XCTAssertNotNil(pool.reusable(mode: .test, at: allocatedAt, excluding: []))
    }

    func testReusableIgnoresOtherModesAndNothingPooled() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pool = EvidenceNumberPool(directory: directory)
        let allocatedAt = Date()
        pool.add(.init(number: "1563-260917-1", mode: .demo, allocatedAt: allocatedAt))

        XCTAssertNil(pool.reusable(mode: .test, at: allocatedAt, excluding: []))
        XCTAssertEqual(pool.reusable(mode: .demo, at: allocatedAt, excluding: [])?.number, "1563-260917-1")
    }

    func testPoolPersists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let allocatedAt = Date()
        let pool = EvidenceNumberPool(directory: directory)
        pool.add(.init(number: "1563-260917-1", mode: .test, allocatedAt: allocatedAt))

        let reopened = EvidenceNumberPool(directory: directory)
        XCTAssertEqual(reopened.reusable(mode: .test, at: allocatedAt, excluding: [])?.number, "1563-260917-1")
        XCTAssertNil(reopened.loadError)

        reopened.remove("1563-260917-1")
        let reopenedAgain = EvidenceNumberPool(directory: directory)
        XCTAssertNil(reopenedAgain.reusable(mode: .test, at: allocatedAt, excluding: []))
    }

    func testUnreadableFileIsNeverOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let evidence = directory.appendingPathComponent("Evidence", isDirectory: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let fileURL = evidence.appendingPathComponent("allocated-numbers.json")
        let originalData = Data(#"{"not":"an array"}"#.utf8)
        try originalData.write(to: fileURL)

        let pool = EvidenceNumberPool(directory: directory)
        XCTAssertNotNil(pool.loadError)
        XCTAssertNil(pool.reusable(mode: .test, at: Date(), excluding: []))

        pool.add(.init(number: "1563-260917-1", mode: .test, allocatedAt: Date()))
        let afterData = try Data(contentsOf: fileURL)
        XCTAssertEqual(afterData, originalData, "The unreadable file must never be overwritten")
    }
}
