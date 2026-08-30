import Foundation
import PDFKit

public struct LLMVisionRequest: Sendable {
    public var model: String
    public var prompt: String
    public var imageJPEG: Data
    public init(model: String, prompt: String, imageJPEG: Data) {
        self.model = model
        self.prompt = prompt
        self.imageJPEG = imageJPEG
    }
}

public protocol LLMTransport: Sendable {
    func post(url: URL, headers: [String: String], body: Data) async throws -> Data
}

public struct URLSessionLLMTransport: LLMTransport {
    var timeout: TimeInterval

    public init(timeout: TimeInterval = 90) {
        self.timeout = timeout
    }

    public func post(url: URL, headers: [String: String], body: Data) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AIProviderError.httpStatus(status)
        }
        return data
    }
}

public enum AIProviderError: LocalizedError, Equatable, Sendable {
    case httpStatus(Int)
    case invalidResponse
    case noJSONFound
    case disabled

    public var errorDescription: String? {
        switch self {
        case .httpStatus(let code): return "AI server vrátil chybu \(code)."
        case .invalidResponse: return "Neplatná odpoveď AI servera."
        case .noJSONFound: return "Odpoveď neobsahuje očakávaný JSON."
        case .disabled: return "AI poskytovateľ nie je zapnutý."
        }
    }
}

public enum LLMVisionParser {
    public static let systemPrompt = """
    Inspect this scanned legal-document page and identify only security elements that are
    physically visible in the image. Do not infer text, signatures, stamps, seals, or other
    elements from OCR, context, expected placement, or legal assumptions.
    Classify only these kinds:
    - "officialStamp": a physically visible round official stamp, including a partial imprint.
    - "handwrittenSignature": physically visible handwritten pen or ballpoint marks (vlastnoručný podpis).
    - "embossedSeal": a physically visible colorless embossed impression or relief (slepotlač).
    - "initial": a physically visible short handwritten initial or parafa.
    - "other": another physically visible security element, such as a notarial attachment (notárska
      pripojka), holographic note, or official sticker.
    Rules:
    1. Report every occurrence as a separate object, including partial occurrences.
    2. Draw tight bounding boxes around the visible element only. Do not include surrounding
       whitespace or unrelated text.
    3. If uncertain, omit the element rather than guessing.
    4. Return JSON only, with no explanation or markdown:
    [{"kind":"officialStamp","page":1,"box":[x,y,w,h],"confidence":0.9,"description_sk":"Úradná pečiatka ..."}]
    5. kind must be one of officialStamp, handwrittenSignature, embossedSeal, initial, other.
    6. box is [x,y,w,h] normalized to 0..1, origin at the top-left of the page.
    7. confidence must be in 0..1. description_sk is a short Slovak description of the
       physically visible element and its position.
    8. If no security element is physically visible, return [].
    """

    public static func effectivePrompt(_ override: String?) -> String {
        guard let override, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return systemPrompt
        }
        return """
        \(override)

        Formát odpovede musí zostať JSON pole:
        [{"kind":"...","page":1,"box":[x,y,w,h],"confidence":0.9,"description_sk":"..."}]
        kind ∈ officialStamp | handwrittenSignature | embossedSeal | initial | other,
        box normalizované 0..1 s počiatkom v ľavom hornom rohu.
        """
    }

    public static func extractJSONArray(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"),
              start < end else { return nil }
        return String(text[start...end]).data(using: .utf8)
    }

    public static func decode(elements: Data) -> [SecurityElement] {
        struct RawElement: Decodable {
            let kind: String?
            let page: Int?
            let box: [Double]?
            let confidence: Double?
            let description_sk: String?
        }

        guard let raws = try? JSONDecoder().decode([RawElement].self, from: elements) else {
            return []
        }

        let kindMap: [String: SecurityElement.Kind] = [
            "officialstamp": .officialStamp,
            "official_stamp": .officialStamp,
            "stamp": .officialStamp,
            "pečiatka": .officialStamp,
            "peciatka": .officialStamp,
            "handwrittensignature": .handwrittenSignature,
            "handwritten_signature": .handwrittenSignature,
            "signature": .handwrittenSignature,
            "podpis": .handwrittenSignature,
            "embossedseal": .embossedSeal,
            "embossed_seal": .embossedSeal,
            "slepotlač": .embossedSeal,
            "slepotlac": .embossedSeal,
            "initial": .initial,
            "parafa": .initial,
            "other": .other
        ]

        return raws.compactMap { raw in
            guard let kindRaw = raw.kind else { return nil }
            let normalized = kindRaw.lowercased().trimmingCharacters(in: .whitespaces)
            let kind = kindMap[normalized]
                ?? kindMap[normalized.replacingOccurrences(of: " ", with: "_")]
                ?? (normalized.contains("stamp") || normalized.contains("pečiat")
                    ? SecurityElement.Kind.officialStamp : nil)
                ?? (normalized.contains("signat") || normalized.contains("podpis")
                    ? SecurityElement.Kind.handwrittenSignature : nil)
                ?? (normalized.contains("seal") || normalized.contains("slepotl")
                    ? SecurityElement.Kind.embossedSeal : nil)
            guard let box = raw.box, box.count == 4 else { return nil }
            let resolvedKind = kind ?? .other
            let page = max((raw.page ?? 1) - 1, 0)
            let x = min(max(box[0], 0), 1)
            let width = min(max(box[2], 0), 1 - x)
            let height = min(max(box[3], 0), 1)
            let topOriginY = min(max(box[1], 0), 1 - height)
            // The UI and XML domain use PDF coordinates (y=0 at the bottom),
            // while the model prompt intentionally asks for image coordinates
            // (y=0 at the top). Convert exactly once at the parser boundary.
            let rect = NormalizedRect(x: x,
                                      y: 1 - topOriginY - height,
                                      width: width,
                                      height: height)
            return SecurityElement(
                kind: resolvedKind,
                pageIndex: page,
                boundingBox: rect,
                confidence: min(max(raw.confidence ?? 0.7, 0), 1),
                verbalDescription: raw.description_sk ?? "",
                detectedByAI: true)
        }
}
}

public struct LLMVisionDetectionOutcome: Sendable {
    public let elements: [SecurityElement]
    public let failureMessage: String?

    public init(elements: [SecurityElement], failureMessage: String? = nil) {
        self.elements = elements
        self.failureMessage = failureMessage
    }
}

public protocol LLMVisionProviderReporting: SecurityElementsProviding {
    func detectWithStatus(in document: PDFDocument,
                          pageAnalyses: [PageAnalysis]) async -> LLMVisionDetectionOutcome
}



public struct OllamaVisionProvider: LLMVisionProviderReporting {
    public var providerName: String { "Ollama (\(model))" }

    public let endpoint: URL
    public let model: String
    public let promptOverride: String?
    public let transport: any LLMTransport

    public init(endpoint: URL = URL(string: "http://localhost:11434")!,
                model: String = "llava",
                promptOverride: String? = nil,
                transport: any LLMTransport = URLSessionLLMTransport()) {
        self.endpoint = endpoint
        self.model = model
        self.promptOverride = promptOverride
        self.transport = transport
    }

    public func detect(in document: PDFDocument, pageAnalyses: [PageAnalysis]) async -> [SecurityElement] {
        await detectWithStatus(in: document, pageAnalyses: pageAnalyses).elements
    }

    public func detectWithStatus(in document: PDFDocument,
                                 pageAnalyses: [PageAnalysis]) async -> LLMVisionDetectionOutcome {
        var all: [SecurityElement] = []
        var failureMessage: String?
        for pageIndex in 0..<document.pageCount {
            if let analysis = pageAnalyses.first(where: { $0.pageIndex == pageIndex }), analysis.isEmpty { continue }
            guard let page = document.page(at: pageIndex) else { continue }
            guard let pixels = BuiltInVisionProvider.renderPixels(page: page, targetWidth: 640),
                  let jpeg = pixels.jpegData() else { continue }

            do {
                let payload: [String: Any] = [
                    "model": model,
                    "prompt": LLMVisionParser.effectivePrompt(promptOverride)
                        + "\nToto je strana č. \(pageIndex + 1).",
                    "images": [jpeg.base64EncodedString()],
                    "stream": false
                ]
                let body = try JSONSerialization.data(withJSONObject: payload)
                let data = try await transport.post(url: endpoint.appendingPathComponent("api/generate"),
                                                    headers: [:], body: body)
                guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let text = object["response"] as? String,
                      let arrayJSON = LLMVisionParser.extractJSONArray(from: text),
                      let rawObject = try? JSONSerialization.jsonObject(with: arrayJSON),
                      let rawArray = rawObject as? [Any] else {
                    failureMessage = failureMessage ?? "\(providerName): Neplatná odpoveď AI servera."
                    continue
                }
                let decoded = LLMVisionParser.decode(elements: arrayJSON).map {
                    var element = $0
                    element.pageIndex = pageIndex
                    return element
                }
                if !rawArray.isEmpty && decoded.isEmpty {
                    failureMessage = failureMessage ?? "\(providerName): Neplatná odpoveď AI servera."
                    continue
                }
                all.append(contentsOf: decoded)
            } catch {
                failureMessage = failureMessage ?? "\(providerName): \(error.localizedDescription)"
            }
        }
        return LLMVisionDetectionOutcome(elements: all, failureMessage: failureMessage)
    }
}

public struct OpenAIVisionProvider: LLMVisionProviderReporting {
    public var providerName: String { "OpenAI-compatible (\(model))" }

    public let baseURL: URL
    public let model: String
    public let apiKey: String
    public let promptOverride: String?
    public let transport: any LLMTransport

    public init(baseURL: URL = URL(string: "https://api.openai.com/v1")!,
                model: String = "gpt-4o-mini",
                apiKey: String,
                promptOverride: String? = nil,
                transport: any LLMTransport = URLSessionLLMTransport()) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.promptOverride = promptOverride
        self.transport = transport
    }

    public func detect(in document: PDFDocument, pageAnalyses: [PageAnalysis]) async -> [SecurityElement] {
        await detectWithStatus(in: document, pageAnalyses: pageAnalyses).elements
    }

    public func detectWithStatus(in document: PDFDocument,
                                 pageAnalyses: [PageAnalysis]) async -> LLMVisionDetectionOutcome {
        var all: [SecurityElement] = []
        var failureMessage: String?
        for pageIndex in 0..<document.pageCount {
            if let analysis = pageAnalyses.first(where: { $0.pageIndex == pageIndex }), analysis.isEmpty { continue }
            guard let page = document.page(at: pageIndex) else { continue }
            guard let pixels = BuiltInVisionProvider.renderPixels(page: page, targetWidth: 640),
                  let jpeg = pixels.jpegData() else { continue }
            let b64 = jpeg.base64EncodedString()

            do {
                let payload: [String: Any] = [
                    "model": model,
                    "messages": [[
                        "role": "user",
                        "content": [
                            ["type": "text", "text": LLMVisionParser.effectivePrompt(promptOverride)
                                + "\nToto je strana č. \(pageIndex + 1)."],
                            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(b64)"]]
                        ]
                    ]],
                    "temperature": 0
                ]
                let body = try JSONSerialization.data(withJSONObject: payload)
                let data = try await transport.post(url: baseURL.appendingPathComponent("chat/completions"),
                                                    headers: ["Authorization": "Bearer \(apiKey)"],
                                                    body: body)
                guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = object["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let content = message["content"] as? String,
                      let arrayJSON = LLMVisionParser.extractJSONArray(from: content),
                      let rawObject = try? JSONSerialization.jsonObject(with: arrayJSON),
                      let rawArray = rawObject as? [Any] else {
                    failureMessage = failureMessage ?? "\(providerName): Neplatná odpoveď AI servera."
                    continue
                }
                let decoded = LLMVisionParser.decode(elements: arrayJSON).map {
                    var element = $0
                    element.pageIndex = pageIndex
                    return element
                }
                if !rawArray.isEmpty && decoded.isEmpty {
                    failureMessage = failureMessage ?? "\(providerName): Neplatná odpoveď AI servera."
                    continue
                }
                all.append(contentsOf: decoded)
            } catch {
                failureMessage = failureMessage ?? "\(providerName): \(error.localizedDescription)"
            }
        }
        return LLMVisionDetectionOutcome(elements: all, failureMessage: failureMessage)
    }
}
public extension DetectionPipeline {
    /// Runs built-in detection first and reports an external LLM failure separately.
    /// Built-in findings remain available even when the augmentation is unavailable.
    func detectWithStatus(in document: PDFDocument,
                          pageAnalyses: [PageAnalysis]) async -> LLMVisionDetectionOutcome {
        let builtinElements = await builtin.detect(in: document, pageAnalyses: pageAnalyses)
        guard let llmProvider else {
            return LLMVisionDetectionOutcome(elements: builtinElements)
        }

        let llmOutcome: LLMVisionDetectionOutcome
        if let reportingProvider = llmProvider as? any LLMVisionProviderReporting {
            llmOutcome = await reportingProvider.detectWithStatus(
                in: document,
                pageAnalyses: pageAnalyses)
        } else {
            llmOutcome = LLMVisionDetectionOutcome(
                elements: await llmProvider.detect(in: document, pageAnalyses: pageAnalyses))
        }
        let merged = SecurityElementMerger.merge(
            primary: builtinElements,
            secondary: llmOutcome.elements)
        return LLMVisionDetectionOutcome(
            elements: merged.sorted {
                ($0.pageIndex, $0.boundingBox.y) < ($1.pageIndex, $1.boundingBox.y)
            },
            failureMessage: llmOutcome.failureMessage)
    }
}
