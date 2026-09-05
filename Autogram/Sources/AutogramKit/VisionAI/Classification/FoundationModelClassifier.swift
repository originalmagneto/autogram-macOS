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
    /// `context` carries extra evidence about the crop (for example OCR text
    /// coverage). Empty when nothing is known.
    func judge(crop: CGImage, hint: SecurityElement.Kind?, context: String) async throws -> FoundationJudgement
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
        and photographs are not security elements. Printed or typed text, names, addresses, \
        numbers, table cells, form fields, ruled boxes and underlines are NOT security elements \
        even when bold. A handwritten signature shows irregular pen strokes that do not look like \
        a font. Answer in the requested structure. descriptionSK must be Slovak.
        """)
        // Warming the session moves model load off the first real classification.
        session.prewarm()
    }

    public func judge(crop: CGImage, hint: SecurityElement.Kind?, context: String) async throws -> FoundationJudgement {
        let hintText = hint.map { "A heuristic detector suggested this may be: \($0.rawValue). Verify visually." } ?? ""
        let response = try await session.respond(generating: GeneratedJudgement.self,
                                                 options: GenerationOptions(temperature: 0)) {
            "Is a physical security element visible in this crop? \(hintText) \(context)"
            Attachment(crop)
        }
        let content = response.content
        return FoundationJudgement(isSecurityElement: content.isSecurityElement,
                                   kind: FoundationJudgementKind(rawValue: content.kind) ?? .none,
                                   descriptionSK: content.descriptionSK,
                                   confidence: min(max(content.confidence, 0), 1))
    }
}

/// Holds the outcome of a judge task so a cancellable polling task can observe it without
/// awaiting the (possibly non-cancellable) judge task directly.
private actor JudgementCell {
    private(set) var result: Result<ElementJudgement, Error>?
    func set(_ r: Result<ElementJudgement, Error>) { result = r }
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
        try await classify(crop: crop, hint: hint, textCoverage: nil)
    }

    /// `textCoverage` is the fraction of the crop covered by OCR text boxes, passed
    /// to the model as extra evidence so printed regions are rejected more reliably.
    public func classify(crop: CGImage, hint: SecurityElement.Kind?,
                         textCoverage: Double?) async throws -> ElementJudgement {
        let judge = self.judge
        let timeout = timeoutSeconds
        let crop = crop
        let context = Self.contextText(textCoverage: textCoverage)
        // The judge runs in its own detached task, outside the task group, because
        // `withThrowingTaskGroup` only returns once every child task has finished.
        // `LanguageModelSession.respond` is not guaranteed to observe cancellation, so if the
        // judge itself were a group child, a slow/non-cancellable model call would block
        // `classify` for the full inference time and the timeout would never be honoured.
        // Instead the judge writes its outcome into an actor-isolated cell, and a cancellable
        // polling child inside the group reads that cell. This lets the group (and therefore
        // `classify`) return as soon as the timeout fires, without ever awaiting the judge task.
        let cell = JudgementCell()
        let judgeTask = Task {
            do {
                let result = Self.map(try await judge.judge(crop: crop, hint: hint, context: context))
                await cell.set(.success(result))
            } catch {
                await cell.set(.failure(error))
            }
        }
        let result: ElementJudgement? = try await withThrowingTaskGroup(of: ElementJudgement?.self) { group in
            group.addTask {
                while !Task.isCancelled {
                    if let outcome = await cell.result {
                        return try outcome.get()
                    }
                    try await Task.sleep(for: .milliseconds(50))
                }
                return nil
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if result == nil {
            judgeTask.cancel()
        }
        return result ?? ElementJudgement(kind: nil, confidence: 0, decidedBy: .foundationModel,
                                          isUnsure: true)
    }

    static func contextText(textCoverage: Double?) -> String {
        guard let textCoverage else { return "" }
        let percent = Int((textCoverage * 100).rounded())
        return "OCR found printed text covering \(percent) % of this region."
    }

    public static func map(_ judgement: FoundationJudgement) -> ElementJudgement {
        let kind = judgement.isSecurityElement ? judgement.kind.securityKind : nil
        return ElementJudgement(kind: kind, confidence: judgement.confidence, margin: 0,
                                descriptionSK: judgement.descriptionSK, decidedBy: .foundationModel)
    }
}
