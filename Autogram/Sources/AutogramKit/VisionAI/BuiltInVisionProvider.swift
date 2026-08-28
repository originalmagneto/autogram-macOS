import Foundation
import PDFKit
import CoreGraphics
import Vision
import AppKit

/// On-device detector combining classical CV masks with Apple Vision requests.
///
/// Vision provides two signals the color/dark masks cannot:
///  - `VNRecognizeTextRequest`: bounding boxes of text lines. Components overlapping
///    text are rejected (this is what previously misclassified text rows as signatures).
///  - `VNDetectBarcodesRequest`: QR / barcode boxes (notary certification blocks).
///    They are reported as `.other` security elements and excluded from stamp candidates.
public struct BuiltInVisionProvider: SecurityElementsProviding {
    public var providerName: String { "Built-in Vision (on-device, Apple Vision)" }

    public var minStampDiameterRatio: Double = 0.035
    public var maxStampDiameterRatio: Double = 0.30
    public var minSignatureWidthRatio: Double = 0.08
    public var maxSignatureWidthRatio: Double = 0.62

    /// Rendered page width used for analysis (px).
    public var renderTargetWidth: Int = 760

    public init() {}

    // MARK: - Public entry point

    public func detect(in document: PDFDocument, pageAnalyses: [PageAnalysis]) async -> [SecurityElement] {
        guard document.pageCount > 0 else { return [] }
        var elements: [SecurityElement] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let analysis = pageAnalyses.first(where: { $0.pageIndex == pageIndex }),
                  !analysis.isEmpty,
                  let rendered = Self.render(page: page, targetWidth: renderTargetWidth) else { continue }

            let exclusions = await Self.visionExclusionBoxes(cgImage: rendered.cgImage)
            let pageElements = detectOnPage(pixels: rendered.pixels,
                                            pageIndex: pageIndex,
                                            exclusions: exclusions)
            elements.append(contentsOf: pageElements)

            for barcode in exclusions.barcodeBoxes {
                elements.append(SecurityElement(
                    kind: .other,
                    pageIndex: pageIndex,
                    boundingBox: barcode,
                    confidence: 0.9,
                    verbalDescription: "Čiarový kód / QR (notárska pripojka)",
                    detectedByAI: false))
            }
        }
        return elements
    }

    // MARK: - Mask based detection

    func detectOnPage(pixels: PixelMap, pageIndex: Int,
                      exclusions: VisionExclusions = .empty) -> [SecurityElement] {
        var masks = Masks(width: pixels.width, height: pixels.height)
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let (h, s, v) = pixels.hueSaturationValue(x: x, y: y)
                if s > 0.18 && v > 0.15 && v < 0.96 {
                    // Lowered saturation threshold: light-blue notary stamps were
                    // previously missed at 0.28.
                    masks.colored[y * pixels.width + x] = true
                    masks.ink[y * pixels.width + x] = true
                } else if v < 0.42 && s < 0.55 {
                    masks.dark[y * pixels.width + x] = true
                    masks.ink[y * pixels.width + x] = true
                }
                _ = h
            }
        }

        var elements: [SecurityElement] = []
        let stamps = detectStamps(masks: masks, pixels: pixels, pageIndex: pageIndex,
                                  exclusions: exclusions)
        elements.append(contentsOf: stamps)

        let stampBoxes = stamps.map { $0.boundingBox }
        elements.append(contentsOf: detectSignatures(masks: masks, pixels: pixels, pageIndex: pageIndex,
                                                     exclusions: exclusions,
                                                     stampBoxes: stampBoxes))
        return elements
    }

    private struct Masks {
        var colored: [Bool]
        var dark: [Bool]
        var ink: [Bool]

        init(width: Int, height: Int) {
            colored = [Bool](repeating: false, count: width * height)
            dark = [Bool](repeating: false, count: width * height)
            ink = [Bool](repeating: false, count: width * height)
        }
    }

    private func detectStamps(masks: Masks, pixels: PixelMap, pageIndex: Int,
                              exclusions: VisionExclusions) -> [SecurityElement] {
        let components = ConnectedComponents.label(mask: masks.colored,
                                                   width: pixels.width,
                                                   height: pixels.height)
        var stamps: [SecurityElement] = []
        let pageArea = Double(pixels.width * pixels.height)

        for component in components {
            let stats = ConnectedComponents.stats(for: component, mask: masks.colored,
                                                  width: pixels.width, height: pixels.height)
            guard stats.area > 60 else { continue }

            let box = normalizedRect(stats: stats, pixels: pixels)
            guard !exclusions.overlapsTextOrBarcode(box) else { continue }

            let diameter = Double(max(stats.bboxWidth, stats.bboxHeight))
            let relativeDiameter = diameter / Double(pixels.width)
            guard relativeDiameter >= minStampDiameterRatio,
                  relativeDiameter <= maxStampDiameterRatio else { continue }

            let aspect = stats.aspectRatio
            guard aspect > 0.55 && aspect < 1.7 else { continue }

            let fillRatio = Double(stats.area) /
                Double(max(stats.bboxWidth, 1) * max(stats.bboxHeight, 1))
            guard fillRatio > 0.05 && fillRatio < 0.85 else { continue }
            guard Double(stats.area) / pageArea > 0.0002 else { continue }

            let coverage = Self.radialCoverage(stats: stats, mask: masks.colored,
                                               width: pixels.width, height: pixels.height)
            guard coverage >= 0.45 else { continue }

            let confidence = min(0.97, 0.45 + coverage * 0.5 +
                                 (stats.fillRatio > 0.5 ? 0.04 : 0))
            stamps.append(SecurityElement(
                kind: .officialStamp,
                pageIndex: pageIndex,
                boundingBox: box,
                confidence: confidence))
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

    private func detectSignatures(masks: Masks, pixels: PixelMap, pageIndex: Int,
                                  exclusions: VisionExclusions,
                                  stampBoxes: [NormalizedRect]) -> [SecurityElement] {
        // Ink mask (dark AND colored strokes): blue ballpoint signatures are colored.
        let components = ConnectedComponents.label(mask: masks.ink,
                                                   width: pixels.width,
                                                   height: pixels.height)
        var signatures: [SecurityElement] = []
        let pageArea = Double(pixels.width * pixels.height)

        for component in components {
            let stats = ConnectedComponents.stats(for: component, mask: masks.ink,
                                                  width: pixels.width, height: pixels.height)
            guard stats.area > 120 else { continue }

            let areaRatio = Double(stats.area) / pageArea
            guard areaRatio < 0.25 else { continue }

            if touchesEdges(stats: stats, width: pixels.width, height: pixels.height, margin: 2) {
                continue
            }

            let box = normalizedRect(stats: stats, pixels: pixels)
            // Text lines (from Vision OCR) and stamp/barcode regions are not signatures.
            guard !exclusions.overlapsTextOrBarcode(box, threshold: 0.3) else { continue }
            guard !stampBoxes.contains(where: { Self.overlapFraction(box, $0) > 0.5 }) else { continue }

            let relativeWidth = Double(stats.bboxWidth) / Double(pixels.width)
            guard relativeWidth >= minSignatureWidthRatio,
                  relativeWidth <= maxSignatureWidthRatio else { continue }

            // Text lines: high bbox fill ratio and extreme width/height ratio.
            let fillRatio = Double(stats.area) /
                Double(max(stats.bboxWidth, 1) * max(stats.bboxHeight, 1))
            guard fillRatio < 0.55 else { continue }
            guard stats.aspectRatio < 18 else { continue }

            let elongation = Double(stats.perimeter * stats.perimeter) / (Double(stats.area) * 4.0 * .pi)
            guard elongation > 2.0 else { continue }

            var confidence = 0.4 + min(elongation / 14.0, 0.35)
            // Rows are top-down: larger y = lower on the page, where
            // handwritten signatures predominantly sit.
            let verticalCenter = Double((stats.minY + stats.maxY)) / Double(pixels.height * 2)
            if verticalCenter > 0.55 { confidence += 0.18 }

            guard confidence >= 0.45 else { continue }

            signatures.append(SecurityElement(
                kind: .handwrittenSignature,
                pageIndex: pageIndex,
                boundingBox: box,
                confidence: min(confidence, 0.92)))
        }
        return signatures
    }

    static func overlapFraction(_ a: NormalizedRect, _ b: NormalizedRect) -> Double {
        let interW = max(0, min(a.x + a.width, b.x + b.width) - max(a.x, b.x))
        let interH = max(0, min(a.y + a.height, b.y + b.height) - max(a.y, b.y))
        let inter = interW * interH
        let aArea = max(a.width * a.height, 0.000001)
        return inter / aArea
    }

    private func touchesEdges(stats: ComponentStats, width: Int, height: Int, margin: Int) -> Bool {
        var touchedEdges = 0
        if stats.minX <= margin { touchedEdges += 1 }
        if stats.maxX >= width - margin { touchedEdges += 1 }
        if stats.minY <= margin { touchedEdges += 1 }
        if stats.maxY >= height - margin { touchedEdges += 1 }
        return touchedEdges > 0
    }


    private func normalizedRect(stats: ComponentStats, pixels: PixelMap) -> NormalizedRect {
        // PixelMap rows are TOP-origin for CGImage-derived bitmaps; convert to
        // the domain convention (normalized y=0 = page BOTTOM).
        NormalizedRect(
            x: Double(stats.minX) / Double(pixels.width),
            y: 1 - (Double(stats.minY) + Double(stats.bboxHeight)) / Double(pixels.height),
            width: Double(stats.bboxWidth) / Double(pixels.width),
            height: Double(stats.bboxHeight) / Double(pixels.height))
    }
    // MARK: - Rendering

    public struct RenderedPage {
        public let pixels: PixelMap
        public let cgImage: CGImage
    }

    public static func render(page: PDFPage, targetWidth: Int = 520) -> RenderedPage? {
        // PDFKit's thumbnail honors /Rotate, so the rendered bitmap matches the
        // page as displayed (a landscape diploma with portrait mediaBox renders
        // landscape, not squashed).
        let mediaBox = page.bounds(for: .mediaBox)
        guard mediaBox.width > 1, mediaBox.height > 1 else { return nil }
        let rotated = (page.rotation == 90 || page.rotation == 270)
        let displayWidth = rotated ? mediaBox.height : mediaBox.width
        let displayHeight = rotated ? mediaBox.width : mediaBox.height
        let scale = CGFloat(targetWidth) / max(displayWidth, 1)
        let pxW = max(Int(displayWidth * scale), 8)
        let pxH = max(Int(displayHeight * scale), 8)

        let nsImage = page.thumbnail(of: CGSize(width: pxW, height: pxH), for: .mediaBox)
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        guard let pixels = PixelMap(cgImage: cgImage, targetWidth: targetWidth) else { return nil }
        return RenderedPage(pixels: pixels, cgImage: cgImage)
    }


    // MARK: - Apple Vision

    struct VisionExclusions {
        var textBoxes: [NormalizedRect] = []
        var barcodeBoxes: [NormalizedRect] = []

        static let empty = VisionExclusions()

        func overlapsTextOrBarcode(_ box: NormalizedRect, threshold: Double = 0.35) -> Bool {
            textBoxes.contains { BuiltInVisionProvider.overlapFraction(box, $0) > threshold } ||
            barcodeBoxes.contains { BuiltInVisionProvider.overlapFraction(box, $0) > threshold }
        }
    }

    /// Runs Apple Vision text recognition and barcode detection on the rendered page.
    /// Vision uses a bottom-left normalized origin, matching our component convention.
    static func visionExclusionBoxes(cgImage: CGImage) async -> VisionExclusions {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var exclusions = VisionExclusions()

                let textRequest = VNRecognizeTextRequest { request, _ in
                    guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
                    exclusions.textBoxes = observations.compactMap { observation in
                        // Only confident real text excludes regions; a squiggly
                        // signature can OCR as garbage with low confidence.
                        guard let candidate = observation.topCandidates(1).first,
                              candidate.confidence > 0.35,
                              candidate.string.contains(where: { $0.isLetter || $0.isNumber })
                        else { return nil }
                        return visionBox(observation.boundingBox)
                    }
                }
                textRequest.recognitionLevel = .fast
                textRequest.usesLanguageCorrection = false

                let barcodeRequest = VNDetectBarcodesRequest { request, _ in
                    guard let observations = request.results as? [VNBarcodeObservation] else { return }
                    exclusions.barcodeBoxes = observations.compactMap {
                        visionBox($0.boundingBox)
                    }
                }

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([textRequest, barcodeRequest])
                } catch {
                    // Vision failure must not break detection: fall back to masks only.
                    NSLog("Vision exclusion requests failed: \(error.localizedDescription)")
                }
                continuation.resume(returning: exclusions)
            }
        }
    }

    private static func visionBox(_ boundingBox: CGRect) -> NormalizedRect {
        // The CGImage is now correctly oriented (PDFKit thumbnail), so Vision's
        // bottom-left-origin box maps directly onto our bottom-origin convention.
        NormalizedRect(
            x: Double(max(0, boundingBox.minX)),
            y: Double(max(0, min(1 - boundingBox.height, 1))),
            width: Double(min(1, boundingBox.width)),
            height: Double(min(1, boundingBox.height)))
    }

    /// Compatibility wrapper for LLM vision providers expecting a PixelMap.
    static func renderPixels(page: PDFPage, targetWidth: Int = 520) -> PixelMap? {
        render(page: page, targetWidth: targetWidth)?.pixels
    }
}
