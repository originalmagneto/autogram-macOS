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

    /// Small local bridge used to join anti-aliased or broken strokes belonging
    /// to one printed security element. The bridge is applied only while
    /// grouping components. Bounds and shape statistics still use the original
    /// mask, so the overlay does not grow into the surrounding page.
    public var stampComponentGapRatio: Double = 0.012
    public var signatureComponentGapRatio: Double = 0.018

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
                    detectedByAI: false,
                    reviewState: .pending))
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
                } else if v < 0.65 && s < 0.55 {
                    masks.dark[y * pixels.width + x] = true
                    // Keep the original ink threshold for signature detection.
                    // The broader dark mask is used only for conservative relief
                    // candidates and must not merge ordinary printed text.
                    if v < 0.42 {
                        masks.ink[y * pixels.width + x] = true
                    }
                }
                _ = h
            }
        }

        var elements: [SecurityElement] = []
        let stamps = detectStamps(masks: masks, pixels: pixels, pageIndex: pageIndex,
                                  exclusions: exclusions)
        elements.append(contentsOf: stamps)

        let stampBoxes = stamps.map { $0.boundingBox }
        elements.append(contentsOf: detectEmbossedSeals(masks: masks, pixels: pixels,
                                                         pageIndex: pageIndex,
                                                         exclusions: exclusions,
                                                         stampBoxes: stampBoxes))
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
        let bridgeRadius = componentBridgeRadius(ratio: stampComponentGapRatio,
                                                  pixels: pixels,
                                                  minimum: 2,
                                                  maximum: 8)
        let components = groupedComponents(mask: masks.colored,
                                           width: pixels.width,
                                           height: pixels.height,
                                           bridgeRadius: bridgeRadius)
        var stamps: [SecurityElement] = []
        let pageArea = Double(pixels.width * pixels.height)

        for component in components {
            let stats = ConnectedComponents.stats(for: component, mask: masks.colored,
                                                  width: pixels.width, height: pixels.height)
            guard stats.area > 60 else { continue }

            let box = normalizedRect(stats: stats, pixels: pixels, padding: 2)
            // Official stamps commonly contain text around the ring. OCR must
            // not reject the enclosing circular element. Barcodes remain a
            // hard exclusion because they are handled separately as `.other`.
            guard !exclusions.barcodeBoxes.contains(where: {
                Self.overlapFraction(box, $0) > 0.35
            }) else { continue }

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

    /// Detects low-saturation circular relief marks that do not have enough
    /// colour to be classified as an official stamp. This is intentionally a
    /// conservative candidate pass: text-like and elongated components are
    /// rejected, and the advocate can still confirm or remove the result.
    private func detectEmbossedSeals(masks: Masks, pixels: PixelMap, pageIndex: Int,
                                     exclusions: VisionExclusions,
                                     stampBoxes: [NormalizedRect]) -> [SecurityElement] {
        let reliefMask = dilated(masks.dark,
                                 width: pixels.width,
                                 height: pixels.height,
                                 radius: 1)
        let bridgeRadius = componentBridgeRadius(ratio: stampComponentGapRatio,
                                                  pixels: pixels,
                                                  minimum: 2,
                                                  maximum: 8)
        let components = groupedComponents(mask: reliefMask,
                                           width: pixels.width,
                                           height: pixels.height,
                                           bridgeRadius: bridgeRadius)
        var seals: [SecurityElement] = []
        let pageArea = Double(pixels.width * pixels.height)

        for component in components {
            let stats = ConnectedComponents.stats(for: component, mask: reliefMask,
                                                  width: pixels.width, height: pixels.height)
            guard stats.area > 500 else { continue }
            // A relief candidate must have a substantial connected contour,
            // not a small glyph or a line of printed text.
            guard stats.perimeter >= 180 else { continue }
            let diameter = Double(max(stats.bboxWidth, stats.bboxHeight))
            let relativeDiameter = diameter / Double(pixels.width)
            guard relativeDiameter >= minStampDiameterRatio,
                  relativeDiameter <= maxStampDiameterRatio,
                  stats.aspectRatio > 0.70,
                  stats.aspectRatio < 1.65 else { continue }

            let fillRatio = Double(stats.area) /
                Double(max(stats.bboxWidth, 1) * max(stats.bboxHeight, 1))
            guard fillRatio > 0.25, fillRatio < 0.70,
                  Double(stats.area) / pageArea > 0.00025 else { continue }

            let box = normalizedRect(stats: stats, pixels: pixels, padding: 2)
            // A seal can contain engraved/printed lettering just like an
            // official stamp. Only barcode overlap is disqualifying here.
            guard !exclusions.barcodeBoxes.contains(where: {
                      Self.overlapFraction(box, $0) > 0.25
                  }),
                  !stampBoxes.contains(where: { Self.overlapFraction(box, $0) > 0.5 }) else { continue }

            let coverage = Self.radialCoverage(stats: stats, mask: reliefMask,
                                               width: pixels.width, height: pixels.height)
            guard coverage >= 0.25 else { continue }

            seals.append(SecurityElement(
                kind: .embossedSeal,
                pageIndex: pageIndex,
                boundingBox: box,
                confidence: min(0.82, 0.42 + coverage * 0.35),
                verbalDescription: "Reliéfna slepotlač",
                detectedByAI: true))
        }
        return seals
    }

    private func detectSignatures(masks: Masks, pixels: PixelMap, pageIndex: Int,
                                  exclusions: VisionExclusions,
                                  stampBoxes: [NormalizedRect]) -> [SecurityElement] {
        // Ink mask (dark AND colored strokes): blue ballpoint signatures are colored.
        let signatureMask = dilated(masks.ink,
                                    width: pixels.width,
                                    height: pixels.height,
                                    radius: 1)
        let bridgeRadius = componentBridgeRadius(ratio: signatureComponentGapRatio,
                                                  pixels: pixels,
                                                  minimum: 4,
                                                  maximum: 14)
        let components = groupedComponents(mask: signatureMask,
                                           width: pixels.width,
                                           height: pixels.height,
                                           bridgeRadius: bridgeRadius)
        var signatures: [SecurityElement] = []
        let pageArea = Double(pixels.width * pixels.height)

        for component in components {
            let stats = ConnectedComponents.stats(for: component, mask: signatureMask,
                                                  width: pixels.width, height: pixels.height)
            guard stats.area > 120 else { continue }

            let areaRatio = Double(stats.area) / pageArea
            guard areaRatio < 0.25 else { continue }

            if touchesEdges(stats: stats, width: pixels.width, height: pixels.height, margin: 2) {
                continue
            }

            let box = normalizedRect(stats: stats, pixels: pixels, padding: 2)
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

    private func componentBridgeRadius(ratio: Double,
                                       pixels: PixelMap,
                                       minimum: Int,
                                       maximum: Int) -> Int {
        let scaled = Int((Double(pixels.width) * max(ratio, 0)).rounded())
        return min(max(scaled, minimum), maximum)
    }

    /// Groups nearby connected components without changing the geometry used
    /// for scoring. This is important for scanned handwriting: anti-aliasing,
    /// paper noise, and compression frequently leave separate pieces of one
    /// signature stroke. The bridge mask is used only to discover the group;
    /// the returned points are always pixels from the original mask.
    private func groupedComponents(mask: [Bool], width: Int, height: Int,
                                   bridgeRadius: Int) -> [[(x: Int, y: Int)]] {
        guard bridgeRadius > 0 else {
            return ConnectedComponents.label(mask: mask, width: width, height: height)
        }

        let bridged = dilated(mask, width: width, height: height, radius: bridgeRadius)
        let bridgeComponents = ConnectedComponents.label(mask: bridged,
                                                          width: width,
                                                          height: height)
        guard !bridgeComponents.isEmpty else { return [] }

        var groupByPixel = [Int](repeating: -1, count: width * height)
        for (groupIndex, component) in bridgeComponents.enumerated() {
            for point in component {
                groupByPixel[point.y * width + point.x] = groupIndex
            }
        }

        var groups = bridgeComponents.map { _ in [(x: Int, y: Int)]() }
        for y in 0..<height {
            for x in 0..<width where mask[y * width + x] {
                let groupIndex = groupByPixel[y * width + x]
                guard groupIndex >= 0 else { continue }
                groups[groupIndex].append((x: x, y: y))
            }
        }
        return groups.filter { !$0.isEmpty }
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

    private func dilated(_ mask: [Bool], width: Int, height: Int, radius: Int) -> [Bool] {
        guard radius > 0 else { return mask }
        var result = mask
        for y in 0..<height {
            for x in 0..<width where mask[y * width + x] {
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        guard abs(dx) + abs(dy) <= radius else { continue }
                        let nx = x + dx
                        let ny = y + dy
                        if nx >= 0, nx < width, ny >= 0, ny < height {
                            result[ny * width + nx] = true
                        }
                    }
                }
            }
        }
        return result
    }


    private func normalizedRect(stats: ComponentStats, pixels: PixelMap,
                                padding: Int = 0) -> NormalizedRect {
        // PixelMap rows are TOP-origin for CGImage-derived bitmaps; convert to
        // the domain convention (normalized y=0 = page BOTTOM).
        let minX = max(stats.minX - padding, 0)
        let maxX = min(stats.maxX + padding, pixels.width - 1)
        let minY = max(stats.minY - padding, 0)
        let maxY = min(stats.maxY + padding, pixels.height - 1)
        return NormalizedRect(
            x: Double(minX) / Double(pixels.width),
            y: 1 - Double(maxY + 1) / Double(pixels.height),
            width: Double(maxX - minX + 1) / Double(pixels.width),
            height: Double(maxY - minY + 1) / Double(pixels.height))
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
            y: Double(max(0, min(boundingBox.minY, 1))),
            width: Double(min(1, boundingBox.width)),
            height: Double(min(1, boundingBox.height)))
    }

    /// Compatibility wrapper for LLM vision providers expecting a PixelMap.
    static func renderPixels(page: PDFPage, targetWidth: Int = 520) -> PixelMap? {
        render(page: page, targetWidth: targetWidth)?.pixels
    }
}
