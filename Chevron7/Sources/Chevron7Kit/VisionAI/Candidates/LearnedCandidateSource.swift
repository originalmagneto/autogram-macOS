// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import CoreGraphics
import CoreML
import Foundation
import Vision

/// One box from the trained object detector, in the app's bottom-origin
/// normalized convention (Vision's `boundingBox` already uses it).
public struct LearnedPrediction: Sendable, Equatable {
    public var box: NormalizedRect
    public var label: String
    public var confidence: Double

    public init(box: NormalizedRect, label: String, confidence: Double) {
        self.box = box; self.label = label; self.confidence = confidence
    }
}

/// Candidate source backed by a model the app trained on the reviewer's own
/// page reviews. It only proposes: every box still flows through
/// `CandidateMerger`, `CandidateQualityFilter` and `TwoStageClassifier`,
/// so bank rejections (including exact-match ones) still apply.
///
/// The `predict` closure is injected so tests can feed canned predictions
/// without a model file; production uses `coreMLPredictor(model:)`.
public struct LearnedCandidateSource: CandidateSourcing {
    public var source: CandidateSource { .learned }
    /// SHA-256 of the active `Detector.mlmodel`, for the audit identifier.
    public var modelID: String
    public var predict: @Sendable (CGImage) throws -> [LearnedPrediction]

    public init(modelID: String, predict: @Sendable @escaping (CGImage) throws -> [LearnedPrediction]) {
        self.modelID = modelID; self.predict = predict
    }

    public func candidates(pageImage: CGImage, pageIndex: Int) async throws -> [DetectionCandidate] {
        try predict(pageImage).compactMap { prediction in
            guard let kind = VisionTrainSplit.kind(forTrainingLabel: prediction.label) else { return nil }
            return DetectionCandidate(pageIndex: pageIndex, box: prediction.box,
                                      sources: [.learned],
                                      kindHint: kind, hintConfidence: prediction.confidence)
        }
    }

/// Shared across the concurrent page tasks. Each call builds its own
/// `VNCoreMLRequest` and handler; inference through one model is read-only.
private final class SharedModel: @unchecked Sendable {
    let model: VNCoreMLModel
    init(_ model: VNCoreMLModel) { self.model = model }
}

    /// Production predictor: one `VNCoreMLRequest` per call (requests are not
    /// shared across the concurrent page tasks).
    public static func coreMLPredictor(model: VNCoreMLModel) -> @Sendable (CGImage) throws -> [LearnedPrediction] {
        let shared = SharedModel(model)
        return { pageImage in
            let request = VNCoreMLRequest(model: shared.model)
            try VNImageRequestHandler(cgImage: pageImage).perform([request])
            return (request.results as? [VNRecognizedObjectObservation] ?? []).compactMap { observation in
                guard let top = observation.labels.first else { return nil }
                let box = observation.boundingBox
                return LearnedPrediction(
                    box: NormalizedRect(x: box.minX, y: box.minY, width: box.width, height: box.height),
                    label: top.identifier, confidence: Double(top.confidence))
            }
        }
    }
}

public enum LearnedModelLoader {
    /// Loads a compiled `.mlmodelc` directly, or compiles a `.mlmodel` to a
    /// temporary directory first.
    public static func load(at url: URL) throws -> VNCoreMLModel {
        let compiled: URL
        if url.pathExtension == "mlmodelc" {
            compiled = url
        } else {
            compiled = try MLModel.compileModel(at: url)
        }
        return try VNCoreMLModel(for: MLModel(contentsOf: compiled))
    }
}
