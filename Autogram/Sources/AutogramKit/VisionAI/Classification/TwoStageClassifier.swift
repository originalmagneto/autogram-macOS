import Foundation
import CoreGraphics

/// kNN first; Foundation Model when kNN is unsure; built-in hint as last resort.
public struct TwoStageClassifier: Sendable {
    public let primary: any ElementClassifying
    public let secondary: (any ElementClassifying)?
    public let minimumSupport: Int
    public let minimumMargin: Double

    public init(primary: any ElementClassifying, secondary: (any ElementClassifying)?,
                minimumSupport: Int = 3, minimumMargin: Double = 0.25) {
        self.primary = primary
        self.secondary = secondary
        self.minimumSupport = minimumSupport
        self.minimumMargin = minimumMargin
    }

    /// Returns nil when the candidate should be discarded.
    public func classify(crop: CGImage, hint: SecurityElement.Kind?, hintConfidence: Double?) async -> ElementJudgement? {
        let primaryJudgement = (try? await primary.classify(crop: crop, hint: hint)) ?? .unsure
        var secondaryJudgement: ElementJudgement? = nil
        if !Self.isConfident(primaryJudgement, minimumSupport: minimumSupport, minimumMargin: minimumMargin),
           let secondary {
            secondaryJudgement = try? await secondary.classify(crop: crop, hint: hint)
        }
        return Self.decide(primary: primaryJudgement, secondary: secondaryJudgement, hint: hint,
                           hintConfidence: hintConfidence, minimumSupport: minimumSupport, minimumMargin: minimumMargin)
    }

    static func isConfident(_ j: ElementJudgement, minimumSupport: Int, minimumMargin: Double) -> Bool {
        j.supportCount >= minimumSupport && j.margin >= minimumMargin
    }

    public static func decide(primary: ElementJudgement, secondary: ElementJudgement?,
                              hint: SecurityElement.Kind?, hintConfidence: Double?,
                              minimumSupport: Int, minimumMargin: Double) -> ElementJudgement? {
        if isConfident(primary, minimumSupport: minimumSupport, minimumMargin: minimumMargin) {
            return primary.kind == nil ? nil : primary
        }
        if let secondary {
            guard let kind = secondary.kind else { return nil }
            var result = secondary
            if primary.kind == kind {
                result.confidence = 0.6 * secondary.confidence + 0.4 * primary.confidence
            }
            result.kind = kind
            return result
        }
        if let hint {
            return ElementJudgement(kind: hint, confidence: hintConfidence ?? 0.5, decidedBy: .builtInHint)
        }
        return nil
    }
}
