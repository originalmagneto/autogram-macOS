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

    /// Reproduces `BuiltInVisionProvider.detect` for one page, but on an already
    /// rendered page so the document is never rasterized or OCRed twice.
    func candidates(on page: PreparedPage) -> (candidates: [DetectionCandidate], passthrough: [SecurityElement]) {
        let elements = provider.detectOnPage(pixels: page.pixels, pageIndex: page.pageIndex,
                                             exclusions: page.exclusions)
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
        // Same barcode passthrough the frozen provider appends after detectOnPage.
        for barcode in page.exclusions.barcodeBoxes {
            passthrough.append(SecurityElement(
                kind: .other,
                pageIndex: page.pageIndex,
                boundingBox: barcode,
                confidence: 0.9,
                verbalDescription: "Čiarový kód / QR (notárska pripojka)",
                detectedByAI: false,
                reviewState: .pending))
        }
        return (candidates, passthrough)
    }
}
