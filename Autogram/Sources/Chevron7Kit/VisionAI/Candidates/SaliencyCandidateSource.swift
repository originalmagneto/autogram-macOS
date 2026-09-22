import Foundation
import CoreGraphics
import Vision

/// Finds candidate regions using Vision's objectness-based saliency request.
/// Catches visually distinct regions (stamps, signatures, embossed seals)
/// that the built-in heuristics or contour detection might miss.
public struct SaliencyCandidateSource: CandidateSourcing {
    public var source: CandidateSource { .saliency }
    public init() {}

    public func candidates(pageImage: CGImage, pageIndex: Int) async throws -> [DetectionCandidate] {
        let request = GenerateObjectnessBasedSaliencyImageRequest()
        let observation = try await request.perform(on: pageImage)
        let size = CGSize(width: pageImage.width, height: pageImage.height)
        return observation.salientObjects.compactMap { object in
            let pixel = object.boundingBox.toImageCoordinates(size, origin: .upperLeft)
            guard pixel.width > 0, pixel.height > 0 else { return nil }
            let box = PageCrop.normalizedRect(fromPixelRect: pixel,
                                              imageWidth: pageImage.width, imageHeight: pageImage.height)
            return DetectionCandidate(pageIndex: pageIndex, box: box, sources: [.saliency])
        }
    }
}
