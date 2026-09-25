// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import CoreGraphics
import Foundation
import ImageIO

public enum LearnedModelScorerError: Error, Equatable {
    case unreadableImage(String)
}

/// Scores a predictor (a compiled model in production, a stub in tests) on
/// one dataset partition through `DetectionEvaluator` (IoU 0.4 default).
/// Shared by the promotion flow and, by pattern, the `vision-train` spike.
public enum LearnedModelScorer {
    public struct PartitionScore: Sendable, Equatable {
        public var pages: Int
        public var predictedBoxes: Int
        public var perLabel: [String: LabelMetrics]
    }

    public static func score(predict: @Sendable @escaping (CGImage) throws -> [LearnedPrediction],
                             imageNames: [String], folder: URL,
                             truth: [CreateMLImageAnnotation],
                             iouThreshold: Double = 0.4) async throws -> PartitionScore {
        let source = LearnedCandidateSource(modelID: "scorer", predict: predict)
        var predicted: [SecurityElement] = []
        var sizes: [String: CGSize] = [:]
        for (index, name) in imageNames.enumerated() {
            try Task.checkCancellation()
            guard let imageSource = CGImageSourceCreateWithURL(folder.appendingPathComponent(name) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw LearnedModelScorerError.unreadableImage(name)
            }
            sizes[name] = CGSize(width: image.width, height: image.height)
            for candidate in try await source.candidates(pageImage: image, pageIndex: index) {
                guard let kind = candidate.kindHint else { continue }
                predicted.append(SecurityElement(kind: kind, pageIndex: index,
                                                 boundingBox: candidate.box,
                                                 confidence: candidate.hintConfidence ?? 0,
                                                 detectionSource: "learned(scorer)"))
            }
        }
        let perLabel = DetectionEvaluator.score(predicted: predicted,
                                                truth: VisionTrainSplit.annotations(for: imageNames, from: truth),
                                                imageSizes: sizes, pageOrder: imageNames,
                                                iouThreshold: iouThreshold)
        return PartitionScore(pages: imageNames.count, predictedBoxes: predicted.count, perLabel: perLabel)
    }
}
