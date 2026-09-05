import Foundation
import CoreGraphics
import PDFKit

public protocol CandidateSourcing: Sendable {
    var source: CandidateSource { get }
    func candidates(pageImage: CGImage, pageIndex: Int) async throws -> [DetectionCandidate]
}

/// Wraps the frozen heuristic detector. Its elements become hinted candidates;
/// barcode/QR elements are already reliable and pass through unchanged.
public struct BuiltInCandidateSource: Sendable {
    public let provider: BuiltInVisionProvider
    public init(provider: BuiltInVisionProvider = BuiltInVisionProvider()) { self.provider = provider }

    public func candidates(in document: PDFDocument,
                           pageAnalyses: [PageAnalysis]) async -> (candidates: [DetectionCandidate], passthrough: [SecurityElement]) {
        let elements = await provider.detect(in: document, pageAnalyses: pageAnalyses)
        var candidates: [DetectionCandidate] = []
        var passthrough: [SecurityElement] = []
        for element in elements {
            if element.kind == .other {
                passthrough.append(element)
            } else {
                candidates.append(DetectionCandidate(pageIndex: element.pageIndex, box: element.boundingBox,
                                                     sources: [.builtIn], kindHint: element.kind,
                                                     hintConfidence: element.confidence))
            }
        }
        return (candidates, passthrough)
    }
}
