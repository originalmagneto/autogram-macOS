import Foundation
import Security
import CryptoKit

public enum XAdESError: LocalizedError, Sendable {
    case certificateUnavailable
    case keyUnavailable
    case unsupportedKeyType
    case signingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .certificateUnavailable: return "Certifikát identity sa nepodarilo načítať."
        case .keyUnavailable: return "Súkromný kľúč certifikátu nie je dostupný (karta odpojená alebo zamietnutý PIN)."
        case .unsupportedKeyType: return "Nepodporovaný typ kľúča podpisového certifikátu."
        case .signingFailed(let detail): return "Kryptografická operácia zlyhala: \(detail)"
        }
    }
}

public struct XAdESResult: Sendable {
    public var signatureXML: String
    public var timestampGenTime: Date?
}

public struct XAdESSigner: Sendable {
    public struct DataObject: Sendable {
        public var uri: String
        public var mimeType: String
        public var data: Data

        public init(uri: String, mimeType: String, data: Data) {
            self.uri = uri
            self.mimeType = mimeType
            self.data = data
        }
    }

    public init() {}

    static let dsNS = "http://www.w3.org/2000/09/xmldsig#"
    static let xadesNS = "http://uri.etsi.org/01903/v1.3.2#"
    static let asicNS = "http://uri.etsi.org/02918/v1.2.1#"
    static let sha256DigestMethod = "http://www.w3.org/2001/04/xmlenc#sha256"
    static let sha512DigestMethod = "http://www.w3.org/2001/04/xmlenc#sha512"
    static let excC14N = "http://www.w3.org/2001/10/xml-exc-c14n#"

    public func sign(dataObjects: [DataObject],
                     identity: SecIdentity,
                     includeTimestamp: Bool,
                     tsaURL: URL?) async throws -> XAdESResult {
        var certificateRef: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificateRef) == errSecSuccess,
              let certificate = certificateRef else { throw XAdESError.certificateUnavailable }

        var privateKey: SecKey?
        guard SecIdentityCopyPrivateKey(identity, &privateKey) == errSecSuccess,
              let key = privateKey else { throw XAdESError.keyUnavailable }

        let algorithm = try Self.signingAlgorithm(for: key)
        let signatureMethod = Self.signatureMethod(for: algorithm)

        let certificateDER = Data(SecCertificateCopyData(certificate) as Data)
        guard let facts = X509Inspector.facts(certificateData: certificateDER) else {
            throw XAdESError.certificateUnavailable
        }

        let signatureID = "id-" + UUID().uuidString.lowercased()
        let signedPropsID = "xades-" + signatureID
        let signingTime = AttestationClauseGenerator.isoFormatter.string(from: Date())

        var references = ""
        var dataObjectFormats = ""
        for (index, object) in dataObjects.enumerated() {
            let refID = "\(signatureID)-r\(index + 1)"
            let digest = Data(SHA256.hash(data: object.data)).base64EncodedString()
            references += """

                  <ds:Reference Id="\(refID)" URI="\(Self.uriEscaped(object.uri))">
                    <ds:DigestMethod Algorithm="\(Self.sha256DigestMethod)"/>
                    <ds:DigestValue>\(digest)</ds:DigestValue>
                  </ds:Reference>
                """
            dataObjectFormats += """

                  <xades:DataObjectFormat ObjectReference="#\(refID)">
                    <xades:MimeType>\(object.mimeType)</xades:MimeType>
                  </xades:DataObjectFormat>
                """
        }

        let signedProperties = """


              <xades:SignedProperties xmlns:xades="\(Self.xadesNS)" xmlns:ds="\(Self.dsNS)" Id="\(signedPropsID)">
                <xades:SignedSignatureProperties>
                  <xades:SigningTime>\(signingTime)</xades:SigningTime>
                  <xades:SigningCertificate>
                    <xades:Cert>
                      <xades:CertDigest>
                        <ds:DigestMethod Algorithm="\(Self.sha512DigestMethod)"/>
                        <ds:DigestValue>\(Data(SHA512.hash(data: certificateDER)).base64EncodedString())</ds:DigestValue>
                      </xades:CertDigest>
                      <xades:IssuerSerial>
                        <ds:X509IssuerName>\(Self.escapeXML(facts.issuerRFC2253))</ds:X509IssuerName>
                        <ds:X509SerialNumber>\(facts.serialNumberDecimal)</ds:X509SerialNumber>
                      </xades:IssuerSerial>
                    </xades:Cert>
                  </xades:SigningCertificate>
                </xades:SignedSignatureProperties>
                <xades:SignedDataObjectProperties>\(dataObjectFormats)
                </xades:SignedDataObjectProperties>
              </xades:SignedProperties>
        """

        let signedPropertiesBytes = Data(signedProperties.utf8)
        let signedPropertiesDigest = Data(SHA256.hash(data: signedPropertiesBytes)).base64EncodedString()

        let canonicalSignedInfo = """


              <ds:SignedInfo xmlns:ds="\(Self.dsNS)">
                <ds:CanonicalizationMethod Algorithm="\(Self.excC14N)"/>
                <ds:SignatureMethod Algorithm="\(signatureMethod)"/>\(references)

                <ds:Reference Type="http://uri.etsi.org/01903#SignedProperties" URI="#\(signedPropsID)">
                  <ds:Transforms>
                    <ds:Transform Algorithm="\(Self.excC14N)"/>
                  </ds:Transforms>
                  <ds:DigestMethod Algorithm="\(Self.sha256DigestMethod)"/>
                  <ds:DigestValue>\(signedPropertiesDigest)</ds:DigestValue>
                </ds:Reference>
              </ds:SignedInfo>
            """.trimmingCharacters(in: .whitespacesAndNewlines)

        let signatureValue = try Self.sign(data: Data(canonicalSignedInfo.utf8), with: key, algorithm: algorithm)

        var unsignedBlock = ""
        var timestampGenTime: Date?
        if includeTimestamp, let tsaURL, !tsaURL.absoluteString.isEmpty {
            let reply = try await RFC3161TimestampClient().requestToken(for: signatureValue, tsaURL: tsaURL)
            timestampGenTime = reply.genTime
            let tsID = "ts-" + UUID().uuidString.lowercased()
            unsignedBlock = """



                  <xades:UnsignedProperties>
                    <xades:UnsignedSignatureProperties>
                      <xades:SignatureTimeStamp Id="\(tsID)">
                        <ds:CanonicalizationMethod Algorithm="\(Self.excC14N)"/>
                        <xades:EncapsulatedTimeStamp Id="ets-\(tsID)">\(reply.token.base64EncodedString())</xades:EncapsulatedTimeStamp>
                      </xades:SignatureTimeStamp>
                    </xades:UnsignedSignatureProperties>
                  </xades:UnsignedProperties>
            """
        }

        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <asic:XAdESSignatures xmlns:asic="\(Self.asicNS)">
          <ds:Signature xmlns:ds="\(Self.dsNS)" Id="\(signatureID)">\(canonicalSignedInfo)

            <ds:SignatureValue Id="value-\(signatureID)">\(signatureValue.base64EncodedString())</ds:SignatureValue>
            <ds:KeyInfo>
              <ds:X509Data>
                <ds:X509Certificate>\(certificateDER.base64EncodedString())</ds:X509Certificate>
              </ds:X509Data>
            </ds:KeyInfo>
            <ds:Object>
              <xades:QualifyingProperties xmlns:xades="\(Self.xadesNS)" Target="#\(signatureID)">\(signedProperties)\(unsignedBlock)
              </xades:QualifyingProperties>
            </ds:Object>
          </ds:Signature>
        </asic:XAdESSignatures>
"""


        return XAdESResult(signatureXML: xml, timestampGenTime: timestampGenTime)
    }

    static func uriEscaped(_ uri: String) -> String {
        uri.addingPercentEncoding(
            withAllowedCharacters: CharacterSet(charactersIn:
                "/._-ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")) ?? uri
    }

    static func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func signingAlgorithm(for key: SecKey) throws -> SecKeyAlgorithm {
        if SecKeyIsAlgorithmSupported(key, .sign, .rsaSignatureMessagePKCS1v15SHA256) {
            return .rsaSignatureMessagePKCS1v15SHA256
        }
        if SecKeyIsAlgorithmSupported(key, .sign, .ecdsaSignatureMessageX962SHA256) {
            return .ecdsaSignatureMessageX962SHA256
        }
        throw XAdESError.unsupportedKeyType
    }

    static func signatureMethod(for algorithm: SecKeyAlgorithm) -> String {
        algorithm == .ecdsaSignatureMessageX962SHA256
            ? "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256"
            : "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
    }

    static func sign(data: Data, with key: SecKey, algorithm: SecKeyAlgorithm) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let result = SecKeyCreateSignature(key, algorithm, data as CFData, &error) else {
            let detail = error?.takeRetainedValue().localizedDescription ?? "neznáma chyba"
            throw XAdESError.signingFailed(detail)
        }
        return result as Data
    }

    static func signStatic(data: Data, with key: SecKey) throws -> Data {
        let algorithm = try signingAlgorithm(for: key)
        return try sign(data: data, with: key, algorithm: algorithm)
    }
}
