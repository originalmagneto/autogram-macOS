import XCTest
@testable import AutogramKit

final class ExampleBankTests: XCTestCase {
    private func temporaryBank() throws -> ExampleBank {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bank-\(UUID().uuidString)", isDirectory: true)
        return ExampleBank(directory: dir)
    }

    // Static (not instance) so it can be called from @Sendable closures without capturing
    // the non-Sendable XCTestCase instance (Swift 6 strict concurrency).
    private static func entry(label: BankLabel, id: UUID = UUID()) -> BankEntry {
        BankEntry(id: id, label: label, documentSHA256: "abc", pageIndex: 0,
                  box: .init(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                  featureVector: FeatureVector(values: [0, 1, 0]),
                  createdAt: Date(timeIntervalSince1970: 1_000), detectorVersion: "test")
    }

    func testAddPersistsAndReloads() throws {
        let bank = try temporaryBank()
        let id = UUID()
        try awaitAsyncThrowing { try await bank.add(Self.entry(label: .kind(.officialStamp), id: id)) }
        let reloaded = ExampleBank(directory: awaitAsync { await bank.directory })
        try awaitAsyncThrowing { try await reloaded.load() }
        let entries = awaitAsync { await reloaded.entries() }
        XCTAssertEqual(entries.map(\.id), [id])
        XCTAssertEqual(entries.first?.label, .kind(.officialStamp))
        XCTAssertEqual(awaitAsync { await reloaded.count(for: .kind(.officialStamp)) }, 1)
    }

    func testRemoveAndRemoveAll() throws {
        let bank = try temporaryBank()
        let a = UUID(), b = UUID()
        try awaitAsyncThrowing {
            try await bank.add(Self.entry(label: .negative, id: a))
            try await bank.add(Self.entry(label: .negative, id: b))
            try await bank.remove(id: a)
        }
        XCTAssertEqual(awaitAsync { await bank.entries().map(\.id) }, [b])
        try awaitAsyncThrowing { try await bank.removeAll() }
        XCTAssertTrue(awaitAsync { await bank.entries() }.isEmpty)
    }

    func testBankLabelExportLabelsAreEnglishIdentifiers() {
        XCTAssertEqual(BankLabel.kind(.officialStamp).exportLabel, "officialStamp")
        XCTAssertEqual(BankLabel.kind(.handwrittenSignature).exportLabel, "handwrittenSignature")
        XCTAssertEqual(BankLabel.negative.exportLabel, "negative")
    }

    func testCorruptIndexYieldsEmptyEntriesAndLoadError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bank-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "not json".data(using: .utf8)!.write(to: dir.appendingPathComponent("bank.json"))
        let bank = ExampleBank(directory: dir)
        XCTAssertTrue(awaitAsync { await bank.entries() }.isEmpty)
        XCTAssertNotNil(awaitAsync { await bank.loadError })
    }
}
