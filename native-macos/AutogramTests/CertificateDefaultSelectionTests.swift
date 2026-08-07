import Foundation
import Testing
@testable import Autogram

@Test func certificateDefaultSelectionUsesTheRequiredOrderAndStoresOnlyPublicMetadata() throws {
    let now = ISO8601DateFormatter().date(from: "2026-08-07T12:00:00Z")!
    let exact = certificate(key: "exact", holder: "holder-a")
    let renewal = certificate(key: "renewal", holder: "holder-a")
    let other = certificate(key: "other", holder: "holder-b")
    let remembered = RememberedCertificateDefault(
        tokenKey: "v1:token",
        providerName: "Qualified Provider",
        certificateKey: "exact",
        holderKey: "holder-a",
        commonName: "Jane Doe",
        issuer: "Qualified Issuer",
        validUntil: exact.validUntil
    )

    #expect(CertificateDefaultSelector.select(
        from: CertificateDiscovery(token: token, certificates: [exact, other]),
        remembered: remembered,
        now: now
    ) == .selected(exact))
    #expect(CertificateDefaultSelector.select(
        from: CertificateDiscovery(token: token, certificates: [renewal, other]),
        remembered: remembered,
        now: now
    ) == .selected(renewal))
    #expect(CertificateDefaultSelector.select(
        from: CertificateDiscovery(token: token, certificates: [expiredCertificate(key: "exact", holder: "holder-a"), renewal, other]),
        remembered: remembered,
        now: now
    ) == .selected(renewal))
    #expect(CertificateDefaultSelector.select(
        from: CertificateDiscovery(token: token, certificates: [notYetValidCertificate(key: "exact", holder: "holder-a"), renewal, other]),
        remembered: remembered,
        now: now
    ) == .pickerRequired)
    #expect(CertificateDefaultSelector.select(
        from: CertificateDiscovery(token: token, certificates: [renewal, certificate(key: "renewal-2", holder: "holder-a")]),
        remembered: remembered,
        now: now
    ) == .pickerRequired)
    #expect(CertificateDefaultSelector.select(
        from: CertificateDiscovery(token: token, certificates: [other]),
        remembered: nil,
        now: now
    ) == .selected(other))
    #expect(CertificateDefaultSelector.select(
        from: CertificateDiscovery(token: token, certificates: [exact, other]),
        remembered: nil,
        now: now
    ) == .pickerRequired)

    let suiteName = "CertificateDefaultSelectionTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsCertificateDefaultStore(defaults: defaults)
    store.saveDefault(for: token, certificate: exact)

    let stored = try #require(store.default(for: token.tokenKey))
    #expect(stored.certificateKey == "exact")
    #expect(stored.commonName == "Jane Doe")
    let persisted = try #require(defaults.data(forKey: UserDefaultsCertificateDefaultStore.storageKey))
    let persistedText = String(decoding: persisted, as: UTF8.self)
    #expect(!persistedText.contains("transient-serial"))
    #expect(!persistedText.localizedCaseInsensitiveContains("pin"))
    #expect(!persistedText.contains("CN=Jane Doe"))
}

private let token = SigningToken(tokenKey: "v1:token", providerName: "Qualified Provider")

private func certificate(key: String, holder: String) -> SigningCertificate {
    SigningCertificate(
        serialNumber: "transient-serial",
        displayName: "Jane Doe",
        issuer: "Qualified Issuer",
        validFrom: ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z")!,
        validUntil: ISO8601DateFormatter().date(from: "2027-01-01T00:00:00Z")!,
        certificateKey: key,
        holderKey: holder
    )
}

private func expiredCertificate(key: String, holder: String) -> SigningCertificate {
    SigningCertificate(
        serialNumber: "transient-serial",
        displayName: "Jane Doe",
        issuer: "Qualified Issuer",
        validFrom: ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")!,
        validUntil: ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z")!,
        certificateKey: key,
        holderKey: holder
    )
}

private func notYetValidCertificate(key: String, holder: String) -> SigningCertificate {
    SigningCertificate(
        serialNumber: "transient-serial",
        displayName: "Jane Doe",
        issuer: "Qualified Issuer",
        validFrom: ISO8601DateFormatter().date(from: "2027-01-01T00:00:00Z")!,
        validUntil: ISO8601DateFormatter().date(from: "2028-01-01T00:00:00Z")!,
        certificateKey: key,
        holderKey: holder
    )
}
