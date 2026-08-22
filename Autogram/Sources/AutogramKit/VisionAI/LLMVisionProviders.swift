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
    public init() {}
    public func post(url: URL, headers: [String: String], body: Data) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
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
    Analyzuj naskenovanú stranu právneho dokumentu a identifikuj bezpečnostné prvky podľa § 37 \
    zákona č. 305/2013 Z. z. Klasifikuj VÝHRADNE tieto typy:
    - "officialStamp" — okrúhla pečiatka (modrá, fialová, červená), zvyčajne so štátnym znakom, \
    názvom inštitúcie alebo advokátskej kancelárie; aj neúplný otlačok.
    - "handwrittenSignature" — vlastnoručný podpis: rukou písané stopy perom alebo guľôčkovým \
    pisom, typicky v dolnej časti strany alebo pri paragrafoch.
    - "embossedSeal" — reliéfna slepotlač: bezfarebný vtláčok viditeľný len ako tieň/relief.
    - "initial" — parafa: krátka značka jednej alebo dvoch iniciál.
    - "other" — iný bezpečnostný prvok (notárska pripojka, holografická poznámka, úradná nálepka).
    Pravidlá:
    1. Každý výskyt = jeden objekt poľa.
    2. Odpovedaj VÝHRADNE JSON poľom, bez akéhokoľvek iného textu:
    [{"kind":"officialStamp","page":1,"box":[x,y,w,h],"confidence":0.9,"description_sk":"Úradná pečiatka ..."}]
    3. kind ∈ officialStamp | handwrittenSignature | embossedSeal | initial | other
    4. box je [x,y,w,h] normalizované na 0..1, počiatok v ľavom hornom rohu strany; \
    box musí tesne obklopiť prvok.
    5. confidence ∈ 0..1 — reálne odhadni istotu, pri pochybnostiach < 0.6.
    6. description_sk — krátky slovný opis po slovensky vrátane polohy (napr. „v pravej dolnej časti“).
    7. Ak sa na strane nenachádza žiadny prvok, odpovedaj [].
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
            let rect = NormalizedRect(x: min(max(box[0], 0), 1),
                                      y: min(max(box[1], 0), 1),
                                      width: min(max(box[2], 0), 1),
                                      height: min(max(box[3], 0), 1))
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

public struct OllamaVisionProvider: SecurityElementsProviding {
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
        var all: [SecurityElement] = []
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
                if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let text = object["response"] as? String,
                   let arrayJSON = LLMVisionParser.extractJSONArray(from: text) {
                    let decoded = LLMVisionParser.decode(elements: arrayJSON).map {
                        var element = $0; element.pageIndex = pageIndex; return element
                    }
                    all.append(contentsOf: decoded)
                }
            } catch {
                continue
            }
        }
        return all
    }
}

public struct OpenAIVisionProvider: SecurityElementsProviding {
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
        var all: [SecurityElement] = []
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
                if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = object["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String,
                   let arrayJSON = LLMVisionParser.extractJSONArray(from: content) {
                    let decoded = LLMVisionParser.decode(elements: arrayJSON).map {
                        var element = $0; element.pageIndex = pageIndex; return element
                    }
                    all.append(contentsOf: decoded)
                }
            } catch {
                continue
            }
        }
        return all
    }
}
