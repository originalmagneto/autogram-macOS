import XCTest
import PDFKit
@testable import AutogramKit

final class ExampleBankRecorderTests: XCTestCase {
    private struct ConstantPrints: FeaturePrintProviding {
        func featureVector(for image: CGImage) async throws -> FeatureVector { FeatureVector(values: [1, 2, 3]) }
    }

    func testRecordWritesEntryPageAndCrop() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString)", isDirectory: true)
        let bank = ExampleBank(directory: dir)
        let data = TestPDFBuilder.typicalContractPDF()
        let document = try XCTUnwrap(PDFDocument(data: data))
        let element = SecurityElement(kind: .officialStamp, pageIndex: 0,
                                      boundingBox: .init(x: 0.6, y: 0.1, width: 0.2, height: 0.2), confidence: 0.9)
        let recorder = ExampleBankRecorder(bank: bank, featurePrints: ConstantPrints(), detectorVersion: "test/1")
        let doc = TestUncheckedSendable(document)
        try awaitAsyncThrowing { try await recorder.record(document: doc.value, documentData: data, element: element, label: .kind(.officialStamp)) }

        let entries = awaitAsync { await bank.entries() }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].id, element.id)
        XCTAssertEqual(entries[0].label, .kind(.officialStamp))
        XCTAssertEqual(entries[0].documentSHA256, AttestationClauseGenerator.sha256Hex(of: data))
        XCTAssertEqual(entries[0].featureVector.values, [1, 2, 3])
        let pages = awaitAsync { await bank.pagesDirectory }
        let crops = awaitAsync { await bank.cropsDirectory }
        XCTAssertTrue(FileManager.default.fileExists(atPath: pages.appendingPathComponent(entries[0].pageImageFileName).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: crops.appendingPathComponent(entries[0].cropImageFileName).path))
    }

    func testForgetRemovesEntry() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString)", isDirectory: true)
        let bank = ExampleBank(directory: dir)
        let data = TestPDFBuilder.typicalContractPDF()
        let document = try XCTUnwrap(PDFDocument(data: data))
        let element = SecurityElement(kind: .initial, pageIndex: 0,
                                      boundingBox: .init(x: 0.1, y: 0.1, width: 0.1, height: 0.1), confidence: 1)
        let recorder = ExampleBankRecorder(bank: bank, featurePrints: ConstantPrints(), detectorVersion: "test/1")
        let doc = TestUncheckedSendable(document)
        try awaitAsyncThrowing {
            try await recorder.record(document: doc.value, documentData: data, element: element, label: .negative)
            try await recorder.forget(elementID: element.id)
        }
        XCTAssertTrue(awaitAsync { await bank.entries() }.isEmpty)
    }
}
