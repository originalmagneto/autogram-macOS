// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class DetectorTrainerTests: XCTestCase {
    private func annotation(image: String) -> CreateMLImageAnnotation {
        CreateMLImageAnnotation(image: image, annotations: [
            .init(label: "officialStamp", coordinates: .init(x: 10, y: 10, width: 4, height: 4))])
    }

    private func dataset(names: [String]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in names {
            try Data([0, 1, 2, 3]).write(to: folder.appendingPathComponent(name))
        }
        return folder
    }

    func testStagingContainsOnlyTrainPartition() throws {
        let source = try dataset(names: ["a-p0.png", "b-p0.png"])
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try DetectorTrainer.stageTrainDirectory(dataset: source, trainImages: ["a-p0.png"],
                                                trainAnnotations: [annotation(image: "a-p0.png")],
                                                to: staged)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.appendingPathComponent("a-p0.png").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.appendingPathComponent("b-p0.png").path))
        let written = try JSONDecoder().decode([CreateMLImageAnnotation].self,
                                               from: Data(contentsOf: staged.appendingPathComponent("annotations.json")))
        XCTAssertEqual(written.map(\.image), ["a-p0.png"])
    }

    func testStagingThrowsOnMissingImage() throws {
        let source = try dataset(names: [])
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try DetectorTrainer.stageTrainDirectory(
            dataset: source, trainImages: ["missing.png"],
            trainAnnotations: [annotation(image: "missing.png")], to: staged))
    }
    func testSecondStartWhileRunningThrowsBusy() async throws {
        actor Gate {
            private var waiters: [CheckedContinuation<Void, Never>] = []
            func open() {
                for waiter in waiters { waiter.resume() }
                waiters = []
            }
            func wait() async {
                await withCheckedContinuation { waiters.append($0) }
            }
        }
        let job = DetectorTrainingJob()
        let gate = Gate()
        let first = Task<Int, Error> {
            try await job.run {
                await gate.wait()
                return 1
            }
        }
        while await !job.isRunning { await Task.yield() }
        do {
            _ = try await job.run { return 2 }
            XCTFail("second start must throw")
        } catch {
            XCTAssertEqual(error as? DetectorTrainingError, .busy)
        }
        await gate.open()
        let value = try await first.value
        XCTAssertEqual(value, 1)
    }

    func testCancellationAbortsRun() async {
        let job = DetectorTrainingJob()
        let task = Task<Int, Error> {
            try await job.run {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return 1
            }
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("cancelled run must throw")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testThermalGateRefusesSeriousAndCritical() {
        XCTAssertFalse(DetectorTrainer.refuseStart(thermalState: .nominal))
        XCTAssertFalse(DetectorTrainer.refuseStart(thermalState: .fair))
        XCTAssertTrue(DetectorTrainer.refuseStart(thermalState: .serious))
        XCTAssertTrue(DetectorTrainer.refuseStart(thermalState: .critical))
    }

    func testThermalCancelsOnlyOnCritical() {
        XCTAssertFalse(DetectorTrainer.cancelRun(thermalState: .nominal))
        XCTAssertFalse(DetectorTrainer.cancelRun(thermalState: .fair))
        XCTAssertFalse(DetectorTrainer.cancelRun(thermalState: .serious))
        XCTAssertTrue(DetectorTrainer.cancelRun(thermalState: .critical))
    }
}
