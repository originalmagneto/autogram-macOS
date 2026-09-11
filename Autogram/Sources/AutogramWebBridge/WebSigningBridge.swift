import Foundation

/// eForm and XML Data Container attributes for a state-portal signing request.
///
/// The field set mirrors the engine's `ServerSigningParameters` so the machine
/// protocol and the engine's own HTTP entry point cannot drift apart. `schema`
/// and `transformation` are the raw XSD and XSLT; they are base64 encoded on
/// the wire, exactly as the engine's HTTP server expects them.
public struct EFormSigningAttributes: Sendable, Equatable, Codable {
    public let containerXmlns: String?
    public let schema: String?
    public let transformation: String?
    public let identifier: String?
    public let schemaIdentifier: String?
    public let transformationIdentifier: String?
    public let transformationLanguage: String?
    public let transformationMediaDestinationTypeDescription: String?
    public let transformationTargetEnvironment: String?
    public let embedUsedSchemas: Bool
    public let autoLoadEform: Bool
    public let fsFormID: String?
    public let packaging: String?

    public static let xmlDataContainerXmlns = "http://data.gov.sk/def/container/xmldatacontainer+xml/1.1"

    public init(
        containerXmlns: String? = xmlDataContainerXmlns,
        schema: String? = nil,
        transformation: String? = nil,
        identifier: String? = nil,
        schemaIdentifier: String? = nil,
        transformationIdentifier: String? = nil,
        transformationLanguage: String? = nil,
        transformationMediaDestinationTypeDescription: String? = nil,
        transformationTargetEnvironment: String? = nil,
        embedUsedSchemas: Bool = false,
        autoLoadEform: Bool = false,
        fsFormID: String? = nil,
        packaging: String? = nil
    ) {
        self.containerXmlns = containerXmlns
        self.schema = schema
        self.transformation = transformation
        self.identifier = identifier
        self.schemaIdentifier = schemaIdentifier
        self.transformationIdentifier = transformationIdentifier
        self.transformationLanguage = transformationLanguage
        self.transformationMediaDestinationTypeDescription = transformationMediaDestinationTypeDescription
        self.transformationTargetEnvironment = transformationTargetEnvironment
        self.embedUsedSchemas = embedUsedSchemas
        self.autoLoadEform = autoLoadEform
        self.fsFormID = fsFormID
        self.packaging = packaging
    }
}

/// Contract shared by the Safari web extension handler and the app.
///
/// Safari delivers `browser.runtime.sendNativeMessage` to a sandboxed app
/// extension, which can neither spawn the signing engine nor reach the card.
/// The extension therefore forwards every request here, over a Mach service the
/// app publishes and the extension is entitled to look up.
public enum WebSigningBridge {
    /// Mach service the app publishes and the extension looks up. The extension
    /// carries `com.apple.security.temporary-exception.mach-lookup.global-name`
    /// for exactly this name, which needs neither a Team ID nor an app group.
    public static let machServiceName = "sk.autogram.Autogram.webbridge"

    /// Label of the launchd agent that owns ``machServiceName``.
    public static let agentLabel = "sk.autogram.Autogram.webbridge"

    /// Payloads at or below this size travel inline as base64 inside the XPC
    /// message. Larger ones are handed over as a file, because the ceiling on a
    /// native message is undocumented and reported to fail opaquely.
    public static let inlinePayloadLimit = 256 * 1024
}

/// Rendezvous published by the launchd agent.
///
/// A plain GUI app cannot publish a named Mach service: launchd owns the name
/// and hands the receive right to the process it launches for it. So a tiny
/// on-demand agent owns the name, the app registers its own anonymous endpoint
/// with it, and the extension asks for that endpoint and then talks to the app
/// directly. The agent is a phone book, not a relay.
@objc public protocol WebBridgeRendezvousProtocol {
    /// Called by the app at launch to publish where it can be reached.
    func registerApp(endpoint: NSXPCListenerEndpoint)

    /// Called by the extension handler to find the running app.
    func appEndpoint(reply: @escaping (NSXPCListenerEndpoint?) -> Void)
}

/// Methods the app exposes to the web extension handler.
///
/// Kept deliberately small: the handler is a relay, not a participant.
@objc public protocol WebSigningBridgeProtocol {
    /// Answers whether the app is ready to sign, so the extension can tell the
    /// page before a document is prepared.
    func status(reply: @escaping (_ ready: Bool, _ version: String) -> Void)

    /// Signs one document. `request` is the JSON encoding of ``WebSignRequest``
    /// and the reply carries the JSON encoding of ``WebSignResponse``.
    func sign(request: Data, reply: @escaping (_ response: Data?, _ error: String?) -> Void)
}

/// A signing request as it arrives from a state portal, before the app turns it
/// into an engine request.
///
/// Mirrors what the ditec shim gives the extension. `content` and `source` are
/// mutually exclusive: small documents travel inline, large ones as a file.
public struct WebSignRequest: Codable, Sendable, Equatable {
    public enum Payload: Codable, Sendable, Equatable {
        /// Base64 document content, for payloads within ``WebSigningBridge/inlinePayloadLimit``.
        case inline(String)
        /// Absolute path inside the extension's own container, plus the SHA-256
        /// of the bytes so the app can refuse anything that was swapped.
        case file(path: String, sha256: String)
    }

    public let requestID: String
    public let filename: String
    public let payload: Payload
    public let payloadMimeType: String
    public let signatureLevel: String
    public let container: String?
    public let eform: EFormSigningAttributes?

    public init(requestID: String, filename: String, payload: Payload, payloadMimeType: String,
                signatureLevel: String, container: String? = nil,
                eform: EFormSigningAttributes? = nil) {
        self.requestID = requestID
        self.filename = filename
        self.payload = payload
        self.payloadMimeType = payloadMimeType
        self.signatureLevel = signatureLevel
        self.container = container
        self.eform = eform
    }

    /// True when the payload mime type carries the `;base64` marker the AVM and
    /// the engine's HTTP server both use to mean "content is already encoded".
    public var isBase64: Bool {
        payloadMimeType.replacingOccurrences(of: " ", with: "").hasSuffix(";base64")
    }
}

/// The signed result handed back to the page.
public struct WebSignResponse: Codable, Sendable, Equatable {
    public let requestID: String
    /// Base64 of the signed container or document.
    public let content: String
    public let signedBy: String
    public let issuedBy: String

    public init(requestID: String, content: String, signedBy: String, issuedBy: String) {
        self.requestID = requestID
        self.content = content
        self.signedBy = signedBy
        self.issuedBy = issuedBy
    }
}
