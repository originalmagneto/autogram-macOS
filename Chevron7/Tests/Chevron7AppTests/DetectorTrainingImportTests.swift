// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation
import XCTest
@testable import Chevron7Kit
@testable import Chevron7App

/// A staged import candidate made of text files: enough for the registry and
/// the flow bookkeeping, no CoreML compile involved.
private func stageFixtureCandidate(in modelsRoot: URL, content: String) throws -> TrainedCandidate {
    let dir = modelsRoot.appendingPathComponent("candidate-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let model = dir.appendingPathComponent("Detector.mlmodel")
    try Data(content.utf8).write(to: model)
    let compiled = dir.appendingPathComponent("Detector.mlmodelc", isDirectory: true)
    try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
    return TrainedCandidate(modelURL: model, compiledURL: compiled,
                            secondsPerPage: 16, pages: 40, iterations: 50)
}

/// The import gate as the reviewer experiences it: staging, scoring and the
/// promotion decision run through `DetectorTrainingFlow` with a fixture
/// candidate and canned metrics, so no real model is compiled or loaded.
@MainActor
final class DetectorTrainingImportTests: XCTestCase {
    private func isResult(_ flow: DetectorTrainingFlow) -> Bool {
        if case .result = flow.step { return true }
        return false
    }

    private func waitForResult(_ flow: DetectorTrainingFlow, timeout: TimeInterval = 10) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !isResult(flow), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func readyReport() -> DetectorTrainingReadiness {
        DetectorTrainingReadiness(reviewedPages: 40, documents: 8,
                                  boxesPerLabel: ["officialStamp": 20],
                                  trainedLabels: ["officialStamp"],
                                  leftOutLabels: [:],
                                  newSinceLastTraining: 0, offerDue: true)
    }

    private func seedActiveModel() async throws -> (DetectorTrainingFlow, ModelRegistry, Data) {
        let store = makeSettingsStore()
        let root = ModelRegistry.modelsDirectory(in: await store.exampleBank.directory)
        let registry = ModelRegistry(root: root)
        _ = try registry.promote(candidate: try stageFixtureCandidate(in: root, content: "active-v1"),
                                 recallGain: 0.1, precisionDelta: 0)
        let flow = DetectorTrainingFlow(settingsStore: store)
        flow.report = readyReport()
        return (flow, registry, try Data(contentsOf: registry.activeModelURL()))
    }

    private func residue(in root: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix("candidate-") }
    }

    func testCancelledImportDiscardsCandidateAndKeepsActive() async throws {
        let (flow, registry, activeBytes) = try await seedActiveModel()
        let root = registry.root
        flow.stageImport = { _, modelsRoot in try stageFixtureCandidate(in: modelsRoot, content: "imported") }
        let entered = XCTestExpectation(description: "scoring entered")
        flow.scoreOverride = { _ in
            entered.fulfill()
            try await Task.sleep(nanoseconds: 30_000_000_000)
            return ([String: LabelMetrics](), [String: LabelMetrics](), Set<String>())
        }
        flow.importModel(from: URL(fileURLWithPath: "/nonexistent.zip"))
        await fulfillment(of: [entered], timeout: 10)
        flow.cancelRun()
        try await waitForResult(flow)
        XCTAssertTrue(isResult(flow))
        XCTAssertFalse(flow.resultPromotable)
        XCTAssertEqual(flow.resultText, "Overenie ste zrušili. Dovezený súbor ostal nedotknutý.")
        XCTAssertEqual(try Data(contentsOf: registry.activeModelURL()), activeBytes)
        XCTAssertTrue(try residue(in: root).isEmpty)
    }

    func testPromotedImportWaitsForConfirmation() async throws {
        let (flow, registry, activeBytes) = try await seedActiveModel()
        let root = registry.root
        flow.stageImport = { _, modelsRoot in try stageFixtureCandidate(in: modelsRoot, content: "imported-v2") }
        flow.scoreOverride = { _ in
            (["officialStamp": LabelMetrics(truePositives: 9, falsePositives: 1, falseNegatives: 1)],
             ["officialStamp": LabelMetrics(truePositives: 5, falsePositives: 5, falseNegatives: 5)],
             Set<String>())
        }
        flow.importModel(from: URL(fileURLWithPath: "/nonexistent.zip"))
        try await waitForResult(flow)
        XCTAssertTrue(flow.resultPromotable)
        // The gate passed, but nothing is active until the reviewer confirms.
        XCTAssertEqual(try Data(contentsOf: registry.activeModelURL()), activeBytes)
        flow.confirmUseNewDetector()
        let activeURL = registry.activeModelURL()
        let deadline = Date().addingTimeInterval(10)
        var current = try Data(contentsOf: activeURL)
        while current == activeBytes, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
            current = try Data(contentsOf: activeURL)
        }
        XCTAssertEqual(current, Data("imported-v2".utf8))
        XCTAssertTrue(try residue(in: root).isEmpty)
    }
}
