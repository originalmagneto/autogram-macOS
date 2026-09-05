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

    public init(kind: SecurityElement.Kind?, confidence: Double, margin: Double = 0,
                descriptionSK: String = "", decidedBy: ClassifierIdentity, supportCount: Int = 0) {
        self.kind = kind
        self.confidence = confidence
        self.margin = margin
        self.descriptionSK = descriptionSK
        self.decidedBy = decidedBy
        self.supportCount = supportCount
    }

    public static let unsure = ElementJudgement(kind: nil, confidence: 0, decidedBy: .featurePrintKNN)
}

public protocol ElementClassifying: Sendable {
    func classify(crop: CGImage, hint: SecurityElement.Kind?) async throws -> ElementJudgement
}
