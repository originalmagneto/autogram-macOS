// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class ModelTransferTests: XCTestCase {
    private func fixtureActiveDir(in root: URL, modelContent: String) throws -> ModelMetadata {
        let dir = root.appendingPathComponent("active", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(modelContent.utf8).write(to: dir.appendingPathComponent("Detector.mlmodel"))
        let meta = ModelMetadata(id: AttestationClauseGenerator.sha256Hex(of: Data(modelContent.utf8)),
                                 trainedAt: Date(), recallGain: 0.1, precisionDelta: 0,
                                 secondsPerPage: 16, pages: 40, iterations: 50)
        try JSONEncoder().encode(meta).write(to: dir.appendingPathComponent("metadata.json"))
        return meta
    }

    private func scratchRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func testExportRoundTrip() throws {
        let root = scratchRoot()
        let meta = try fixtureActiveDir(in: root, modelContent: "model-v1")
        let zip = root.appendingPathComponent("Detector-test.zip")
        try ModelTransfer().exportActiveModel(modelsRoot: root, to: zip)
        let staged = root.appendingPathComponent("staged", isDirectory: true)
        try ModelTransfer().unbundle(at: zip, to: staged)
        XCTAssertEqual(try ModelTransfer().validateStagedBundle(at: staged), meta)
    }

    func testExportWithoutActiveModelThrows() throws {
        let root = scratchRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertThrowsError(
            try ModelTransfer().exportActiveModel(
                modelsRoot: root, to: root.appendingPathComponent("out.zip"))
        ) { XCTAssertEqual($0 as? ModelTransferError, .noActiveModel) }
    }

    func testValidateRejectsTamperedModel() throws {
        let root = scratchRoot()
        _ = try fixtureActiveDir(in: root, modelContent: "model-v1")
        let active = root.appendingPathComponent("active", isDirectory: true)
        try Data("tampered".utf8).write(to: active.appendingPathComponent("Detector.mlmodel"))
        XCTAssertThrowsError(try ModelTransfer().validateStagedBundle(at: active)) { error in
            guard case .invalidBundle = error as? ModelTransferError else {
                return XCTFail("tampered model must be invalidBundle, got \(error)")
            }
        }
    }

    func testValidateRejectsMissingMetadata() throws {
        let root = scratchRoot()
        _ = try fixtureActiveDir(in: root, modelContent: "model-v1")
        let active = root.appendingPathComponent("active", isDirectory: true)
        try FileManager.default.removeItem(at: active.appendingPathComponent("metadata.json"))
        XCTAssertThrowsError(try ModelTransfer().validateStagedBundle(at: active)) { error in
            guard case .invalidBundle = error as? ModelTransferError else {
                return XCTFail("missing metadata must be invalidBundle, got \(error)")
            }
        }
    }

    func testValidateRejectsMissingModel() throws {
        let root = scratchRoot()
        _ = try fixtureActiveDir(in: root, modelContent: "model-v1")
        let active = root.appendingPathComponent("active", isDirectory: true)
        try FileManager.default.removeItem(at: active.appendingPathComponent("Detector.mlmodel"))
        XCTAssertThrowsError(try ModelTransfer().validateStagedBundle(at: active)) { error in
            guard case .invalidBundle = error as? ModelTransferError else {
                return XCTFail("missing model must be invalidBundle, got \(error)")
            }
        }
    }
}
