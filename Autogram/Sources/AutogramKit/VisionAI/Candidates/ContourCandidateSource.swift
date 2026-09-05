import Foundation
import CoreGraphics
import Vision

/// Finds candidate regions using Vision's contour detector. Useful for
/// catching stamp rings and boxed elements the color/dark heuristics miss.
///
/// `contrastAdjustment` was tuned to 1.5 against `TestPDFBuilder.typicalContractPDF()`:
/// the drawn stamp ring is a thin dark-on-light stroke that at the default
/// value (2.0) was not consistently returned as a top-level contour.
public struct ContourCandidateSource: CandidateSourcing {
    public var source: CandidateSource { .contour }
    public var contrastAdjustment: Float = 1.5
    public var maximumImageDimension = 760

    public init() {}

    public func candidates(pageImage: CGImage, pageIndex: Int) async throws -> [DetectionCandidate] {
        var request = DetectContoursRequest()
        request.contrastAdjustment = contrastAdjustment
        request.detectsDarkOnLight = true
        request.maximumImageDimension = maximumImageDimension
        let observation = try await request.perform(on: pageImage)
        let size = CGSize(width: pageImage.width, height: pageImage.height)
        var result: [DetectionCandidate] = []
        for contour in observation.topLevelContours {
            // normalizedPath is lower-left origin in 0...1; boundingBoxOfPath gives a
            // normalized rect we convert to pixels (top-origin) and back to the app type.
            let normalized = contour.normalizedPath.boundingBoxOfPath
            guard normalized.width > 0, normalized.height > 0 else { continue }
            let pixel = CGRect(x: normalized.minX * size.width,
                               y: (1 - normalized.maxY) * size.height,
                               width: normalized.width * size.width,
                               height: normalized.height * size.height)
            let box = PageCrop.normalizedRect(fromPixelRect: pixel,
                                              imageWidth: pageImage.width, imageHeight: pageImage.height)
            result.append(DetectionCandidate(pageIndex: pageIndex, box: box, sources: [.contour]))
        }
        return result
    }
}
