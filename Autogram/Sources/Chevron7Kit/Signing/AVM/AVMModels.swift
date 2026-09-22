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
    /// The `;base64` suffix tells avm-server that `content` is already base64.
    /// Without it the server base64-encodes the payload a second time.
    public static let pdfMimeType = "application/pdf;base64"
    public static let asicEMimeType = "application/vnd.etsi.asic-e+zip;base64"

    public struct Document: Encodable, Sendable, Equatable {
        public var filename: String
        /// Base64 of the raw file bytes.
        public var content: String
    }

    public struct Parameters: Encodable, Sendable, Equatable {
        public var level: AVMSignatureLevel
        public var container: AVMContainer?
        /// eForm and XML Data Container attributes. The relay accepts the same
        /// set as the local engine, so a state-portal form can be signed on the
        /// phone as well as with a card. Omitted entirely for plain documents.
        public var containerXmlns: String?
        public var identifier: String?
        public var schema: String?
        public var transformation: String?
        public var schemaIdentifier: String?
        public var transformationIdentifier: String?
        public var transformationLanguage: String?
        public var transformationMediaDestinationTypeDescription: String?
        public var transformationTargetEnvironment: String?
        public var embedUsedSchemas: Bool?
        public var autoLoadEform: Bool?
        public var packaging: String?
    }

    public var document: Document
    public var parameters: Parameters
    public var payloadMimeType: String

    public static let xmlMimeType = "application/xml;base64"

    public init(filename: String, data: Data, mimeType: String,
                level: AVMSignatureLevel, container: AVMContainer? = nil,
                eform: EFormSigningAttributes? = nil) {
        self.document = Document(filename: filename, content: data.base64EncodedString())
        var parameters = Parameters(level: level, container: container)
        if let eform {
            // The relay expects the schema and transformation base64 encoded,
            // exactly as the engine's own HTTP server does.
            parameters.containerXmlns = eform.containerXmlns
            parameters.identifier = eform.identifier
            parameters.schema = eform.schema.map { Data($0.utf8).base64EncodedString() }
            parameters.transformation = eform.transformation.map { Data($0.utf8).base64EncodedString() }
            parameters.schemaIdentifier = eform.schemaIdentifier
            parameters.transformationIdentifier = eform.transformationIdentifier
            parameters.transformationLanguage = eform.transformationLanguage
            parameters.transformationMediaDestinationTypeDescription =
                eform.transformationMediaDestinationTypeDescription
            parameters.transformationTargetEnvironment = eform.transformationTargetEnvironment
            parameters.embedUsedSchemas = eform.embedUsedSchemas
            parameters.autoLoadEform = eform.autoLoadEform
            parameters.packaging = eform.packaging
        }
        self.parameters = parameters
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
