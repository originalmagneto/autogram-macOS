import Foundation
import Security
import CryptoKit
import os

public struct SigningIdentityInfo: Identifiable, Hashable, Sendable {
    public var id: String
    public var label: String
    public var issuerSummary: String
    public var validUntil: Date?
    public var isMandateCertificate: Bool
    public var isQualified: Bool

    public init(id: String, label: String, issuerSummary: String,
                validUntil: Date? = nil, isMandateCertificate: Bool = false,
                isQualified: Bool = false) {
        self.id = id
        self.label = label
        self.issuerSummary = issuerSummary
        self.validUntil = validUntil
        self.isMandateCertificate = isMandateCertificate
        self.isQualified = isQualified
    }
}

public enum SigningError: LocalizedError, Equatable, Sendable {
    case identityUnavailable
    case signingFailed(String)
    case timestampFailed

    public var errorDescription: String? {
        switch self {
        case .identityUnavailable:
            return "Certifikát nie je dostupný — vložte kartu a overte PIN/BOK."
        case .signingFailed(let detail): return "Podpisovanie zlyhalo: \(detail)"
        case .timestampFailed: return "Nepodarilo sa získať kvalifikovanú časovú pečiatku."
        }
    }
}

public struct SignedConversionResult: Sendable {
    public var pdfData: Data
    public var asicData: Data?
    public var signedAt: Date
    public var signatureLabel: String
    public var isLegallyBinding: Bool

    public init(pdfData: Data, asicData: Data?, signedAt: Date,
                signatureLabel: String, isLegallyBinding: Bool) {
        self.pdfData = pdfData
        self.asicData = asicData
        self.signedAt = signedAt
        self.signatureLabel = signatureLabel
        self.isLegallyBinding = isLegallyBinding
    }
}

public protocol QualifiedSigningProviding: Sendable {
    func availableIdentities() async -> [SigningIdentityInfo]
    func sign(pdf: Data, identityID: String, includeTimestamp: Bool) async throws -> SignedConversionResult
}

public final class DemoSigningProvider: QualifiedSigningProviding, @unchecked Sendable {
    private let counter = OSAllocatedUnfairLock(initialState: 0)

    public init() {}

    public func availableIdentities() async -> [SigningIdentityInfo] {
        let systemIdentities = KeychainIdentityScanner.scanCodeSigningIdentities()
        if !systemIdentities.isEmpty { return systemIdentities }
        return [
            SigningIdentityInfo(
                id: "demo",
                label: "DEMO podpis (vývojový režim)",
                issuerSummary: "Autogram Demo CA",
                validUntil: Calendar.current.date(byAdding: .year, value: 1, to: Date()),
                isMandateCertificate: false,
                isQualified: false)
        ]
    }

    public func sign(pdf: Data, identityID: String, includeTimestamp: Bool) async throws -> SignedConversionResult {
        let n = counter.withLock { state -> Int in
            state += 1
            return state
        }

        let digest = SHA256.hash(data: pdf).map { String(format: "%02x", $0) }.joined()
        let manifest = """
        {
          "type": "autogram-demo-signature",
          "legallyBinding": false,
          "note": "Vývojový podpis — nenahrádza KEP s mandátnym certifikátom.",
          "sequence": \(n),
          "identity": "\(identityID)",
          "sha256": "\(digest)",
          "timestampRequested": \(includeTimestamp),
          "signedAtISO": "\(AttestationClauseGenerator.isoFormatter.string(from: Date()))"
        }
        """
        guard let manifestData = manifest.data(using: .utf8) else {
            throw SigningError.signingFailed("Interná chyba manifestu.")
        }

        let asic = try ASiCEPackager().package(files: [
            ASiCEPackager.Entry(path: "mimetype",
                                data: Data("application/vnd.etsi.asic-e+zip".utf8),
                                storeUncompressed: true),
            ASiCEPackager.Entry(path: "META-INF/demo-signature.json", data: manifestData),
            ASiCEPackager.Entry(path: "document.pdf", data: pdf)
        ])

        return SignedConversionResult(
            pdfData: pdf,
            asicData: asic,
            signedAt: Date(),
            signatureLabel: "Demo podpis #\(n) (SHA-256 potvrdený)",
            isLegallyBinding: false)
    }
}

public enum KeychainIdentityScanner {
    public static func scanCodeSigningIdentities() -> [SigningIdentityInfo] {
        var query = [String: Any]()
        query[kSecClass as String] = kSecClassIdentity
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnRef as String] = true

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let refs = result as? [SecIdentity] else { return [] }

        return refs.compactMap { ref in
            var certificate: SecCertificate?
            guard SecIdentityCopyCertificate(ref, &certificate) == errSecSuccess,
                  let cert = certificate else { return nil }

            let summary = SecCertificateCopySubjectSummary(cert) as String? ?? "Certifikát"
            let lowered = summary.lowercased()
            let isMandate = lowered.contains("mandat") || lowered.contains("mandát")

            return SigningIdentityInfo(
                id: summary,
                label: summary,
                issuerSummary: "Keychain",
                validUntil: nil,
                isMandateCertificate: isMandate,
                isQualified: lowered.contains("qcp") || lowered.contains("qualified"))
        }
    }
}
