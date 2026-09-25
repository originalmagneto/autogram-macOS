// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

/// Decides whether a freshly trained candidate model replaces the active
/// one. The rule from the spec: mean recall across trained labels must rise
/// by at least 0.05 while mean precision must not drop by more than 0.02,
/// both measured on held-out documents. The previous model is kept by the
/// registry for one-click rollback.
public enum DetectorPromotion {
    public enum Decision: Equatable {
        case promote(recallGain: Double, precisionDelta: Double)
        case keep(reason: String)
    }

    public static let requiredRecallGain = 0.05
    public static let allowedPrecisionDrop = 0.02

    public static func decide(candidate: [String: LabelMetrics],
                              active: [String: LabelMetrics],
                              trainedLabels: Set<String>) -> Decision {
        guard !trainedLabels.isEmpty else { return .keep(reason: "no trained labels") }
        func mean(_ metrics: [String: LabelMetrics], _ pick: (LabelMetrics) -> Double) -> Double {
            let values = trainedLabels.map { pick(metrics[$0] ?? LabelMetrics(truePositives: 0, falsePositives: 0, falseNegatives: 0)) }
            return values.reduce(0, +) / Double(values.count)
        }
        let recallGain = mean(candidate, \.recall) - mean(active, \.recall)
        let precisionDelta = mean(candidate, \.precision) - mean(active, \.precision)
        guard recallGain >= requiredRecallGain else {
            return .keep(reason: String(format: "recall gain %.2f below %.2f", recallGain, requiredRecallGain))
        }
        guard precisionDelta >= -allowedPrecisionDrop else {
            return .keep(reason: String(format: "precision drop %.2f over %.2f", -precisionDelta, allowedPrecisionDrop))
        }
        return .promote(recallGain: recallGain, precisionDelta: precisionDelta)
    }
}
