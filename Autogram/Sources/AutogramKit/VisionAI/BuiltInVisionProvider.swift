import Foundation
import PDFKit
import CoreGraphics

public struct BuiltInVisionProvider: SecurityElementsProviding {
    public var providerName: String { "Built-in Vision (on-device)" }

    public var minStampDiameterRatio: Double = 0.035
    public var maxStampDiameterRatio: Double = 0.30
    public var minSignatureWidthRatio: Double = 0.08
    public var maxSignatureWidthRatio: Double = 0.62

    public init() {}

    public func detect(in document: PDFDocument, pageAnalyses: [PageAnalysis]) async -> [SecurityElement] {
        guard document.pageCount > 0 else { return [] }
        var elements: [SecurityElement] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let pixels = Self.renderPixels(page: page) else { continue }
            if let analysis = pageAnalyses.first(where: { $0.pageIndex == pageIndex }), analysis.isEmpty {
                continue
            }
            let pageElements = detectOnPage(pixels: pixels, pageIndex: pageIndex)
            elements.append(contentsOf: pageElements)
        }
        return elements
    }

    func detectOnPage(pixels: PixelMap, pageIndex: Int) -> [SecurityElement] {
        var masks = Masks(width: pixels.width, height: pixels.height)
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let (h, s, v) = pixels.hueSaturationValue(x: x, y: y)
                if s > 0.28 && v > 0.15 && v < 0.96 {
                    masks.colored[y * pixels.width + x] = true
                } else if v < 0.42 && s < 0.55 {
                    masks.dark[y * pixels.width + x] = true
                }
                masks.gray[y * pixels.width + x] = 0.299 * v
                _ = h
            }
        }

        var elements: [SecurityElement] = []
        elements.append(contentsOf: detectStamps(masks: masks, pixels: pixels, pageIndex: pageIndex))
        elements.append(contentsOf: detectSignatures(masks: masks, pixels: pixels, pageIndex: pageIndex))
        return elements
    }

    private struct Masks {
        var colored: [Bool]
        var dark: [Bool]
        var gray: [Double]

        init(width: Int, height: Int) {
            colored = [Bool](repeating: false, count: width * height)
            dark = [Bool](repeating: false, count: width * height)
            gray = [Double](repeating: 1.0, count: width * height)
        }
    }

    private func detectStamps(masks: Masks, pixels: PixelMap, pageIndex: Int) -> [SecurityElement] {
        let components = ConnectedComponents.label(mask: masks.colored,
                                                   width: pixels.width,
                                                   height: pixels.height)
        var stamps: [SecurityElement] = []

        for component in components {
            let stats = ConnectedComponents.stats(for: component, mask: masks.colored,
                                                  width: pixels.width, height: pixels.height)
            guard stats.area > 24 else { continue }

            let diameter = Double(max(stats.bboxWidth, stats.bboxHeight))
            let relativeDiameter = diameter / Double(pixels.width)
            guard relativeDiameter >= minStampDiameterRatio,
                  relativeDiameter <= maxStampDiameterRatio else { continue }

            let aspect = stats.aspectRatio
            guard aspect > 0.55 && aspect < 1.7 else { continue }

            let coverage = Self.radialCoverage(stats: stats, mask: masks.colored,
                                               width: pixels.width, height: pixels.height)
            guard coverage >= 0.45 else { continue }

            let confidence = min(0.97, 0.42 + coverage * 0.55 +
                                 (stats.fillRatio > 0.5 ? 0.04 : 0))

            let rect = normalizedRect(stats: stats, pixels: pixels)
            let element = SecurityElement(
                kind: .officialStamp,
                pageIndex: pageIndex,
                boundingBox: rect,
                confidence: confidence)
            stamps.append(element)
        }
        return stamps
    }

    static func radialCoverage(stats: ComponentStats, mask: [Bool],
                               width: Int, height: Int) -> Double {
        let cx = Double(stats.minX + stats.maxX) / 2.0
        let cy = Double(stats.minY + stats.maxY) / 2.0
        let outerRadius = Double(max(stats.bboxWidth, stats.bboxHeight)) / 2.0
        let sampleCount = 48
        var hits = 0

        for step in 0..<sampleCount {
            let angle = Double(step) / Double(sampleCount) * 2.0 * .pi
            var hit = false
            for factor in [0.62, 0.78, 0.92] {
                let radius = outerRadius * factor
                let x = Int(cx + cos(angle) * radius)
                let y = Int(cy + sin(angle) * radius)
                guard x >= 0, x < width, y >= 0, y < height else { continue }
                if mask[y * width + x] {
                    hit = true
                    break
                }
            }
            if hit { hits += 1 }
        }
        return Double(hits) / Double(sampleCount)
    }

    private func detectSignatures(masks: Masks, pixels: PixelMap, pageIndex: Int) -> [SecurityElement] {
        let components = ConnectedComponents.label(mask: masks.dark,
                                                   width: pixels.width,
                                                   height: pixels.height)
        var signatures: [SecurityElement] = []
        let pageArea = Double(pixels.width * pixels.height)

        for component in components {
            let stats = ConnectedComponents.stats(for: component, mask: masks.dark,
                                                  width: pixels.width, height: pixels.height)
            guard stats.area > 40 else { continue }

            let areaRatio = Double(stats.area) / pageArea
            guard areaRatio < 0.25 else { continue }

            if touchesEdges(stats: stats, width: pixels.width, height: pixels.height, margin: 2) {
                continue
            }

            let relativeWidth = Double(stats.bboxWidth) / Double(pixels.width)
            guard relativeWidth >= minSignatureWidthRatio,
                  relativeWidth <= maxSignatureWidthRatio else { continue }

            let elongation = Double(stats.perimeter * stats.perimeter) / (Double(stats.area) * 4.0 * .pi)
            guard elongation > 2.2 else { continue }

            var confidence = 0.35 + min(elongation / 14.0, 0.4)

            let verticalCenter = Double((stats.minY + stats.maxY)) / Double(pixels.height * 2)
            if verticalCenter > 0.55 { confidence += 0.18 }

            guard confidence >= 0.42 else { continue }

            let rect = normalizedRect(stats: stats, pixels: pixels)
            signatures.append(SecurityElement(
                kind: .handwrittenSignature,
                pageIndex: pageIndex,
                boundingBox: rect,
                confidence: min(confidence, 0.92)))
        }
        return signatures
    }

    private func touchesEdges(stats: ComponentStats, width: Int, height: Int, margin: Int) -> Bool {
        var touchedEdges = 0
        if stats.minX <= margin || stats.maxX >= width - margin - 1 { touchedEdges += 1 }
        if stats.minY <= margin || stats.maxY >= height - margin - 1 { touchedEdges += 1 }
        return touchedEdges >= 2 &&
               (Double(stats.bboxWidth) / Double(width) > 0.85 ||
                Double(stats.bboxHeight) / Double(height) > 0.85)
    }

    private func normalizedRect(stats: ComponentStats, pixels: PixelMap) -> NormalizedRect {
        NormalizedRect(
            x: Double(stats.minX) / Double(pixels.width),
            y: Double(stats.minY) / Double(pixels.height),
            width: Double(stats.bboxWidth) / Double(pixels.width),
            height: Double(stats.bboxHeight) / Double(pixels.height))
    }

    static func renderPixels(page: PDFPage, targetWidth: Int = 520) -> PixelMap? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let scale = CGFloat(targetWidth) / bounds.width
        let w = max(Int(bounds.width * scale), 8)
        let h = max(Int(bounds.height * scale), 8)

        var buffer = [UInt8](repeating: 255, count: w * h * 4)
        let ok = buffer.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(
                data: ptr.baseAddress,
                width: w, height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.scaleBy(x: 1, y: -1)
            if let ref = page.pageRef { ctx.drawPDFPage(ref) }
            return true
        }
        guard ok else { return nil }
        return PixelMap(width: w, height: h, rgba: buffer)
    }
}
