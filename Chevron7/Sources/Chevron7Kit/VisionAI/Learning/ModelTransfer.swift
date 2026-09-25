// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import CoreML
import Foundation

/// Moves a trained detector between Macs as a zip of `Detector.mlmodel` plus
/// `metadata.json`. Only the model travels, never scans or bank entries. An
/// import is only ever staged as a candidate: the promotion gate in
/// `DetectorPromotion` decides on local held-out documents, direct activation
/// does not exist.
public enum ModelTransferError: LocalizedError, Equatable {
    case noActiveModel
    case toolUnavailable
    case archiveFailed(String)
    case invalidBundle(String)

    public var errorDescription: String? {
        switch self {
        case .noActiveModel:
            return "Nie je čo exportovať: žiadny aktívny detektor."
        case .toolUnavailable:
            return "Balíček sa nedá vytvoriť (chýba /usr/bin/ditto)."
        case .archiveFailed(let details):
            return "Balíček sa nepodarilo spracovať: \(details)"
        case .invalidBundle(let reason):
            return "Balíček nie je platný detektor: \(reason)"
        }
    }
}

public struct ModelTransfer: Sendable {
    private let dittoURL: URL

    public init(dittoURL: URL = URL(fileURLWithPath: "/usr/bin/ditto")) {
        self.dittoURL = dittoURL
    }

    /// Zips the active `Detector.mlmodel` and `metadata.json` to `zipURL`.
    public func exportActiveModel(modelsRoot: URL, to zipURL: URL) throws {
        try requireDitto()
        let active = modelsRoot.appendingPathComponent("active", isDirectory: true)
        let model = active.appendingPathComponent("Detector.mlmodel")
        let metadata = active.appendingPathComponent("metadata.json")
        let files = FileManager.default
        guard files.fileExists(atPath: model.path), files.fileExists(atPath: metadata.path) else {
            throw ModelTransferError.noActiveModel
        }
        let staging = files.temporaryDirectory
            .appendingPathComponent("chevron7-model-export-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: staging) }
        try files.copyItem(at: model, to: staging.appendingPathComponent("Detector.mlmodel"))
        try files.copyItem(at: metadata, to: staging.appendingPathComponent("metadata.json"))
        try? files.removeItem(at: zipURL)
        try runDitto(["-c", "-k", "--sequesterRsrc", staging.path, zipURL.path])
    }

    /// Unzips a transfer bundle into `directory`.
    public func unbundle(at zipURL: URL, to directory: URL) throws {
        try requireDitto()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try runDitto(["-x", "-k", zipURL.path, directory.path])
    }

    /// Checks an unbundled folder: both files present and the model SHA-256
    /// matches `metadata.id`. Anything else is refused, never repaired.
    public func validateStagedBundle(at directory: URL) throws -> ModelMetadata {
        let model = directory.appendingPathComponent("Detector.mlmodel")
        let metadataURL = directory.appendingPathComponent("metadata.json")
        guard FileManager.default.fileExists(atPath: model.path) else {
            throw ModelTransferError.invalidBundle("chýba Detector.mlmodel")
        }
        guard let raw = try? Data(contentsOf: metadataURL),
              let meta = try? JSONDecoder().decode(ModelMetadata.self, from: raw) else {
            throw ModelTransferError.invalidBundle("chýba alebo je poškodený metadata.json")
        }
        let actual = AttestationClauseGenerator.sha256Hex(of: try Data(contentsOf: model))
        guard actual == meta.id else {
            throw ModelTransferError.invalidBundle("model nezodpovedá údaju v metadata.json")
        }
        return meta
    }

    /// Validates a zip bundle and stages it as `models/candidate-<UUID>/`
    /// with a compiled model, ready for the promotion gate. Never touches
    /// `active/`: activation happens only through `ModelRegistry.promote`.
    public func stageImportCandidate(from zipURL: URL, modelsRoot: URL) throws -> TrainedCandidate {
        try requireDitto()
        let files = FileManager.default
        let tmp = files.temporaryDirectory
            .appendingPathComponent("chevron7-model-import-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: tmp) }
        try runDitto(["-x", "-k", zipURL.path, tmp.path])
        let meta = try validateStagedBundle(at: tmp)
        let candidateDir = modelsRoot
            .appendingPathComponent("candidate-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: candidateDir, withIntermediateDirectories: true)
        do {
            try files.copyItem(at: tmp.appendingPathComponent("Detector.mlmodel"),
                               to: candidateDir.appendingPathComponent("Detector.mlmodel"))
            let compiled = try MLModel.compileModel(
                at: candidateDir.appendingPathComponent("Detector.mlmodel"))
            try files.moveItem(at: compiled,
                               to: candidateDir.appendingPathComponent("Detector.mlmodelc"))
        } catch {
            try? files.removeItem(at: candidateDir)
            throw error
        }
        return TrainedCandidate(
            modelURL: candidateDir.appendingPathComponent("Detector.mlmodel"),
            compiledURL: candidateDir.appendingPathComponent("Detector.mlmodelc"),
            secondsPerPage: meta.secondsPerPage, pages: meta.pages, iterations: meta.iterations)
    }

    private func requireDitto() throws {
        guard FileManager.default.isExecutableFile(atPath: dittoURL.path) else {
            throw ModelTransferError.toolUnavailable
        }
    }

    private func runDitto(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = dittoURL
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw ModelTransferError.archiveFailed(error.localizedDescription)
        }
        // Read before waiting so a long error report cannot fill the pipe and block ditto.
        let output = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ModelTransferError.archiveFailed(
                output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
