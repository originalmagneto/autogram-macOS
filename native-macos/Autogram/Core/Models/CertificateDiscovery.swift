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
    func saveDefault(for token: SigningToken, certificate: SigningCertificate)
    func clearDefault(for tokenKey: String)
}

final class UserDefaultsCertificateDefaultStore: CertificateDefaultStoring, @unchecked Sendable {
    static let storageKey = "certificateDefaults"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func `default`(for tokenKey: String) -> RememberedCertificateDefault? {
        lock.withLock { savedDefaults()[tokenKey] }
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
            var defaultsByToken = savedDefaults()
            defaultsByToken[token.tokenKey] = remembered
            save(defaultsByToken)
        }
    }

    func clearDefault(for tokenKey: String) {
        lock.withLock {
            var defaultsByToken = savedDefaults()
            defaultsByToken.removeValue(forKey: tokenKey)
            save(defaultsByToken)
        }
    }

    private func savedDefaults() -> [String: RememberedCertificateDefault] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: RememberedCertificateDefault].self, from: data)) ?? [:]
    }

    private func save(_ defaultsByToken: [String: RememberedCertificateDefault]) {
        defaults.set(try? JSONEncoder().encode(defaultsByToken), forKey: Self.storageKey)
    }
}
