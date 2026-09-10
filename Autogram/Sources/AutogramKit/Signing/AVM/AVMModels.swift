import Foundation

public enum AVMSignatureLevel: String, Codable, Sendable, CaseIterable {
    case padesB = "PAdES_BASELINE_B"
    case padesT = "PAdES_BASELINE_T"
    case xadesB = "XAdES_BASELINE_B"
    case xadesT = "XAdES_BASELINE_T"
    case cadesB = "CAdES_BASELINE_B"
    case cadesT = "CAdES_BASELINE_T"

    public static func pades(timestamp: Bool) -> AVMSignatureLevel { timestamp ? .padesT : .padesB }
    public static func xades(timestamp: Bool) -> AVMSignatureLevel { timestamp ? .xadesT : .xadesB }
}

public enum AVMContainer: String, Codable, Sendable {
    case asicE = "ASiC-E"
    case asicS = "ASiC-S"
}

/// Body of `POST /documents`.
public struct AVMUploadRequest: Encodable, Sendable, Equatable {
    public static let pdfMimeType = "application/pdf"
    public static let asicEMimeType = "application/vnd.etsi.asic-e+zip"

    public struct Document: Encodable, Sendable, Equatable {
        public var filename: String
        /// Base64 of the raw file bytes.
        public var content: String
    }

    public struct Parameters: Encodable, Sendable, Equatable {
        public var level: AVMSignatureLevel
        public var container: AVMContainer?
    }

    public var document: Document
    public var parameters: Parameters
    public var payloadMimeType: String

    public init(filename: String, data: Data, mimeType: String,
                level: AVMSignatureLevel, container: AVMContainer? = nil) {
        self.document = Document(filename: filename, content: data.base64EncodedString())
        self.parameters = Parameters(level: level, container: container)
        self.payloadMimeType = mimeType
    }
}

/// Everything the client must remember to poll, download or delete one document.
public struct AVMDocumentReference: Sendable, Equatable {
    public var guid: String
    public var key: AVMDocumentKey
    /// HTTP date from the upload response, sent back as `If-Modified-Since`.
    public var lastModified: String

    public init(guid: String, key: AVMDocumentKey, lastModified: String) {
        self.guid = guid
        self.key = key
        self.lastModified = lastModified
    }
}

public struct AVMSigner: Codable, Sendable, Equatable {
    public var signedBy: String?
    public var issuedBy: String?

    public init(signedBy: String?, issuedBy: String?) {
        self.signedBy = signedBy
        self.issuedBy = issuedBy
    }
}

/// Body of `GET /documents/{guid}` once the document is signed.
public struct AVMSignedDocument: Decodable, Sendable, Equatable {
    public var filename: String?
    public var mimeType: String?
    public var content: String
    public var signers: [AVMSigner]?

    public init(filename: String?, mimeType: String?, content: String, signers: [AVMSigner]?) {
        self.filename = filename
        self.mimeType = mimeType
        self.content = content
        self.signers = signers
    }

    public var data: Data? {
        Data(base64Encoded: content) ?? Data(base64Encoded: content, options: .ignoreUnknownCharacters)
    }
}

public enum AVMPollResult: Sendable, Equatable {
    case pending
    case signed(AVMSignedDocument)
}

struct AVMServerErrorBody: Decodable {
    var code: String?
    var message: String?
    var details: String?
}

public enum AVMError: Error, Equatable, LocalizedError {
    case server(status: Int, code: String?, message: String?)
    case invalidResponse
    case timeout
    case cancelled
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .server(let status, let code, let message):
            let detail = [code, message].compactMap { $0 }.joined(separator: ": ")
            return detail.isEmpty
                ? "Server Autogram v mobile odpovedal chybou \(status)."
                : "Server Autogram v mobile odpovedal chybou \(status) (\(detail))."
        case .invalidResponse:
            return "Server Autogram v mobile vrátil neočakávanú odpoveď."
        case .timeout:
            return "Podpis z mobilu neprišiel včas."
        case .cancelled:
            return "Podpisovanie mobilom bolo zrušené."
        case .transport(let detail):
            return "Server Autogram v mobile je nedostupný (\(detail))."
        }
    }
}
