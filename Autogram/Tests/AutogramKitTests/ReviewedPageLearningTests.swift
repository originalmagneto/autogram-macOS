import XCTest
import PDFKit
@testable import AutogramKit

final class ReviewedPageLearningTests: XCTestCase {
    private struct ConstantPrints: FeaturePrintProviding {
        func featureVector(for image: CGImage) async throws -> FeatureVector { .init(values: [1, 2, 3]) }
    }

    private func fixture() throws -> (URL, ExampleBank, ExampleBankRecorder, Data, TestUncheckedSendable<PDFDocument>) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let bank = ExampleBank(directory: directory.appendingPathComponent("bank"))
        let data = TestPDFBuilder.build(pages: [(CGSize(width: 1000, height: 500), { _, _ in })])
        return (directory, bank, ExampleBankRecorder(bank: bank, featurePrints: ConstantPrints(), pageRenderWidth: 1000,
                                                    detectorVersion: "test"), data,
                TestUncheckedSendable(try XCTUnwrap(PDFDocument(data: data))))
    }

    func testPhysicalOnlyPositiveForgetsPreviousCrop() throws {
        let (_, bank, recorder, data, document) = try fixture()
        let visible = SecurityElement(kind: .officialStamp, pageIndex: 0,
                                      boundingBox: .init(x: 0.5, y: 0, width: 0.5, height: 0.5), confidence: 1)
        var original = visible
        original.observation = .physicalOriginal
        let physical = original
        try awaitAsyncThrowing {
            try await recorder.record(document: document.value, documentData: data, element: visible, label: .kind(.officialStamp))
            try await recorder.record(document: document.value, documentData: data, element: physical, label: .kind(.officialStamp))
        }
        XCTAssertTrue(awaitAsync { await bank.entries() }.isEmpty)
        let cropDirectory = awaitAsync { await bank.cropsDirectory }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: cropDirectory.path).isEmpty)
    }

    func testCropLabelsAreCanonicalAndRejectedScanOtherRemainsNegative() throws {
        let (_, bank, recorder, data, document) = try fixture()
        let signature = SecurityElement(kind: .certifiedSignature, pageIndex: 0,
                                        boundingBox: .init(x: 0.1, y: 0.1, width: 0.2, height: 0.2), confidence: 1)
        let rejected = SecurityElement(kind: .other, pageIndex: 0,
                                       boundingBox: .init(x: 0.5, y: 0.5, width: 0.1, height: 0.1), confidence: 1,
                                       reviewState: .rejected)
        try awaitAsyncThrowing {
            try await recorder.record(document: document.value, documentData: data, element: signature, label: .kind(.certifiedSignature))
            try await recorder.record(document: document.value, documentData: data, element: rejected, label: .negative)
        }
        let entries = awaitAsync { await bank.entries() }
        XCTAssertEqual(entries.first { $0.id == signature.id }?.label, .kind(.handwrittenSignature))
        XCTAssertEqual(entries.first { $0.id == rejected.id }?.label, .negative)
    }

    func testPendingPageCannotBecomeComplete() throws {
        let (directory, bank, recorder, data, document) = try fixture()
        let pending = SecurityElement(kind: .officialStamp, pageIndex: 0,
                                      boundingBox: .init(x: 0.5, y: 0, width: 0.5, height: 0.5), confidence: 1)
        try awaitAsyncThrowing {
            try await recorder.recordReviewedPage(document: document.value, documentData: data, pageIndex: 0, elements: [])
        }
        XCTAssertThrowsError(try awaitAsyncThrowing {
            try await recorder.recordReviewedPage(document: document.value, documentData: data, pageIndex: 0, elements: [pending])
        })
        let output = directory.appendingPathComponent("export")
        let url = try awaitAsyncThrowing { try await CreateMLExporter.export(bank: bank, to: output) }
        XCTAssertTrue(try JSONDecoder().decode([CreateMLImageAnnotation].self, from: Data(contentsOf: url)).isEmpty)
    }

    func testCompletePageExportsOnlyConfirmedVisualBoxesWithCorrectCoordinates() throws {
        let (directory, bank, recorder, data, document) = try fixture()
        let confirmed = SecurityElement(kind: .roundOfficialStamp, pageIndex: 0,
                                        boundingBox: .init(x: 0.5, y: 0, width: 0.5, height: 0.5), confidence: 1,
                                        reviewState: .confirmed)
        let rejected = SecurityElement(kind: .initial, pageIndex: 0,
                                       boundingBox: .init(x: 0.1, y: 0.8, width: 0.1, height: 0.1), confidence: 1,
                                       reviewState: .rejected)
        let output = directory.appendingPathComponent("export")
        let url = try awaitAsyncThrowing {
            try await recorder.recordReviewedPage(document: document.value, documentData: data, pageIndex: 0,
                                                   elements: [confirmed, rejected])
            return try await CreateMLExporter.export(bank: bank, to: output)
        }
        let annotations = try JSONDecoder().decode([CreateMLImageAnnotation].self, from: Data(contentsOf: url))
        XCTAssertEqual(annotations.count, 1)
        XCTAssertEqual(annotations.first?.annotations, [.init(label: "officialStamp", coordinates: .init(x: 750, y: 375, width: 500, height: 250))])
    }

    func testConfirmedPhysicalObservationRejectsPageAndInvalidatesPreviousSnapshot() throws {
        let (directory, bank, recorder, data, document) = try fixture()
        let physical = SecurityElement(kind: .bindingCord, pageIndex: 0, boundingBox: .zero, confidence: 1,
                                       detectedByAI: false, observation: .physicalOriginal,
                                       originalLocation: "Na hrane", newDocumentPageIndex: 0)
        try awaitAsyncThrowing {
            try await recorder.recordReviewedPage(document: document.value, documentData: data, pageIndex: 0, elements: [])
        }
        XCTAssertEqual(try awaitAsyncThrowing { try await bank.reviewedPages().count }, 1)
        XCTAssertThrowsError(try awaitAsyncThrowing {
            try await recorder.recordReviewedPage(document: document.value, documentData: data, pageIndex: 0,
                                                   elements: [physical])
        }) { error in
            guard case ExampleBankRecorder.RecorderError.unlocalizedPhysicalElement = error else {
                return XCTFail("Expected an unlocalized physical element error, got \(error)")
            }
        }
        let output = directory.appendingPathComponent("export")
        let url = try awaitAsyncThrowing { try await CreateMLExporter.export(bank: bank, to: output) }
        XCTAssertTrue(try JSONDecoder().decode([CreateMLImageAnnotation].self, from: Data(contentsOf: url)).isEmpty)
        XCTAssertTrue(awaitAsync { await bank.entries() }.isEmpty, "A manual observation cannot fabricate a positive crop")
    }

    func testUnsupportedConfirmedVisibleElementRejectsWholePage() throws {
        let (_, _, recorder, data, document) = try fixture()
        let other = SecurityElement(kind: .other, pageIndex: 0,
                                    boundingBox: .init(x: 0.1, y: 0.1, width: 0.2, height: 0.2), confidence: 1,
                                    reviewState: .confirmed)
        XCTAssertThrowsError(try awaitAsyncThrowing {
            try await recorder.recordReviewedPage(document: document.value, documentData: data, pageIndex: 0, elements: [other])
        })
    }

    func testReviewedEmptyPageRendersPersistsAndExportsIntoFreshFolders() throws {
        let (directory, bank, recorder, data, document) = try fixture()
        try awaitAsyncThrowing {
            try await recorder.recordReviewedPage(document: document.value, documentData: data, pageIndex: 0, elements: [])
        }
        let bankDirectory = awaitAsync { await bank.directory }
        let reloaded = ExampleBank(directory: bankDirectory)
        let output = directory.appendingPathComponent("export")
        let first = try awaitAsyncThrowing { try await CreateMLExporter.export(bank: reloaded, to: output) }
        let second = try awaitAsyncThrowing { try await CreateMLExporter.export(bank: reloaded, to: output) }
        XCTAssertNotEqual(first.deletingLastPathComponent(), second.deletingLastPathComponent())
        let annotations = try JSONDecoder().decode([CreateMLImageAnnotation].self, from: Data(contentsOf: second))
        XCTAssertEqual(annotations.count, 1)
        XCTAssertTrue(try XCTUnwrap(annotations.first).annotations.isEmpty)
        let image = second.deletingLastPathComponent().appendingPathComponent(try XCTUnwrap(annotations.first).image)
        XCTAssertEqual(CreateMLExporter.imageSize(at: image), CGSize(width: 1000, height: 500))
        let splitsURL = second.deletingLastPathComponent().appendingPathComponent("splits.json")
        let splits = try JSONDecoder().decode([CreateMLDocumentSplit].self, from: Data(contentsOf: splitsURL))
        XCTAssertEqual(splits.count, 1)
        XCTAssertEqual(splits.first?.images, annotations.map(\.image))
    }

    func testAddingAndRemovingCropInvalidatesReviewedPage() throws {
        let (directory, bank, recorder, data, document) = try fixture()
        let element = SecurityElement(kind: .initial, pageIndex: 0,
                                      boundingBox: .init(x: 0.1, y: 0.1, width: 0.2, height: 0.2), confidence: 1,
                                      reviewState: .confirmed)
        let output = directory.appendingPathComponent("export")
        let afterAdding = try awaitAsyncThrowing {
            try await recorder.recordReviewedPage(document: document.value, documentData: data, pageIndex: 0, elements: [])
            try await recorder.record(document: document.value, documentData: data, element: element, label: .kind(.initial))
            return try await CreateMLExporter.export(bank: bank, to: output)
        }
        XCTAssertTrue(try JSONDecoder().decode([CreateMLImageAnnotation].self, from: Data(contentsOf: afterAdding)).isEmpty)
        let afterRemoving = try awaitAsyncThrowing {
            try await recorder.recordReviewedPage(document: document.value, documentData: data, pageIndex: 0, elements: [element])
            try await recorder.forget(elementID: element.id)
            return try await CreateMLExporter.export(bank: bank, to: output)
        }
        XCTAssertTrue(try JSONDecoder().decode([CreateMLImageAnnotation].self, from: Data(contentsOf: afterRemoving)).isEmpty)
    }

    func testExplicitInvalidationRemovesSnapshotWithoutCropEntries() throws {
        let (directory, bank, recorder, data, document) = try fixture()
        let output = directory.appendingPathComponent("export")
        let before = try awaitAsyncThrowing {
            try await recorder.recordReviewedPage(document: document.value, documentData: data, pageIndex: 0, elements: [])
            return try await CreateMLExporter.export(bank: bank, to: output)
        }
        XCTAssertEqual(try JSONDecoder().decode([CreateMLImageAnnotation].self, from: Data(contentsOf: before)).count, 1)
        let url = try awaitAsyncThrowing {
            try await bank.invalidateReviewedPage(documentSHA256: AttestationClauseGenerator.sha256Hex(of: data), pageIndex: 0)
            return try await CreateMLExporter.export(bank: bank, to: output)
        }
        XCTAssertTrue(try JSONDecoder().decode([CreateMLImageAnnotation].self, from: Data(contentsOf: url)).isEmpty)
    }

    func testMissingPageImageIsExcludedFromAnnotationsAndSplits() throws {
        let (directory, bank, recorder, data, document) = try fixture()
        try awaitAsyncThrowing {
            try await recorder.recordReviewedPage(document: document.value, documentData: data, pageIndex: 0, elements: [])
        }
        let pagesDirectory = awaitAsync { await bank.pagesDirectory }
        for image in try FileManager.default.contentsOfDirectory(at: pagesDirectory, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: image)
        }
        let output = directory.appendingPathComponent("export")
        let url = try awaitAsyncThrowing { try await CreateMLExporter.export(bank: bank, to: output) }
        XCTAssertTrue(try JSONDecoder().decode([CreateMLImageAnnotation].self, from: Data(contentsOf: url)).isEmpty)
        let splits = url.deletingLastPathComponent().appendingPathComponent("splits.json")
        XCTAssertTrue(try JSONDecoder().decode([CreateMLDocumentSplit].self, from: Data(contentsOf: splits)).isEmpty)
    }
}
