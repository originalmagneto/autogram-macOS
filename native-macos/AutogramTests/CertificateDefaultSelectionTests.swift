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

@Test func clearingDefaultRetainsTheRememberedTokenUntilItIsForgotten() throws {
    let suiteName = "CertificateDefaultSelectionTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsCertificateDefaultStore(defaults: defaults)
    let selected = certificate(key: "exact", holder: "holder-a")

    store.saveDefault(for: token, certificate: selected)
    store.clearDefault(for: token.tokenKey)

    #expect(store.rememberedTokens == [
        RememberedSigningToken(tokenKey: token.tokenKey, providerName: token.providerName, certificateDefault: nil)
    ])

    store.forgetToken(for: token.tokenKey)

    #expect(store.rememberedTokens.isEmpty)
}

@Test @MainActor func workspaceAutomaticallyStartsSigningWithAnExactRememberedDefault() async {
    let defaultToken = SigningToken(tokenKey: "workspace-auto-selection", providerName: "Test Provider")
    let selected = certificate(key: "selected", holder: "holder-a")
    let alternative = certificate(key: "alternative", holder: "holder-b")
    let suiteName = "CertificateDefaultSelectionTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsCertificateDefaultStore(defaults: defaults)
    store.saveDefault(for: defaultToken, certificate: selected)

    let workspace = WorkspaceModel(
        engine: CertificateDiscoveryEngine(
            discovery: CertificateDiscovery(token: defaultToken, certificates: [selected, alternative])
        ),
        certificateDefaultStore: store
    )
    await workspace.refreshSigningEnvironment()

    let resolution = await workspace.resolveCertificates(using: PINSubmission(
        certificatePIN: Secret("1234"),
        signingPIN: Secret("1234")
    ))

    #expect(resolution == .signingStarted)
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

private struct CertificateDiscoveryEngine: SigningEngine {
    let discovery: CertificateDiscovery

    func capabilities() async throws -> EngineCapabilities {
        EngineCapabilities(protocolVersion: 1, supportsQualifiedTimestamp: true)
    }

    func drivers() async throws -> [SigningDriver] {
        [SigningDriver(id: "test-driver", displayName: "Test Driver", tokenPresent: true)]
    }

    func certificates(driverID: String, pin: Secret?) async throws -> [SigningCertificate] {
        throw SigningFailure.engine("Certificate discovery must be used for default selection.")
    }

    func certificateDiscovery(driverID: String, pin: Secret?) async throws -> CertificateDiscovery {
        discovery
    }

    func inspect(files: [PDFItemDescriptor]) async throws -> [PDFInspection] { [] }

    func sign(request: SigningRequest) -> AsyncThrowingStream<SigningEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func cancel() async {}
}
