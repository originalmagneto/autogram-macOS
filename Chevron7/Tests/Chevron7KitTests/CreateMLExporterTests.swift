// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
import PDFKit
@testable import Chevron7Kit

final class CreateMLExporterTests: XCTestCase {
    func testLegacyCropBankDoesNotExportIncompletePages() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bank = ExampleBank(directory: directory.appendingPathComponent("bank"))
        let data = TestPDFBuilder.typicalContractPDF()
        let document = TestUncheckedSendable(try XCTUnwrap(PDFDocument(data: data)))
        let element = SecurityElement(kind: .officialStamp, pageIndex: 0,
                                      boundingBox: .init(x: 0.5, y: 0, width: 0.5, height: 0.5), confidence: 1)
        let recorder = ExampleBankRecorder(bank: bank, detectorVersion: "test")
        let output = directory.appendingPathComponent("export")
        let url = try awaitAsyncThrowing {
            try await recorder.record(document: document.value, documentData: data, element: element, label: .kind(.officialStamp))
            return try await CreateMLExporter.export(bank: bank, to: output)
        }
        let annotations = try JSONDecoder().decode([CreateMLImageAnnotation].self, from: Data(contentsOf: url))
        XCTAssertTrue(annotations.isEmpty, "Individual crop decisions do not establish complete page annotations")
    }

    func testAnnotationsUseCentrePixelCoordinatesWithTopLeftOrigin() {
        // Box occupies the bottom-right quadrant of a 1000x500 image.
        let page = ReviewedBankPage(documentSHA256: "d", pageIndex: 2,
                                    boxes: [.init(kind: .officialStamp, box: .init(x: 0.5, y: 0, width: 0.5, height: 0.5))],
                                    reviewedAt: Date(), detectorVersion: "t")
        let result = CreateMLExporter.annotations(for: [page], imageSizes: ["d-p2.png": CGSize(width: 1000, height: 500)])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].image, "d-p2.png")
        XCTAssertEqual(result[0].annotations.count, 1, "Negatívy sa neexportujú ako boxy")
        let box = result[0].annotations[0]
        XCTAssertEqual(box.label, "officialStamp")
        XCTAssertEqual(box.coordinates.x, 750, accuracy: 1e-6)
        XCTAssertEqual(box.coordinates.y, 375, accuracy: 1e-6)
        XCTAssertEqual(box.coordinates.width, 500, accuracy: 1e-6)
        XCTAssertEqual(box.coordinates.height, 250, accuracy: 1e-6)
    }

    func testCompletePagesWithNoBoxesStillAppearWithEmptyAnnotations() {
        let page = ReviewedBankPage(documentSHA256: "d", pageIndex: 0, boxes: [], reviewedAt: Date(), detectorVersion: "t")
        let result = CreateMLExporter.annotations(for: [page], imageSizes: ["d-p0.png": CGSize(width: 10, height: 10)])
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].annotations.isEmpty)
    }

    func testAnnotationsJSONShapeMatchesCreateML() throws {
        let annotation = CreateMLImageAnnotation(image: "a.png", annotations: [
            .init(label: "initial", coordinates: .init(x: 1, y: 2, width: 3, height: 4))])
        let data = try JSONEncoder().encode([annotation])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(object[0]["image"] as? String, "a.png")
        let first = try XCTUnwrap((object[0]["annotations"] as? [[String: Any]])?.first)
        XCTAssertEqual(first["label"] as? String, "initial")
        XCTAssertEqual((first["coordinates"] as? [String: Double])?["width"], 3)
    }

    func testDocumentPartitionDoesNotChangeWhenMorePagesAreAdded() {
        let first = ReviewedBankPage(documentSHA256: "same-document", pageIndex: 0, boxes: [], reviewedAt: Date(), detectorVersion: "t")
        var second = first
        second.pageIndex = 1
        var other = first
        other.documentSHA256 = "other-document"
        let original = CreateMLExporter.documentSplits(for: [first])
        let expanded = CreateMLExporter.documentSplits(for: [other, second, first])
        let assignment = expanded.first { $0.documentSHA256 == "same-document" }
        XCTAssertEqual(expanded.count, 2)
        XCTAssertEqual(assignment?.partition, original.first?.partition)
        XCTAssertEqual(assignment?.images, ["same-document-p0.png", "same-document-p1.png"])
        XCTAssertTrue(expanded.allSatisfy { ["train", "validation", "test"].contains($0.partition) })
    }
}
