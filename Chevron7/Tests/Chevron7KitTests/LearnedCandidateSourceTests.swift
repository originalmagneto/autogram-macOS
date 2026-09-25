// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class LearnedCandidateSourceTests: XCTestCase {
    func testLearnedSourceLabelRenders() {
        let candidate = DetectionCandidate(pageIndex: 0, box: .zero, sources: [.learned])
        XCTAssertEqual(candidate.sourceLabel, "learned")
    }

    func testIdentifierNamesActiveModel() {
        let bank = ExampleBank(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let learned = LearnedCandidateSource(modelID: "deadbeef", predict: { _ in [] })
        let provider = LayeredDetectionProvider.makeDefault(bank: bank, useFoundationModel: false, learnedSource: learned)
        XCTAssertTrue(provider.identifier.contains("learned(deadbeef)"),
                      "SecurityReviewStamp must name the active model, got: \(provider.identifier)")
    }

    func testIdentifierWithoutLearnedSourceUnchanged() {
        let bank = ExampleBank(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let provider = LayeredDetectionProvider.makeDefault(bank: bank, useFoundationModel: false)
        XCTAssertFalse(provider.identifier.contains("learned"))
    }

    func testSourceIsLearned() {
        let source = LearnedCandidateSource(modelID: "abc", predict: { _ in [] })
        XCTAssertEqual(source.source, .learned)
        XCTAssertEqual(source.modelID, "abc")
    }

    func testMapsLabelsToKindHints() async throws {
        let image = try XCTUnwrap(blankImage())
        let source = LearnedCandidateSource(modelID: "abc", predict: { _ in
            [
                LearnedPrediction(box: .init(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
                                  label: "officialStamp", confidence: 0.9),
                LearnedPrediction(box: .init(x: 0.5, y: 0.5, width: 0.2, height: 0.2),
                                  label: "handwrittenSignature", confidence: 0.7),
            ]
        })
        let candidates = try await source.candidates(pageImage: image, pageIndex: 3)
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates[0].sources, [.learned])
        XCTAssertEqual(candidates[0].pageIndex, 3)
        XCTAssertEqual(candidates[0].kindHint, .officialStamp)
        XCTAssertEqual(candidates[0].hintConfidence, 0.9)
        XCTAssertEqual(candidates[0].box, NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        XCTAssertEqual(candidates[1].kindHint, .handwrittenSignature)
    }

    func testDropsUnknownLabels() async throws {
        let image = try XCTUnwrap(blankImage())
        let source = LearnedCandidateSource(modelID: "abc", predict: { _ in
            [LearnedPrediction(box: .zero, label: "noSuchLabel", confidence: 1)]
        })
        let candidates = try await source.candidates(pageImage: image, pageIndex: 0)
        XCTAssertTrue(candidates.isEmpty)
    }

    private func blankImage() -> CGImage? {
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        return ctx?.makeImage()
    }
}
