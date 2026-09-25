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
}
