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
    Si expert na analýzu naskenovaných právnych dokumentov. Na obrázku strany dokumentu identifikuj \
    bezpečnostné prvky: úradné pečiatky (okrúhle), vlastnoručné podpisy, parfy a reliéfne slepotlače. \
    Odpovedaj VÝHRADNE JSON poľom bez ďalšieho textu v tvare:
    [{"kind":"officialStamp","page":1,"box":[x,y,w,h],"confidence":0.9,"description_sk":"Úradná pečiatka ..."}]
    kind ∈ officialStamp | handwrittenSignature | embossedSeal | initial | other.
    box sú normalizované súradnice 0..1 s počiatkom v ľavom hornom rohu strany.
    """

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
            "officialStamp": .officialStamp,
            "handwrittenSignature": .handwrittenSignature,
            "embossedSeal": .embossedSeal,
            "initial": .initial,
            "other": .other
        ]

        return raws.compactMap { raw in
            guard let kindRaw = raw.kind,
                  let kind = kindMap[kindRaw.lowercased()] ?? kindMap[String(kindRaw.lowercased().prefix(20))],
                  let box = raw.box, box.count == 4 else { return nil }
            let page = max((raw.page ?? 1) - 1, 0)
            let rect = NormalizedRect(x: min(max(box[0], 0), 1),
                                      y: min(max(box[1], 0), 1),
                                      width: min(max(box[2], 0), 1),
                                      height: min(max(box[3], 0), 1))
            return SecurityElement(
                kind: kind,
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
    public let transport: any LLMTransport

    public init(endpoint: URL = URL(string: "http://localhost:11434")!,
                model: String = "llava",
                transport: any LLMTransport = URLSessionLLMTransport()) {
        self.endpoint = endpoint
        self.model = model
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
                    "prompt": LLMVisionParser.systemPrompt + "\nToto je strana č. \(pageIndex + 1).",
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
    public let transport: any LLMTransport

    public init(baseURL: URL = URL(string: "https://api.openai.com/v1")!,
                model: String = "gpt-4o-mini",
                apiKey: String,
                transport: any LLMTransport = URLSessionLLMTransport()) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
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
                            ["type": "text", "text": LLMVisionParser.systemPrompt +
                                "\nToto je strana č. \(pageIndex + 1)."],
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
