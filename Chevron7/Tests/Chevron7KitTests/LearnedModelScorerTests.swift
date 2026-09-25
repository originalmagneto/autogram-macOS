// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
import UniformTypeIdentifiers
@testable import Chevron7Kit

final class LearnedModelScorerTests: XCTestCase {
    private func writePNG(_ image: CGImage, named name: String, in folder: URL) throws {
        let data = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        try (data as Data).write(to: folder.appendingPathComponent(name))
    }

    private func whiteImage(side: Int = 100) throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return try XCTUnwrap(ctx.makeImage())
    }

    func testScoresStubPredictionsAgainstTruth() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = try whiteImage()
        try writePNG(image, named: "p0.png", in: folder)
        try writePNG(image, named: "p1.png", in: folder)
        let truth = [
            CreateMLImageAnnotation(image: "p0.png", annotations: [
                .init(label: "officialStamp",
                      coordinates: .init(x: 50, y: 50, width: 50, height: 50))]),
            CreateMLImageAnnotation(image: "p1.png", annotations: []),
        ]
        let result = try await LearnedModelScorer.score(
            predict: { _ in
                [LearnedPrediction(box: .init(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                                   label: "officialStamp", confidence: 0.9)]
            },
            imageNames: ["p0.png", "p1.png"], folder: folder, truth: truth)
        XCTAssertEqual(result.pages, 2)
        XCTAssertEqual(result.predictedBoxes, 2)
        let stamp = try XCTUnwrap(result.perLabel["officialStamp"])
        XCTAssertEqual(stamp.truePositives, 1)
        XCTAssertEqual(stamp.falsePositives, 1)
        XCTAssertEqual(stamp.falseNegatives, 0)
    }

    func testMissingImageThrows() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            _ = try await LearnedModelScorer.score(predict: { _ in [] },
                                                   imageNames: ["gone.png"],
                                                   folder: folder, truth: [])
            XCTFail("missing image must throw")
        } catch {
            XCTAssertEqual(error as? LearnedModelScorerError, .unreadableImage("gone.png"))
        }
    }
}
