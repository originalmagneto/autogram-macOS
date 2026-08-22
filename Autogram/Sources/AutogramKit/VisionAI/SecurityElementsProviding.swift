import Foundation
import PDFKit

public protocol SecurityElementsProviding: Sendable {
    var providerName: String { get }
    func detect(in document: PDFDocument, pageAnalyses: [PageAnalysis]) async -> [SecurityElement]
}

public struct DetectionPipeline: SecurityElementsProviding {
    public let builtin: BuiltInVisionProvider
    public let llmProvider: (any SecurityElementsProviding)?

    public init(builtin: BuiltInVisionProvider = BuiltInVisionProvider(),
                llmProvider: (any SecurityElementsProviding)? = nil) {
        self.builtin = builtin
        self.llmProvider = llmProvider
    }

    public var providerName: String { "DetectionPipeline" }

    public func detect(in document: PDFDocument, pageAnalyses: [PageAnalysis]) async -> [SecurityElement] {
        var elements = await builtin.detect(in: document, pageAnalyses: pageAnalyses)
        if let llm = llmProvider {
            let llmElements = await llm.detect(in: document, pageAnalyses: pageAnalyses)
            elements = SecurityElementMerger.merge(primary: elements, secondary: llmElements)
        }
        return elements.sorted {
            ($0.pageIndex, $0.boundingBox.y) < ($1.pageIndex, $1.boundingBox.y)
        }
    }
}

public enum SecurityElementMerger {
    public static func merge(primary: [SecurityElement], secondary: [SecurityElement]) -> [SecurityElement] {
        guard !secondary.isEmpty else { return primary }
        var result = primary

        for candidate in secondary {
            let duplicate = result.contains { existing in
                existing.pageIndex == candidate.pageIndex &&
                existing.kind == candidate.kind &&
                iou(existing.boundingBox, candidate.boundingBox) > 0.4
            }
            if !duplicate { result.append(candidate) }
        }
        return result
    }

    public static func iou(_ a: NormalizedRect, _ b: NormalizedRect) -> Double {
        let x1 = max(a.x, b.x)
        let y1 = max(a.y, b.y)
        let x2 = min(a.x + a.width, b.x + b.width)
        let y2 = min(a.y + a.height, b.y + b.height)
        guard x2 > x1, y2 > y1 else { return 0 }
        let intersection = (x2 - x1) * (y2 - y1)
        let union = a.width * a.height + b.width * b.height - intersection
        return union <= 0 ? 0 : intersection / union
    }
}
