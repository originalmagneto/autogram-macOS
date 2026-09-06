import XCTest
import CoreGraphics
@testable import AutogramKit

final class CandidateQualityFilterTests: XCTestCase {
    /// Draws into a white 100x100 bitmap and returns both the pixels and the image.
    private func bitmap(_ draw: (CGContext) -> Void) throws -> (pixels: PixelMap, image: CGImage) {
        let side = 100
        let context = try XCTUnwrap(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                              bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        draw(context)
        let image = try XCTUnwrap(context.makeImage())
        let pixels = try XCTUnwrap(PixelMap(cgImage: image, targetWidth: side))
        return (pixels, image)
    }

    private func page(pixels: PixelMap, image: CGImage, textBoxes: [NormalizedRect]) -> PreparedPage {
        var exclusions = BuiltInVisionProvider.VisionExclusions()
        exclusions.textBoxes = textBoxes
        return PreparedPage(pageIndex: 0, pixels: pixels, image: image, exclusions: exclusions)
    }

    func testTextCoverageCountsOverlappingBoxesOnlyOnce() {
        let box = NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        let half = NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.2)
        let coverage = CandidateQualityFilter.textCoverage(of: box, textBoxes: [half, half])
        XCTAssertEqual(coverage, 0.5, accuracy: 0.02)
    }

    func testTextCoverageIsZeroForDisjointText() {
        let box = NormalizedRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2)
        let elsewhere = NormalizedRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)
        XCTAssertEqual(CandidateQualityFilter.textCoverage(of: box, textBoxes: [elsewhere]), 0)
    }

    func testHollowRectangleIsMostlyPerimeterInkWhileCentreBlobIsNot() throws {
        let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)

        let hollow = try bitmap { context in
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
            context.setLineWidth(3)
            context.stroke(CGRect(x: 3, y: 3, width: 94, height: 94))
        }
        XCTAssertGreaterThan(CandidateQualityFilter.perimeterInkFraction(of: full, pixels: hollow.pixels), 0.9)

        let blob = try bitmap { context in
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 30, y: 30, width: 40, height: 40))
        }
        XCTAssertLessThan(CandidateQualityFilter.perimeterInkFraction(of: full, pixels: blob.pixels), 0.2)
    }

    func testStampHintedCandidateSurvivesFullTextCoverage() throws {
        let bitmap = try bitmap { _ in }
        let box = NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        let candidate = DetectionCandidate(pageIndex: 0, box: box, sources: [.builtIn],
                                           kindHint: .officialStamp, hintConfidence: 0.8)
        let prepared = page(pixels: bitmap.pixels, image: bitmap.image, textBoxes: [box])
        XCTAssertNotNil(CandidateQualityFilter.filter(candidate, page: prepared),
                        "Pečiatka sa nesmie zahodiť podľa pokrytia textom")
    }

    func testSignatureHintedCandidateOverPrintedTextIsDropped() throws {
        let bitmap = try bitmap { _ in }
        let box = NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        // A text box covering 30 % of the candidate height, so coverage is above the limit.
        let text = NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.16)
        let candidate = DetectionCandidate(pageIndex: 0, box: box, sources: [.builtIn],
                                           kindHint: .handwrittenSignature, hintConfidence: 0.75)
        let prepared = page(pixels: bitmap.pixels, image: bitmap.image, textBoxes: [text])
        XCTAssertGreaterThan(CandidateQualityFilter.textCoverage(of: box, textBoxes: [text]), 0.3)
        XCTAssertNil(CandidateQualityFilter.filter(candidate, page: prepared))
    }

    func testRuledCellFullOfTextIsDroppedByEdgeLinesEvenWhenPerimeterInkIsLow() throws {
        // Thin border plus a heavy "text" block inside: most ink is interior, so the
        // perimeter rule fails, but all four edges are ruled.
        let cell = try bitmap { context in
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
            context.setLineWidth(2)
            context.stroke(CGRect(x: 1, y: 1, width: 98, height: 98))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 15, y: 30, width: 70, height: 40))
        }
        let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        XCTAssertLessThan(CandidateQualityFilter.perimeterInkFraction(of: full, pixels: cell.pixels), 0.6)
        XCTAssertEqual(CandidateQualityFilter.ruledSides(of: full, pixels: cell.pixels), 4)
        let candidate = DetectionCandidate(pageIndex: 0, box: full, sources: [.builtIn],
                                           kindHint: .handwrittenSignature, hintConfidence: 0.75)
        XCTAssertNil(CandidateQualityFilter.filter(candidate, page: page(pixels: cell.pixels, image: cell.image, textBoxes: [])))

        let signature = try bitmap { context in
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
            context.setLineWidth(3)
            context.move(to: CGPoint(x: 10, y: 50))
            context.addCurve(to: CGPoint(x: 90, y: 50), control1: CGPoint(x: 30, y: 90), control2: CGPoint(x: 70, y: 10))
            context.strokePath()
        }
        XCTAssertEqual(CandidateQualityFilter.ruledSides(of: full, pixels: signature.pixels), 0)
    }

    func testInkInsideOCRTextIsDroppedButInkOutsideSurvives() throws {
        let blob = try bitmap { context in
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 20, y: 40, width: 60, height: 20))
        }
        let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        let candidate = DetectionCandidate(pageIndex: 0, box: full, sources: [.builtIn],
                                           kindHint: .handwrittenSignature, hintConfidence: 0.75)
        // The blob sits in rows 40...60 of a 100 px bitmap: normalized y 0.4...0.6.
        let covering = NormalizedRect(x: 0.15, y: 0.35, width: 0.7, height: 0.3)
        XCTAssertGreaterThan(CandidateQualityFilter.inkInsideText(of: full, textBoxes: [covering], pixels: blob.pixels).fraction, 0.9)
        XCTAssertNil(CandidateQualityFilter.filter(candidate, page: page(pixels: blob.pixels, image: blob.image, textBoxes: [covering])))

        let elsewhere = NormalizedRect(x: 0.0, y: 0.8, width: 0.2, height: 0.15)
        XCTAssertNotNil(CandidateQualityFilter.filter(candidate, page: page(pixels: blob.pixels, image: blob.image, textBoxes: [elsewhere])))
    }

    func testRuledBoxWithoutTextIsDroppedByPerimeterInk() throws {
        let hollow = try bitmap { context in
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
            context.setLineWidth(3)
            context.stroke(CGRect(x: 3, y: 3, width: 94, height: 94))
        }
        let candidate = DetectionCandidate(pageIndex: 0, box: .init(x: 0, y: 0, width: 1, height: 1),
                                           sources: [.builtIn], kindHint: .handwrittenSignature,
                                           hintConfidence: 0.75)
        let prepared = page(pixels: hollow.pixels, image: hollow.image, textBoxes: [])
        XCTAssertNil(CandidateQualityFilter.filter(candidate, page: prepared))
    }
}
