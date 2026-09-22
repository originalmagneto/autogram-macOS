import Foundation
import CoreGraphics
import Vision

/// Second OCR pass at the accurate recognition level. The frozen heuristic's own
/// pass uses the fast level, which on real scans misses most printed lines, so
/// bold text blocks survive as "signatures". The boxes found here are merged into
/// the page exclusions and therefore reach the frozen `detectOnPage` as well.
enum AccurateTextExclusions {
    static let minimumConfidence: Float = 0.3

    static func textBoxes(in image: CGImage) async -> [NormalizedRect] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        guard let observations = try? await request.perform(on: image) else { return [] }
        let size = CGSize(width: image.width, height: image.height)
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= minimumConfidence,
                  candidate.string.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
            let pixel = observation.boundingBox.toImageCoordinates(size, origin: .upperLeft)
            return PageCrop.normalizedRect(fromPixelRect: pixel, imageWidth: image.width, imageHeight: image.height)
        }
    }

    /// Unions the accurate boxes into the fast-pass exclusions.
    static func merged(into exclusions: BuiltInVisionProvider.VisionExclusions,
                       accurate: [NormalizedRect]) -> BuiltInVisionProvider.VisionExclusions {
        var result = exclusions
        for box in accurate where !result.textBoxes.contains(where: { SecurityElementMerger.iou($0, box) > 0.8 }) {
            result.textBoxes.append(box)
        }
        return result
    }
}
