import Foundation
import CoreGraphics
import FoundationModels

public enum FoundationJudgementKind: String, Sendable, CaseIterable, Codable {
    case stamp, signature, embossedSeal, initial, other, none

    public var securityKind: SecurityElement.Kind? {
        switch self {
        case .stamp: return .officialStamp
        case .signature: return .handwrittenSignature
        case .embossedSeal: return .embossedSeal
        case .initial: return .initial
        case .other: return .other
        case .none: return nil
        }
    }
}

public struct FoundationJudgement: Sendable, Equatable {
    public var isSecurityElement: Bool
    public var kind: FoundationJudgementKind
    public var descriptionSK: String
    public var confidence: Double

    public init(isSecurityElement: Bool, kind: FoundationJudgementKind, descriptionSK: String, confidence: Double) {
        self.isSecurityElement = isSecurityElement
        self.kind = kind
        self.descriptionSK = descriptionSK
        self.confidence = confidence
    }
}

public protocol FoundationJudging: Sendable {
    func judge(crop: CGImage, hint: SecurityElement.Kind?) async throws -> FoundationJudgement
}

/// Structured output type for the on-device model.
@Generable(description: "Judgement whether a crop of a scanned legal document shows a physical security element")
struct GeneratedJudgement {
    @Guide(description: "true only if a stamp, handwritten signature, embossed seal or handwritten initial is physically visible in the image")
    var isSecurityElement: Bool
    @Guide(description: "one of: stamp, signature, embossedSeal, initial, other, none")
    var kind: String
    @Guide(description: "one short Slovak sentence describing the visible element, empty if none")
    var descriptionSK: String
    @Guide(description: "confidence between 0 and 1", .range(0.0...1.0))
    var confidence: Double
}

/// Live judge. One session per instance; calls are serialised by the actor.
public actor SystemFoundationJudge: FoundationJudging {
    private let session: LanguageModelSession

    public init() {
        session = LanguageModelSession(instructions: """
        You inspect small crops of scanned Slovak legal documents. Decide only from what is \
        physically visible in the image. Never infer an element from context, expected placement, \
        or surrounding text. A stamp is an inked impression (often round, blue or red, with text or \
        a coat of arms). A signature is handwritten cursive ink. An embossed seal is a colourless \
        relief impression. An initial is a short handwritten mark. Printed text, logos, lines, tables \
        and photographs are not security elements. Answer in the requested structure. \
        descriptionSK must be Slovak.
        """)
    }

    public func judge(crop: CGImage, hint: SecurityElement.Kind?) async throws -> FoundationJudgement {
        let hintText = hint.map { "A heuristic detector suggested this may be: \($0.rawValue). Verify visually." } ?? ""
        let response = try await session.respond(generating: GeneratedJudgement.self,
                                                 options: GenerationOptions(temperature: 0)) {
            "Is a physical security element visible in this crop? \(hintText)"
            Attachment(crop)
        }
        let content = response.content
        return FoundationJudgement(isSecurityElement: content.isSecurityElement,
                                   kind: FoundationJudgementKind(rawValue: content.kind) ?? .none,
                                   descriptionSK: content.descriptionSK,
                                   confidence: min(max(content.confidence, 0), 1))
    }
}

public struct FoundationModelClassifier: ElementClassifying {
    public let judge: any FoundationJudging
    public let timeoutSeconds: Double

    public init(judge: any FoundationJudging, timeoutSeconds: Double = 8) {
        self.judge = judge
        self.timeoutSeconds = timeoutSeconds
    }

    public static func makeIfAvailable(timeoutSeconds: Double = 8) -> FoundationModelClassifier? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        return FoundationModelClassifier(judge: SystemFoundationJudge(), timeoutSeconds: timeoutSeconds)
    }

    public func classify(crop: CGImage, hint: SecurityElement.Kind?) async throws -> ElementJudgement {
        let judge = self.judge
        let timeout = timeoutSeconds
        let crop = crop
        return try await withThrowingTaskGroup(of: ElementJudgement?.self) { group in
            group.addTask { Self.map(try await judge.judge(crop: crop, hint: hint)) }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first ?? ElementJudgement(kind: nil, confidence: 0, decidedBy: .foundationModel)
        }
    }

    public static func map(_ judgement: FoundationJudgement) -> ElementJudgement {
        let kind = judgement.isSecurityElement ? judgement.kind.securityKind : nil
        return ElementJudgement(kind: kind, confidence: judgement.confidence, margin: 0,
                                descriptionSK: judgement.descriptionSK, decidedBy: .foundationModel)
    }
}
