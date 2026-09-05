import XCTest
import PDFKit
import AutogramKit
@testable import AutogramApp

@MainActor
final class ZakoBankRecordingTests: XCTestCase {
    private struct ConstantPrints: FeaturePrintProviding {
        func featureVector(for image: CGImage) async throws -> FeatureVector { FeatureVector(values: [0.5]) }
    }

    private func makeStore(learn: Bool) throws -> (ZakoSessionStore, ExampleBank) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zako-bank-\(UUID().uuidString)", isDirectory: true)
        let bank = ExampleBank(directory: dir)
        let settingsStore = AppSettingsStore()
        settingsStore.settings.learnFromReviews = learn
        let store = ZakoSessionStore(settingsStore: settingsStore, exampleBank: bank)
        store.bankRecorderFactory = { bank, version in
            ExampleBankRecorder(bank: bank, featurePrints: ConstantPrints(), detectorVersion: version)
        }
        let data = TestPDFBuilderApp.typicalContractPDF()
        store.document = try XCTUnwrap(PDFDocument(data: data))
        store.documentData = data
        store.analysis = PDFAnalysisEngine().analyze(document: store.document!)
        return (store, bank)
    }

    func testConfirmAndRejectWriteBankEntriesAndReturnRemovesThem() async throws {
        let (store, bank) = try makeStore(learn: true)
        let stamp = SecurityElement(kind: .officialStamp, pageIndex: 0,
                                    boundingBox: .init(x: 0.6, y: 0.1, width: 0.2, height: 0.2), confidence: 0.8)
        let noise = SecurityElement(kind: .handwrittenSignature, pageIndex: 0,
                                    boundingBox: .init(x: 0.1, y: 0.7, width: 0.3, height: 0.05), confidence: 0.5)
        store.securityElements = [stamp, noise]

        store.confirmSecurityElement(id: stamp.id)
        store.rejectSecurityElement(id: noise.id)
        await store.waitForBankWrites()

        let entries = await bank.entries()
        XCTAssertEqual(Set(entries.map(\.id)), [stamp.id, noise.id])
        XCTAssertEqual(entries.first { $0.id == stamp.id }?.label, .kind(.officialStamp))
        XCTAssertEqual(entries.first { $0.id == noise.id }?.label, .negative)

        store.returnSecurityElementToReview(id: stamp.id)
        await store.waitForBankWrites()
        let remainingIDs = await bank.entries().map(\.id)
        XCTAssertEqual(remainingIDs, [noise.id])
    }

    func testLearningOffWritesNothing() async throws {
        let (store, bank) = try makeStore(learn: false)
        let stamp = SecurityElement(kind: .officialStamp, pageIndex: 0,
                                    boundingBox: .init(x: 0.6, y: 0.1, width: 0.2, height: 0.2), confidence: 0.8)
        store.securityElements = [stamp]
        store.confirmSecurityElement(id: stamp.id)
        await store.waitForBankWrites()
        let entries = await bank.entries()
        XCTAssertTrue(entries.isEmpty)
    }

    func testRapidDecisionsOnOneElementApplyInOrder() async throws {
        let (store, bank) = try makeStore(learn: true)
        let stamp = SecurityElement(kind: .officialStamp, pageIndex: 0,
                                    boundingBox: .init(x: 0.6, y: 0.1, width: 0.2, height: 0.2), confidence: 0.8)
        store.securityElements = [stamp]

        store.confirmSecurityElement(id: stamp.id)
        store.returnSecurityElementToReview(id: stamp.id)
        await store.waitForBankWrites()
        let entriesAfterReturn = await bank.entries()
        XCTAssertTrue(entriesAfterReturn.isEmpty, "Návrat na kontrolu po potvrdení musí záznam odstrániť")

        store.rejectSecurityElement(id: stamp.id)
        store.confirmSecurityElement(id: stamp.id)
        await store.waitForBankWrites()
        let entriesAfterConfirm = await bank.entries()
        XCTAssertEqual(entriesAfterConfirm.first?.label, .kind(.officialStamp))
    }

    func testReviewStampCarriesDetectorIdentifier() throws {
        let (store, _) = try makeStore(learn: true)
        XCTAssertTrue(store.securityReviewStamp.detectorIdentifier.hasPrefix("LayeredDetectionProvider/"))
    }
}
