// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Combine
import CoreML
import CreateML
import Foundation

public enum DetectorStagingError: Error, Equatable {
    case missingImage(String)
}

/// In-app object-detector training (phase 2 of the learned detector).
/// The CreateML call itself has no suite test (about 9 minutes fixed cost;
/// `vision-train` covers that path manually). Everything around it is pure
/// and tested: staging, the single-job guard, scoring, promotion and the
/// model registry.
public enum DetectorTrainer {
    /// Copies the train partition into a fresh folder CreateML accepts
    /// (images plus `annotations.json`). A missing image throws instead of
    /// silently shrinking the training set.
    public static func stageTrainDirectory(dataset: URL, trainImages: [String],
                                           trainAnnotations: [CreateMLImageAnnotation],
                                           to staged: URL) throws {
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        for name in trainImages {
            let source = dataset.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw DetectorStagingError.missingImage(name)
            }
            try FileManager.default.copyItem(at: source, to: staged.appendingPathComponent(name))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(VisionTrainSplit.annotations(for: trainImages, from: trainAnnotations))
            .write(to: staged.appendingPathComponent("annotations.json"), options: .atomic)
    }
}

public enum DetectorTrainingError: Error, Equatable {
    case busy
    case thermalRefused
    case thermalCancelled
    case emptyTrainPartition
}

public struct TrainedCandidate: Sendable {
    public var modelURL: URL
    public var compiledURL: URL
    public var secondsPerPage: Double
    public var pages: Int
    public var iterations: Int
}

/// One training at a time: a second concurrent `run` throws `busy`.
/// Cancellation of the caller's task aborts the run it started.
public actor DetectorTrainingJob {
    private var running = false
    public var isRunning: Bool { running }
    public init() {}

    public func run<R: Sendable>(_ work: @Sendable () async throws -> R) async throws -> R {
        guard !running else { throw DetectorTrainingError.busy }
        running = true
        defer { running = false }
        return try await work()
    }
}

/// Handoff between the Combine callback (background executor) and the
/// polling task. Written at most once; a stale read only delays one poll.
private final class TrainingResultBox: @unchecked Sendable {
    var model: MLObjectDetector?
    var error: Error?
}

extension DetectorTrainer {
    /// Refuse to start a run while the Mac reports serious heat or worse.
    /// CreateML has no suspend, so a hot start would only end in a cancel.
    public static func refuseStart(thermalState: ProcessInfo.ThermalState) -> Bool {
        thermalState == .serious || thermalState == .critical
    }

    /// A critical state mid-run cancels the job: a throttled run must never
    /// produce the model the promotion compares.
    public static func cancelRun(thermalState: ProcessInfo.ThermalState) -> Bool {
        thermalState == .critical
    }

    /// The real training path: export, stage, `MLObjectDetector.train`,
    /// write and compile into `models/candidate-<UUID>/`, clean up temps.
    /// Call from a `.utility` task; one job at a time via `DetectorTrainingJob`.
    public static func trainProduction(bank: ExampleBank, maxIterations: Int = 50,
                                       onProgress: @Sendable @escaping (Double) -> Void) async throws -> TrainedCandidate {
        if refuseStart(thermalState: ProcessInfo.processInfo.thermalState) {
            throw DetectorTrainingError.thermalRefused
        }
        try Task.checkCancellation()
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("detector-train-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let datasetURL = try await CreateMLExporter.export(bank: bank, to: tempRoot)
        let datasetFolder = datasetURL.deletingLastPathComponent()
        let annotations = try JSONDecoder().decode([CreateMLImageAnnotation].self,
                                                   from: Data(contentsOf: datasetURL))
        let splits = try JSONDecoder().decode([CreateMLDocumentSplit].self,
                                              from: Data(contentsOf: datasetFolder.appendingPathComponent("splits.json")))
        let trainImages = VisionTrainSplit.images(in: "train", splits: splits)
        guard !trainImages.isEmpty else { throw DetectorTrainingError.emptyTrainPartition }
        try stageTrainDirectory(dataset: datasetFolder, trainImages: trainImages,
                                trainAnnotations: VisionTrainSplit.annotations(for: trainImages, from: annotations),
                                to: tempRoot.appendingPathComponent("train", isDirectory: true))
        try Task.checkCancellation()
        var parameters = MLObjectDetector.ModelParameters()
        parameters.maxIterations = maxIterations
        parameters.algorithm = .transferLearning(.objectPrint(revision: 1))
        let startedAt = Date()
        let job = try MLObjectDetector.train(
            trainingData: .directoryWithImagesAndJsonAnnotation(at: tempRoot.appendingPathComponent("train")),
            annotationType: .boundingBox(units: .pixel, origin: .topLeft, anchor: .center),
            parameters: parameters)
        // Written once by the Combine callback, polled below. A stale read
        // only costs one more 5 s sleep; the callback never mutates twice
        // (Combine delivers one value or one failure, not both).
        let box = TrainingResultBox()
        let cancellable = job.result.sink(
            receiveCompletion: { @Sendable completion in
                if case .failure(let error) = completion { box.error = error }
            },
            receiveValue: { @Sendable model in box.model = model })
        defer { cancellable.cancel() }
        do {
            while box.model == nil && box.error == nil {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                try Task.checkCancellation()
                if cancelRun(thermalState: ProcessInfo.processInfo.thermalState) {
                    job.cancel()
                    throw DetectorTrainingError.thermalCancelled
                }
                onProgress(job.progress.fractionCompleted)
            }
        } catch {
            job.cancel()
            throw error
        }
        if let error = box.error { throw error }
        guard let detector = box.model else { throw DetectorTrainingError.emptyTrainPartition }
        let secondsPerPage = Date().timeIntervalSince(startedAt) / Double(trainImages.count)
        let bankDir = await bank.directory
        let candidateDir = bankDir.appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("candidate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: candidateDir, withIntermediateDirectories: true)
        let modelURL = candidateDir.appendingPathComponent("Detector.mlmodel")
        try detector.write(to: modelURL)
        let compiled = try await MLModel.compileModel(at: modelURL)
        try FileManager.default.copyItem(at: compiled,
                                         to: candidateDir.appendingPathComponent("Detector.mlmodelc"))
        return TrainedCandidate(modelURL: modelURL,
                                compiledURL: candidateDir.appendingPathComponent("Detector.mlmodelc"),
                                secondsPerPage: secondsPerPage,
                                pages: trainImages.count, iterations: maxIterations)
    }
}
