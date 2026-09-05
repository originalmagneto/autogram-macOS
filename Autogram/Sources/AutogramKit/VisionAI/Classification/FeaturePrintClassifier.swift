import Foundation
import CoreGraphics

public struct FeaturePrintClassifier: ElementClassifying {
    /// Live bank, read on every classification. Nil for a snapshotted classifier.
    public let bank: ExampleBank?
    /// Fixed examples captured by `snapshot()`. Nil for a bank-backed classifier.
    public let examples: [(FeatureVector, BankLabel)]?
    public let featurePrints: any FeaturePrintProviding
    public let k: Int

    public init(bank: ExampleBank, featurePrints: any FeaturePrintProviding = VisionFeaturePrintProvider(), k: Int = 5) {
        self.bank = bank
        self.examples = nil
        self.featurePrints = featurePrints
        self.k = k
    }

    /// Classifier over a fixed example set, so one detection run votes against
    /// a stable bank even when reviews are recorded while it runs.
    public init(examples: [(FeatureVector, BankLabel)],
                featurePrints: any FeaturePrintProviding = VisionFeaturePrintProvider(), k: Int = 5) {
        self.bank = nil
        self.examples = examples
        self.featurePrints = featurePrints
        self.k = k
    }

    /// Reads the bank once and returns an examples-backed copy.
    public func snapshot() async -> FeaturePrintClassifier {
        guard let bank else { return self }
        let entries = await bank.entries().map { ($0.featureVector, $0.label) }
        return FeaturePrintClassifier(examples: entries, featurePrints: featurePrints, k: k)
    }

    public func classify(crop: CGImage, hint: SecurityElement.Kind?) async throws -> ElementJudgement {
        let query = try await featurePrints.featureVector(for: crop)
        let pool: [(FeatureVector, BankLabel)]
        if let examples {
            pool = examples
        } else if let bank {
            pool = await bank.entries().map { ($0.featureVector, $0.label) }
        } else {
            pool = []
        }
        return Self.vote(query: query,
                         examples: pool.filter { $0.0.values.count == query.values.count },
                         k: k)
    }

    /// Distance-weighted vote over the k nearest examples.
    public static func vote(query: FeatureVector, examples: [(FeatureVector, BankLabel)], k: Int) -> ElementJudgement {
        guard !examples.isEmpty else { return .unsure }
        let nearest = examples
            .map { (label: $0.1, distance: query.distance(to: $0.0)) }
            .sorted { $0.distance < $1.distance }
            .prefix(k)
        var weights: [BankLabel: Double] = [:]
        var counts: [BankLabel: Int] = [:]
        for item in nearest {
            let w = 1.0 / (item.distance + 0.05)
            weights[item.label, default: 0] += w
            counts[item.label, default: 0] += 1
        }
        let total = weights.values.reduce(0, +)
        let ranked = weights.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key.exportLabel < $1.key.exportLabel) }
        let winner = ranked[0]
        let runnerUp = ranked.count > 1 ? ranked[1].value : 0
        let confidence = winner.value / total
        let margin = (winner.value - runnerUp) / total
        let kind: SecurityElement.Kind? = { if case .kind(let k) = winner.key { return k } else { return nil } }()
        return ElementJudgement(kind: kind, confidence: confidence, margin: margin,
                                descriptionSK: "", decidedBy: .featurePrintKNN,
                                supportCount: counts[winner.key] ?? 0)
    }
}
