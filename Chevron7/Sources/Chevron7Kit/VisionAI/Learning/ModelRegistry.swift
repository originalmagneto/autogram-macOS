// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

public enum ModelRegistryError: Error, Equatable {
    case nothingToRollBack
    case noActiveModel
}

/// On-disk model versions under `<bank>/models/`: `active/` holds the model
/// detection runs load, `previous/` the one rollback restores. Deleting the
/// bank directory deletes the models with it; nothing extra tracks them.
public struct ModelMetadata: Codable, Equatable, Sendable {
    public var id: String

    public var trainedAt: Date
    public var recallGain: Double
    public var precisionDelta: Double
    public var secondsPerPage: Double
    public var pages: Int
    public var iterations: Int
}

public struct ModelRegistry: Sendable {
    public var root: URL
    public static func modelsDirectory(in bankDirectory: URL) -> URL {
        bankDirectory.appendingPathComponent("models", isDirectory: true)
    }

    public init(root: URL) { self.root = root }

    public var activeDir: URL { root.appendingPathComponent("active", isDirectory: true) }
    public var previousDir: URL { root.appendingPathComponent("previous", isDirectory: true) }

    public func activeModelURL() -> URL { activeDir.appendingPathComponent("Detector.mlmodel") }
    public func activeCompiledURL() -> URL { activeDir.appendingPathComponent("Detector.mlmodelc") }
    public func previousModelURL() -> URL { previousDir.appendingPathComponent("Detector.mlmodel") }

    @discardableResult
    public func promote(candidate: TrainedCandidate, recallGain: Double, precisionDelta: Double) throws -> ModelMetadata {
        let files = FileManager.default
        if files.fileExists(atPath: previousDir.path) {
            try files.removeItem(at: previousDir)
        }
        if files.fileExists(atPath: activeDir.path) {
            try files.moveItem(at: activeDir, to: previousDir)
        }
        try files.createDirectory(at: activeDir, withIntermediateDirectories: true)
        try files.moveItem(at: candidate.modelURL, to: activeModelURL())
        try files.moveItem(at: candidate.compiledURL, to: activeCompiledURL())
        try? files.removeItem(at: candidate.modelURL.deletingLastPathComponent())
        let meta = ModelMetadata(
            id: AttestationClauseGenerator.sha256Hex(of: try Data(contentsOf: activeModelURL())),
            trainedAt: Date(), recallGain: recallGain, precisionDelta: precisionDelta,
            secondsPerPage: candidate.secondsPerPage, pages: candidate.pages,
            iterations: candidate.iterations)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(meta).write(to: activeDir.appendingPathComponent("metadata.json"), options: .atomic)
        return meta
    }

    public func rollback() throws {
        let files = FileManager.default
        guard files.fileExists(atPath: previousDir.path) else { throw ModelRegistryError.nothingToRollBack }
        let stashed = root.appendingPathComponent("stashed-\(UUID().uuidString)", isDirectory: true)
        try files.moveItem(at: activeDir, to: stashed)
        try files.moveItem(at: previousDir, to: activeDir)
        try files.moveItem(at: stashed, to: previousDir)
    }

    public func activeModelID() throws -> String {
        guard FileManager.default.fileExists(atPath: activeModelURL().path) else {
            throw ModelRegistryError.noActiveModel
        }
        return try JSONDecoder().decode(ModelMetadata.self,
                                        from: Data(contentsOf: activeDir.appendingPathComponent("metadata.json"))).id
    }
}
