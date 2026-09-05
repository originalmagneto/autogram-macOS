import Foundation
import CoreGraphics

public enum ClassifierIdentity: String, Sendable, Codable {
    case featurePrintKNN, foundationModel, builtInHint
}

public struct ElementJudgement: Sendable, Equatable {
    /// Nil means "not a security element".
    public var kind: SecurityElement.Kind?
    public var confidence: Double
    /// Winner share minus runner-up share (kNN) or 0 for other classifiers.
    public var margin: Double
    public var descriptionSK: String
    public var decidedBy: ClassifierIdentity
    /// Number of bank examples backing the winning label (kNN only).
    public var supportCount: Int
    /// True when the classifier could not decide at all (no examples, a model
    /// timeout or a model error). A judgement that is not unsure is decisive
    /// even when `kind` is nil and `confidence` is 0.
    public var isUnsure: Bool

    public init(kind: SecurityElement.Kind?, confidence: Double, margin: Double = 0,
                descriptionSK: String = "", decidedBy: ClassifierIdentity, supportCount: Int = 0,
                isUnsure: Bool = false) {
        self.kind = kind
        self.confidence = confidence
        self.margin = margin
        self.descriptionSK = descriptionSK
        self.decidedBy = decidedBy
        self.supportCount = supportCount
        self.isUnsure = isUnsure
    }

    public static let unsure = ElementJudgement(kind: nil, confidence: 0, decidedBy: .featurePrintKNN,
                                                isUnsure: true)
}

public protocol ElementClassifying: Sendable {
    func classify(crop: CGImage, hint: SecurityElement.Kind?) async throws -> ElementJudgement
}
