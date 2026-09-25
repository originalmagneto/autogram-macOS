// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class ModelRegistryTests: XCTestCase {
    private func modelFile(named name: String, content: String, in folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(content.utf8).write(to: url)
        return url
    }

    private func candidate(content: String, in root: URL) throws -> TrainedCandidate {
        let dir = root.appendingPathComponent("candidate-\(UUID().uuidString)", isDirectory: true)
        let model = try modelFile(named: "Detector.mlmodel", content: content, in: dir)
        let compiledDir = dir.appendingPathComponent("Detector.mlmodelc", isDirectory: true)
        try FileManager.default.createDirectory(at: compiledDir, withIntermediateDirectories: true)
        return TrainedCandidate(modelURL: model, compiledURL: compiledDir,
                                secondsPerPage: 16, pages: 40, iterations: 50)
    }

    func testPromoteKeepsPreviousForRollback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let registry = ModelRegistry(root: root)
        let first = try candidate(content: "v1", in: root)
        let meta1 = try registry.promote(candidate: first, recallGain: 0.1, precisionDelta: 0)
        let second = try candidate(content: "v2", in: root)
        _ = try registry.promote(candidate: second, recallGain: 0.2, precisionDelta: 0)
        XCTAssertEqual(try Data(contentsOf: registry.activeModelURL()).utf8String, "v2")
        XCTAssertEqual(try Data(contentsOf: registry.previousModelURL()).utf8String, "v1")
        XCTAssertEqual(meta1.pages, 40)
    }

    func testRollbackRestoresPrevious() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let registry = ModelRegistry(root: root)
        _ = try registry.promote(candidate: candidate(content: "v1", in: root),
                                 recallGain: 0.1, precisionDelta: 0)
        _ = try registry.promote(candidate: candidate(content: "v2", in: root),
                                 recallGain: 0.2, precisionDelta: 0)
        try registry.rollback()
        XCTAssertEqual(try Data(contentsOf: registry.activeModelURL()).utf8String, "v1")
    }

    func testActiveIDIsSHA256OfModel() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let registry = ModelRegistry(root: root)
        let meta = try registry.promote(candidate: candidate(content: "v1", in: root),
                                        recallGain: 0.1, precisionDelta: 0)
        let expected = AttestationClauseGenerator.sha256Hex(of: Data("v1".utf8))
        XCTAssertEqual(meta.id, expected)
        XCTAssertEqual(try registry.activeModelID(), expected)
    }

    func testRollbackWithoutPreviousThrows() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let registry = ModelRegistry(root: root)
        XCTAssertThrowsError(try registry.rollback())
    }
}

private extension Data {
    var utf8String: String? { String(data: self, encoding: .utf8) }
}
