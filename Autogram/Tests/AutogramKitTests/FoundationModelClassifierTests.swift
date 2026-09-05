import XCTest
import CoreGraphics
import PDFKit
@testable import AutogramKit

final class FoundationModelClassifierTests: XCTestCase {
    private struct FakeJudge: FoundationJudging {
        let result: FoundationJudgement
        let delay: Double
        func judge(crop: CGImage, hint: SecurityElement.Kind?) async throws -> FoundationJudgement {
            if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
            return result
        }
    }

    private func blankImage() throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(ctx.makeImage())
    }

    func testMapsStampJudgementToOfficialStamp() {
        let judgement = FoundationModelClassifier.map(
            FoundationJudgement(isSecurityElement: true, kind: .stamp, descriptionSK: "Okrúhla modrá pečiatka.", confidence: 0.8))
        XCTAssertEqual(judgement.kind, .officialStamp)
        XCTAssertEqual(judgement.confidence, 0.8, accuracy: 1e-9)
        XCTAssertEqual(judgement.descriptionSK, "Okrúhla modrá pečiatka.")
        XCTAssertEqual(judgement.decidedBy, .foundationModel)
    }

    func testNotASecurityElementYieldsNilKindRegardlessOfKindField() {
        let judgement = FoundationModelClassifier.map(
            FoundationJudgement(isSecurityElement: false, kind: .stamp, descriptionSK: "", confidence: 0.9))
        XCTAssertNil(judgement.kind)
    }

    func testTimeoutYieldsUnsureJudgement() throws {
        let classifier = FoundationModelClassifier(
            judge: FakeJudge(result: .init(isSecurityElement: true, kind: .signature, descriptionSK: "", confidence: 1), delay: 2),
            timeoutSeconds: 0.1)
        let image = try blankImage()
        let judgement = try awaitAsyncThrowing { try await classifier.classify(crop: image, hint: nil) }
        XCTAssertNil(judgement.kind)
        XCTAssertEqual(judgement.confidence, 0)
        XCTAssertEqual(judgement.decidedBy, .foundationModel)
    }

    func testLiveModelSeparatesRingFromPlainTextIfAvailable() throws {
        guard let classifier = FoundationModelClassifier.makeIfAvailable() else {
            throw XCTSkip("On-device Foundation Model nie je dostupný")
        }
        let document = try XCTUnwrap(PDFKit.PDFDocument(data: TestPDFBuilder.typicalContractPDF()))
        let page = try XCTUnwrap(document.page(at: 0))
        let rendered = try XCTUnwrap(BuiltInVisionProvider.render(page: page, targetWidth: 760))
        // The ring in typicalContractPDF sits in the lower-right quadrant; text is upper-left.
        let ring = try XCTUnwrap(PageCrop.crop(rendered.cgImage, to: .init(x: 0.55, y: 0.05, width: 0.4, height: 0.35)))
        let text = try XCTUnwrap(PageCrop.crop(rendered.cgImage, to: .init(x: 0.05, y: 0.70, width: 0.5, height: 0.2)))
        let ringJudgement = try awaitAsyncThrowing { try await classifier.classify(crop: ring, hint: nil) }
        let textJudgement = try awaitAsyncThrowing { try await classifier.classify(crop: text, hint: nil) }
        XCTAssertNotNil(ringJudgement.kind, "Kruh má byť rozpoznaný ako prvok")
        XCTAssertNil(textJudgement.kind, "Bežný text nesmie byť prvok")
    }
}
