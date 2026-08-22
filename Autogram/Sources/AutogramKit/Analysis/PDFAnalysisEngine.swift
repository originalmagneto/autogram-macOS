import Foundation
import PDFKit
import CoreGraphics

public struct PDFAnalysisEngine: Sendable {
    public var blankInkCoverageThreshold: Double = 0.006
    public var blankAbsolutePixelThreshold: Int = 50

    public init(blankInkCoverageThreshold: Double = 0.006,
                blankAbsolutePixelThreshold: Int = 50) {
        self.blankInkCoverageThreshold = blankInkCoverageThreshold
        self.blankAbsolutePixelThreshold = blankAbsolutePixelThreshold
    }

    public func analyze(document: PDFDocument) -> DocumentAnalysis {
        let pageCount = document.pageCount
        var analyses: [PageAnalysis] = []
        analyses.reserveCapacity(pageCount)

        for index in 0..<pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let sizeClass = PaperClassifier.classify(widthPt: bounds.width, heightPt: bounds.height)
            let coverage = Self.inkCoverage(of: page)
            let pixels = Self.inkPixelCount(of: page)
            let isEmpty = pixels < blankAbsolutePixelThreshold
            let analysis = PageAnalysis(
                pageIndex: index,
                widthPt: bounds.width,
                heightPt: bounds.height,
                sizeClass: sizeClass,
                inkCoverage: coverage,
                isEmpty: isEmpty)
            analyses.append(analysis)
        }

        let nonEmpty = analyses.filter { !$0.isEmpty }.count
        let sheets = Int(ceil(Double(nonEmpty) / 2.0))
        let title = Self.suggestTitle(in: document)

        return DocumentAnalysis(
            totalPages: analyses.count,
            nonEmptyPages: nonEmpty,
            estimatedSheetsDuplex: max(sheets, analyses.isEmpty ? 0 : 1),
            pageAnalyses: analyses,
            securityElements: [],
            suggestedTitle: title,
            analyzedAt: Date())
    }

    public static func inkCoverage(of page: PDFPage, targetWidth: CGFloat = 480) -> Double {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return 0 }
        let scale = targetWidth / bounds.width
        let width = max(Int(targetWidth), 1)
        let height = max(Int(bounds.height * scale), 1)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: max(width, 1),
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }

        context.setFillColor(gray: 1.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        if let ref = page.pageRef {
            context.drawPDFPage(ref)
        }
        context.restoreGState()

        return Double(inkCount(buffer: context.data, capacity: width * height)) / Double(width * height)
    }

    static func inkPixelCount(of page: PDFPage, targetWidth: CGFloat = 480) -> Int {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0 else { return 0 }
        let scale = targetWidth / bounds.width
        let width = max(Int(targetWidth), 1)
        let height = max(Int(bounds.height * scale), 1)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: max(width, 1),
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }

        context.setFillColor(gray: 1.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        if let ref = page.pageRef {
            context.drawPDFPage(ref)
        }
        context.restoreGState()

        return inkCount(buffer: context.data, capacity: width * height)
    }

    private static func inkCount(buffer: UnsafeMutableRawPointer?, capacity: Int) -> Int {
        guard let data = buffer, capacity > 0 else { return 0 }
        let pointer = data.bindMemory(to: UInt8.self, capacity: capacity)
        var count = 0
        for i in 0..<capacity where pointer[i] < 235 {
            count += 1
        }
        return count
    }

    public static func suggestTitle(in document: PDFDocument, maxLength: Int = 90) -> String? {
        guard document.pageCount > 0,
              let firstPage = document.page(at: 0),
              let text = firstPage.string else { return nil }

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 3 }

        for line in lines.prefix(8) {
            if looksLikeTitle(line) {
                return String(line.prefix(maxLength))
            }
        }
        return lines.first.map { String($0.prefix(maxLength)) }
    }

    private static func looksLikeTitle(_ line: String) -> Bool {
        let lowercasedNoise = ["strana", "dátum", "datum", "číslo", "cislo", "www.", "http", "tel:", "email"]
        let lowered = line.lowercased()
        if lowercasedNoise.contains(where: { lowered.contains($0) }) { return false }
        return line.count >= 4 && line.count <= 120
    }
}

public enum PaperClassifier {
    public static func classify(widthPt: Double, heightPt: Double, tolerancePt: Double = 14) -> PaperClassification {
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= tolerancePt }

        let portraitSizes: [(Double, Double, PaperClassification)] = [
            (595, 842, .a4Portrait),
            (842, 1191, .a3Portrait),
            (612, 792, .letterPortrait)
        ]

        for (w, h, classification) in portraitSizes where near(widthPt, w) && near(heightPt, h) {
            return classification
        }
        for (w, h, classification) in portraitSizes where near(widthPt, h) && near(heightPt, w) {
            switch classification {
            case .a4Portrait: return .a4Landscape
            case .a3Portrait: return .a3Landscape
            case .letterPortrait: return .letterLandscape
            default: break
            }
        }
        return .unknown
    }
}
