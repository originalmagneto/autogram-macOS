import Foundation
import CoreGraphics

public struct FeaturePrintClassifier: ElementClassifying {
    public let bank: ExampleBank
    public let featurePrints: any FeaturePrintProviding
    public let k: Int

    public init(bank: ExampleBank, featurePrints: any FeaturePrintProviding = VisionFeaturePrintProvider(), k: Int = 5) {
        self.bank = bank
        self.featurePrints = featurePrints
        self.k = k
    }

    public func classify(crop: CGImage, hint: SecurityElement.Kind?) async throws -> ElementJudgement {
        let query = try await featurePrints.featureVector(for: crop)
        let examples = await bank.entries()
            .filter { $0.featureVector.values.count == query.values.count }
            .map { ($0.featureVector, $0.label) }
        return Self.vote(query: query, examples: examples, k: k)
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
