import Foundation

struct SigningToken: Sendable, Equatable {
    let tokenKey: String
    let providerName: String
}

struct CertificateDiscovery: Sendable, Equatable {
    let token: SigningToken
    let certificates: [SigningCertificate]
}

struct RememberedCertificateDefault: Codable, Sendable, Equatable {
    let tokenKey: String
    let providerName: String
    let certificateKey: String
    let holderKey: String
    let commonName: String
    let issuer: String
    let validUntil: Date
}

struct RememberedSigningToken: Codable, Sendable, Equatable, Identifiable {
    let tokenKey: String
    let providerName: String
    var certificateDefault: RememberedCertificateDefault?
    private let storageVersion: Int

    var id: String { tokenKey }

    init(
        tokenKey: String,
        providerName: String,
        certificateDefault: RememberedCertificateDefault?,
        storageVersion: Int = 1
    ) {
        self.tokenKey = tokenKey
        self.providerName = providerName
        self.certificateDefault = certificateDefault
        self.storageVersion = storageVersion
    }
}

enum CertificateSelection: Sendable, Equatable {
    case selected(SigningCertificate)
    case pickerRequired
}

enum CertificateDefaultSelector {
    static func select(
        from discovery: CertificateDiscovery,
        remembered: RememberedCertificateDefault?,
        now: Date
    ) -> CertificateSelection {
        let eligible = discovery.certificates.filter { $0.validFrom <= now && now <= $0.validUntil }
        let remembered = remembered?.tokenKey == discovery.token.tokenKey ? remembered : nil

        if let remembered,
           let exact = discovery.certificates.first(where: { $0.certificateKey == remembered.certificateKey }) {
            if exact.validFrom <= now && now <= exact.validUntil {
                return .selected(exact)
            }
            if exact.validUntil >= now {
                return .pickerRequired
            }
        }

        if let remembered, !remembered.holderKey.isEmpty {
            let renewals = eligible.filter { $0.holderKey == remembered.holderKey }
            if renewals.count == 1, let renewal = renewals.first {
                return .selected(renewal)
            }
        }

        if eligible.count == 1, let certificate = eligible.first {
            return .selected(certificate)
        }
        return .pickerRequired
    }
}

protocol CertificateDefaultStoring: Sendable {
    func `default`(for tokenKey: String) -> RememberedCertificateDefault?
    var rememberedTokens: [RememberedSigningToken] { get }
    func remember(_ token: SigningToken)
    func saveDefault(for token: SigningToken, certificate: SigningCertificate)
    func clearDefault(for tokenKey: String)
    func forgetToken(for tokenKey: String)
}

final class UserDefaultsCertificateDefaultStore: CertificateDefaultStoring, @unchecked Sendable {
    static let storageKey = "certificateDefaults"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func `default`(for tokenKey: String) -> RememberedCertificateDefault? {
        lock.withLock { savedTokens()[tokenKey]?.certificateDefault }
    }

    var rememberedTokens: [RememberedSigningToken] {
        lock.withLock {
            savedTokens().values.sorted {
                let providerOrder = $0.providerName.localizedCaseInsensitiveCompare($1.providerName)
                return providerOrder == .orderedSame ? $0.tokenKey < $1.tokenKey : providerOrder == .orderedAscending
            }
        }
    }

    func remember(_ token: SigningToken) {
        lock.withLock {
            var tokensByKey = savedTokens()
            let existingDefault = tokensByKey[token.tokenKey]?.certificateDefault
            tokensByKey[token.tokenKey] = RememberedSigningToken(
                tokenKey: token.tokenKey,
                providerName: token.providerName,
                certificateDefault: existingDefault
            )
            save(tokensByKey)
        }
    }

    func saveDefault(for token: SigningToken, certificate: SigningCertificate) {
        let remembered = RememberedCertificateDefault(
            tokenKey: token.tokenKey,
            providerName: token.providerName,
            certificateKey: certificate.certificateKey,
            holderKey: certificate.holderKey,
            commonName: certificate.displayName,
            issuer: certificate.issuer,
            validUntil: certificate.validUntil
        )
        lock.withLock {
            var tokensByKey = savedTokens()
            tokensByKey[token.tokenKey] = RememberedSigningToken(
                tokenKey: token.tokenKey,
                providerName: token.providerName,
                certificateDefault: remembered
            )
            save(tokensByKey)
        }
    }

    func clearDefault(for tokenKey: String) {
        lock.withLock {
            var tokensByKey = savedTokens()
            guard var remembered = tokensByKey[tokenKey] else { return }
            remembered.certificateDefault = nil
            tokensByKey[tokenKey] = remembered
            save(tokensByKey)
        }
    }

    func forgetToken(for tokenKey: String) {
        lock.withLock {
            var tokensByKey = savedTokens()
            tokensByKey.removeValue(forKey: tokenKey)
            save(tokensByKey)
        }
    }

    private func savedTokens() -> [String: RememberedSigningToken] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [:] }
        if let tokens = try? JSONDecoder().decode([String: RememberedSigningToken].self, from: data) {
            return tokens
        }
        guard let legacyDefaults = try? JSONDecoder().decode([String: RememberedCertificateDefault].self, from: data) else {
            return [:]
        }
        return legacyDefaults.mapValues {
            RememberedSigningToken(
                tokenKey: $0.tokenKey,
                providerName: $0.providerName,
                certificateDefault: $0
            )
        }
    }

    private func save(_ tokensByKey: [String: RememberedSigningToken]) {
        defaults.set(try? JSONEncoder().encode(tokensByKey), forKey: Self.storageKey)
    }
}
