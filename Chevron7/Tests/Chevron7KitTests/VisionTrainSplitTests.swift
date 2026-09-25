// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class VisionTrainSplitTests: XCTestCase {
    private func splits() -> [CreateMLDocumentSplit] {
        [
            .init(documentSHA256: "docA", partition: "train", images: ["a-p0.png", "a-p1.png"]),
            .init(documentSHA256: "docB", partition: "validation", images: ["b-p0.png"]),
            .init(documentSHA256: "docC", partition: "test", images: ["c-p0.png", "c-p1.png"]),
        ]
    }

    func testTrainPartitionCollectsOnlyTrainImages() {
        XCTAssertEqual(VisionTrainSplit.images(in: "train", splits: splits()), ["a-p0.png", "a-p1.png"])
    }

    func testValidationAndTestPartitionsStaySeparate() {
        XCTAssertEqual(VisionTrainSplit.images(in: "validation", splits: splits()), ["b-p0.png"])
        XCTAssertEqual(VisionTrainSplit.images(in: "test", splits: splits()), ["c-p0.png", "c-p1.png"])
    }

    func testAnnotationsFilterKeepsOnlyRequestedImages() {
        let all = [
            CreateMLImageAnnotation(image: "a-p0.png", annotations: []),
            CreateMLImageAnnotation(image: "b-p0.png", annotations: []),
        ]
        let result = VisionTrainSplit.annotations(for: ["b-p0.png"], from: all)
        XCTAssertEqual(result.map(\.image), ["b-p0.png"])
    }

    func testKindForTrainingLabelMapsKnownLabels() {
        XCTAssertEqual(VisionTrainSplit.kind(forTrainingLabel: "officialStamp"), .officialStamp)
        XCTAssertEqual(VisionTrainSplit.kind(forTrainingLabel: "handwrittenSignature"), .handwrittenSignature)
        XCTAssertEqual(VisionTrainSplit.kind(forTrainingLabel: "bindingCord"), .bindingCord)
        XCTAssertNil(VisionTrainSplit.kind(forTrainingLabel: "noSuchLabel"))
    }
}
