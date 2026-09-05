import Foundation
import CoreGraphics

/// Cheap geometric pre-filters that drop candidates a scanned form produces in
/// bulk: printed text blocks and ruled table cells. Running before
/// classification keeps them away from the on-device model entirely.
enum CandidateQualityFilter {
    /// Candidate boxes whose text coverage exceeds this are printed text, not ink.
    static let maximumTextCoverage = 0.25
    /// Above this share of ink on the border the candidate is a ruled box.
    static let maximumPerimeterInkFraction = 0.6
    /// Perimeter ink is only meaningful once the box holds enough ink to measure.
    static let minimumInkPixelsForPerimeterRule = 200
    /// Resolution of the coverage grid, per axis.
    static let coverageGridSize = 64

    /// Fraction of the candidate box covered by the union of OCR text boxes.
    static func textCoverage(of box: NormalizedRect, textBoxes: [NormalizedRect]) -> Double {
        guard box.width > 0, box.height > 0, !textBoxes.isEmpty else { return 0 }
        let n = coverageGridSize
        // Rasterising the union on a coarse grid avoids polygon math and counts
        // overlapping text boxes only once.
        var marked = [Bool](repeating: false, count: n * n)
        let cellWidth = box.width / Double(n)
        let cellHeight = box.height / Double(n)
        for text in textBoxes {
            let x0 = max(box.x, text.x)
            let x1 = min(box.x + box.width, text.x + text.width)
            let y0 = max(box.y, text.y)
            let y1 = min(box.y + box.height, text.y + text.height)
            guard x1 > x0, y1 > y0 else { continue }
            let columnStart = max(0, Int(((x0 - box.x) / cellWidth).rounded(.down)))
            let columnEnd = min(n - 1, Int(((x1 - box.x) / cellWidth).rounded(.up)) - 1)
            let rowStart = max(0, Int(((y0 - box.y) / cellHeight).rounded(.down)))
            let rowEnd = min(n - 1, Int(((y1 - box.y) / cellHeight).rounded(.up)) - 1)
            guard columnEnd >= columnStart, rowEnd >= rowStart else { continue }
            for row in rowStart...rowEnd {
                for column in columnStart...columnEnd {
                    marked[row * n + column] = true
                }
            }
        }
        return Double(marked.lazy.filter { $0 }.count) / Double(n * n)
    }

    /// Fraction of ink pixels that lie within `bandRatio` of the box edges (a ruled
    /// table cell has most of its ink on the border).
    static func perimeterInkFraction(of box: NormalizedRect, pixels: PixelMap,
                                     bandRatio: Double = 0.08, inkThreshold: Double = 0.42) -> Double {
        inkMeasurement(of: box, pixels: pixels, bandRatio: bandRatio, inkThreshold: inkThreshold).fraction
    }

    /// Ink pixel count plus the share of it sitting on the border band.
    static func inkMeasurement(of box: NormalizedRect, pixels: PixelMap,
                               bandRatio: Double = 0.08,
                               inkThreshold: Double = 0.42) -> (fraction: Double, inkPixels: Int) {
        let rect = PageCrop.pixelRect(for: box, imageWidth: pixels.width,
                                      imageHeight: pixels.height, margin: 0).integral
        let minX = max(0, Int(rect.minX))
        let minY = max(0, Int(rect.minY))
        let maxX = min(pixels.width - 1, Int(rect.maxX) - 1)
        let maxY = min(pixels.height - 1, Int(rect.maxY) - 1)
        guard maxX >= minX, maxY >= minY else { return (0, 0) }

        let widthPixels = Double(maxX - minX + 1)
        let heightPixels = Double(maxY - minY + 1)
        let band = max(1.0, bandRatio * min(widthPixels, heightPixels))

        var ink = 0
        var onBorder = 0
        for y in minY...maxY {
            for x in minX...maxX {
                guard pixels.luminance(x: x, y: y) < inkThreshold else { continue }
                ink += 1
                let distance = min(min(Double(x - minX), Double(maxX - x)),
                                   min(Double(y - minY), Double(maxY - y)))
                if distance <= band { onBorder += 1 }
            }
        }
        guard ink > 0 else { return (0, 0) }
        return (Double(onBorder) / Double(ink), ink)
    }

    /// Kinds a false ruled-box or printed-text candidate can masquerade as.
    /// Stamps, seals and `.other` are exempt: their evidence is colour or shape,
    /// not stroke geometry, and dropping them here would lose real findings.
    static func appliesTo(_ hint: SecurityElement.Kind?) -> Bool {
        switch hint {
        case nil, .handwrittenSignature, .initial: return true
        default: return false
        }
    }

    /// Returns nil when the candidate should be dropped, else the candidate.
    static func filter(_ candidate: DetectionCandidate, page: PreparedPage) -> DetectionCandidate? {
        guard appliesTo(candidate.kindHint) else { return candidate }
        if textCoverage(of: candidate.box, textBoxes: page.exclusions.textBoxes) > maximumTextCoverage {
            return nil
        }
        let ink = inkMeasurement(of: candidate.box, pixels: page.pixels)
        if ink.inkPixels >= minimumInkPixelsForPerimeterRule,
           ink.fraction > maximumPerimeterInkFraction {
            return nil
        }
        return candidate
    }
}
