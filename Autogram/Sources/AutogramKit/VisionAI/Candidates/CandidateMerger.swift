import Foundation

typealias VisionExclusions = BuiltInVisionProvider.VisionExclusions

public enum CandidateMerger {
    public static let minAreaRatio = 0.0002
    public static let maxAreaRatio = 0.25
    public static let maxAspect = 18.0
    public static let exclusionOverlap = 0.3

    static func merge(_ candidates: [DetectionCandidate],
                      exclusions: VisionExclusions,
                      iouThreshold: Double = 0.5) -> [DetectionCandidate] {
        let gated = candidates.filter { passesGates($0, exclusions: exclusions) }
        var result: [DetectionCandidate] = []
        // Strongest hints first so the union keeps them.
        for candidate in gated.sorted(by: { ($0.hintConfidence ?? 0) > ($1.hintConfidence ?? 0) }) {
            if let index = result.firstIndex(where: {
                $0.pageIndex == candidate.pageIndex &&
                SecurityElementMerger.iou($0.box, candidate.box) > iouThreshold
            }) {
                result[index] = union(result[index], candidate)
            } else {
                result.append(candidate)
            }
        }
        return result
    }

    static func passesGates(_ c: DetectionCandidate, exclusions: VisionExclusions) -> Bool {
        let area = c.box.width * c.box.height
        guard area >= minAreaRatio, area <= maxAreaRatio else { return false }
        guard c.box.width > 0, c.box.height > 0 else { return false }
        let aspect = max(c.box.width / c.box.height, c.box.height / c.box.width)
        guard aspect <= maxAspect else { return false }
        // Built-in candidates were already screened against OCR text by BuiltInVisionProvider.
        if c.sources == [.builtIn] { return true }
        return !exclusions.overlapsTextOrBarcode(c.box, threshold: exclusionOverlap)
    }

    static func union(_ a: DetectionCandidate, _ b: DetectionCandidate) -> DetectionCandidate {
        let x0 = min(a.box.x, b.box.x), y0 = min(a.box.y, b.box.y)
        let x1 = max(a.box.x + a.box.width, b.box.x + b.box.width)
        let y1 = max(a.box.y + a.box.height, b.box.y + b.box.height)
        let stronger = (a.hintConfidence ?? -1) >= (b.hintConfidence ?? -1) ? a : b
        return DetectionCandidate(pageIndex: a.pageIndex,
                                  box: .init(x: x0, y: y0, width: x1 - x0, height: y1 - y0),
                                  sources: a.sources.union(b.sources),
                                  kindHint: stronger.kindHint ?? a.kindHint ?? b.kindHint,
                                  hintConfidence: stronger.hintConfidence ?? a.hintConfidence ?? b.hintConfidence)
    }
}
