import XCTest
@testable import AutogramKit

final class CandidateMergerTests: XCTestCase {
    private func cand(_ x: Double, _ y: Double, _ w: Double, _ h: Double,
                      source: CandidateSource, hint: SecurityElement.Kind? = nil,
                      conf: Double? = nil, page: Int = 0) -> DetectionCandidate {
        DetectionCandidate(pageIndex: page, box: .init(x: x, y: y, width: w, height: h),
                           sources: [source], kindHint: hint, hintConfidence: conf)
    }

    func testOverlappingCandidatesAreUnionedAndKeepStrongestHint() {
        let a = cand(0.10, 0.10, 0.20, 0.20, source: .builtIn, hint: .officialStamp, conf: 0.7)
        let b = cand(0.12, 0.12, 0.20, 0.20, source: .contour)
        let merged = CandidateMerger.merge([a, b], exclusions: .empty)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].sources, [.builtIn, .contour])
        XCTAssertEqual(merged[0].kindHint, .officialStamp)
        XCTAssertEqual(merged[0].box.x, 0.10, accuracy: 1e-9)
        XCTAssertEqual(merged[0].box.width, 0.22, accuracy: 1e-9)
    }

    func testDifferentPagesNeverMerge() {
        let a = cand(0.1, 0.1, 0.2, 0.2, source: .builtIn, page: 0)
        let b = cand(0.1, 0.1, 0.2, 0.2, source: .contour, page: 1)
        XCTAssertEqual(CandidateMerger.merge([a, b], exclusions: .empty).count, 2)
    }

    func testTinyAndHugeBoxesAreDropped() {
        let tiny = cand(0.5, 0.5, 0.01, 0.01, source: .contour)      // area 1e-4 < 2e-4
        let huge = cand(0.0, 0.0, 0.6, 0.6, source: .saliency)       // area 0.36 > 0.25
        let ok = cand(0.2, 0.2, 0.1, 0.1, source: .contour)
        let merged = CandidateMerger.merge([tiny, huge, ok], exclusions: .empty)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].box.x, 0.2, accuracy: 1e-9)
    }

    func testExtremeAspectIsDropped() {
        let line = cand(0.1, 0.5, 0.5, 0.02, source: .contour) // aspect 25 > 18
        XCTAssertTrue(CandidateMerger.merge([line], exclusions: .empty).isEmpty)
    }

    func testCandidateOverlappingTextIsDropped() {
        var exclusions = VisionExclusions.empty
        exclusions.textBoxes = [.init(x: 0.1, y: 0.1, width: 0.3, height: 0.05)]
        let onText = cand(0.1, 0.1, 0.3, 0.05, source: .contour)
        let clear = cand(0.6, 0.6, 0.1, 0.1, source: .contour)
        let merged = CandidateMerger.merge([onText, clear], exclusions: exclusions)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].box.x, 0.6, accuracy: 1e-9)
    }

    func testBuiltInHintSurvivesTextOverlapBecauseBuiltInAlreadyExcluded() {
        var exclusions = VisionExclusions.empty
        exclusions.textBoxes = [.init(x: 0.1, y: 0.1, width: 0.3, height: 0.05)]
        let builtIn = cand(0.1, 0.1, 0.3, 0.05, source: .builtIn, hint: .handwrittenSignature, conf: 0.6)
        XCTAssertEqual(CandidateMerger.merge([builtIn], exclusions: exclusions).count, 1)
    }
}
