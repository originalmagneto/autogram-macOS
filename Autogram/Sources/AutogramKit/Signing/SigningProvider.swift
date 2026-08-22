import Foundation
import Security
import CryptoKit
import os
import CryptoTokenKit

public struct SigningIdentityInfo: Identifiable, Hashable, Sendable {
    public var id: String
    public var label: String
    public var issuerSummary: String
    public var validUntil: Date?
    public var isMandateCertificate: Bool
    public var isQualified: Bool
    public var hasPrivateKey: Bool

    public init(id: String, label: String, issuerSummary: String,
                validUntil: Date? = nil, isMandateCertificate: Bool = false,
                isQualified: Bool = false, hasPrivateKey: Bool = true) {
        self.id = id
        self.label = label
        self.issuerSummary = issuerSummary
        self.validUntil = validUntil
        self.isMandateCertificate = isMandateCertificate
        self.isQualified = isQualified
        self.hasPrivateKey = hasPrivateKey
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
        var result = KeychainIdentityScanner.scanAll()
        if !result.isEmpty { return result }

        result.append(SigningIdentityInfo(
            id: "demo",
            label: "DEMO podpis (vývojový režim)",
            issuerSummary: "Autogram Demo CA",
            validUntil: Calendar.current.date(byAdding: .year, value: 1, to: Date()),
            isMandateCertificate: false,
            isQualified: false))
        return result
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
    static let qualifiedIssuerHints = ["i.ca", "ica", "disig", "eid", "e-id", "nase", "nácionalna",
                                       "národná", "slovensko", "qcp", "qualified", "certum", "bok"]

    public static func scanAll() -> [SigningIdentityInfo] {
        var seen = Set<String>()
        var result: [SigningIdentityInfo] = []

        for identity in scanCodeSigningIdentities() where seen.insert(identity.label).inserted {
            result.append(identity)
        }
        for cert in scanTokenCertificates() where seen.insert(cert.label).inserted {
            result.append(cert)
        }
        return result.sorted { lhs, rhs in
            if lhs.hasPrivateKey != rhs.hasPrivateKey { return lhs.hasPrivateKey }
            return lhs.label < rhs.label
        }
    }

    public static func scanCodeSigningIdentities() -> [SigningIdentityInfo] {
        var query = [String: Any]()
        query[kSecClass as String] = kSecClassIdentity
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnRef as String] = true

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess || status == errSecItemNotFound else { return [] }
        guard let refs = result as? [SecIdentity], !refs.isEmpty else { return [] }

        return refs.compactMap { ref in
            var certificate: SecCertificate?
            guard SecIdentityCopyCertificate(ref, &certificate) == errSecSuccess,
                  let cert = certificate else { return nil }

            let summary = SecCertificateCopySubjectSummary(cert) as String? ?? "Certifikát"
            return SigningIdentityInfo(
                id: "identity:\(summary)",
                label: summary,
                issuerSummary: Self.issuerHint(from: summary),
                isMandateCertificate: Self.looksMandate(summary),
                isQualified: Self.looksQualified(summary))
        }
    }

    public static func scanTokenCertificates() -> [SigningIdentityInfo] {
        var query = [String: Any]()
        query[kSecClass as String] = kSecClassCertificate
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnRef as String] = true

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let refs = result as? [SecCertificate] else { return [] }

        return refs.compactMap { cert -> SigningIdentityInfo? in
            let summary = SecCertificateCopySubjectSummary(cert) as String? ?? ""
            guard !summary.isEmpty else { return nil }
            let lowered = summary.lowercased()

            let relevant = lowered.contains("qcp") ||
                           qualifiedIssuerHints.contains { lowered.contains($0) } ||
                           lowered.contains("advok") || lowered.contains("notár") ||
                           lowered.contains("podpis")
            guard relevant else { return nil }

            return SigningIdentityInfo(
                id: "certificate:\(summary)",
                label: summary,
                issuerSummary: Self.issuerHint(from: summary) + " · bez privátneho kľúča cez Keychain",
                isMandateCertificate: Self.looksMandate(summary),
                isQualified: true,
                hasPrivateKey: false)
        }
    }

    public static func connectedTokenNames() -> [String] {
        let watcher = TKTokenWatcher()
        return watcher.tokenIDs.map { tokenID in
            let cleaned = tokenID
                .replacingOccurrences(of: "com.", with: "")
                .replacingOccurrences(of: ".tokenextension", with: "")
                .replacingOccurrences(of: ".pkcs11", with: "")
                .replacingOccurrences(of: ".token", with: "")
            return cleaned.capitalized
        }.sorted()
    }

    static func looksMandate(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("mandat") || lowered.contains("mandát")
    }

    static func looksQualified(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("qcp") || lowered.contains("qualified") ||
               looksMandate(lowered) || qualifiedIssuerHints.contains { lowered.contains($0) }
    }

    static func issuerHint(from summary: String) -> String {
        for hint in ["i.ca", "disig", "eid", "e-id", "nase", "slovensko", "certum"] where summary.lowercased().contains(hint) {
            switch hint {
            case "i.ca": return "I.CA"
            case "disig": return "Disig"
            case "eid", "e-id": return "eID SR"
            case "nase": return "NASE"
            case "slovensko": return "Slovensko.sk"
            case "certum": return "Certum"
            default: continue
            }
        }
        return "Keychain / token"
    }
}
