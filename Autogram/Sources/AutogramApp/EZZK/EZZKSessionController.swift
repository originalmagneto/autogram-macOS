import AutogramKit
import Foundation
import Observation

@MainActor
@Observable
final class EZZKSessionController {
    enum State: Equatable, Sendable {
        case signedOut
        case authenticating
        case authenticated(environment: EZZKEnvironment, availableEvidenceNumbers: Int)
        case expired
        case failed(String)
    }

    private(set) var state: State = .signedOut
    private var environment: EZZKEnvironment = .sandbox
    private let oauthConfiguration: EZZKOAuthConfiguration?
    private let tokenStore: any EZZKTokenStoring
    private let transport: any EZZKHTTPTransport
    private let authenticationSession: any EZZKAuthenticationSessionRunning
    private let demoService = MockEZZKService()
    private var client: EZZKClient?
    private var activeService: EZZKClientServiceAdapter?

    var selectedEnvironment: EZZKEnvironment {
        get { environment }
        set {
            guard newValue != .production || Self.productionAuthorityGate else { return }
            guard client == nil || newValue == environment else { return }
            environment = newValue
        }
    }

    var service: any EZZKServicing {
        activeService ?? demoService
    }

    var canSelectProduction: Bool { Self.productionAuthorityGate }

    init(
        oauthConfiguration: EZZKOAuthConfiguration? = try? EZZKOAuthConfiguration(),
        tokenStore: any EZZKTokenStoring = EZZKTokenStore(),
        transport: any EZZKHTTPTransport = URLSessionEZZKHTTPTransport(),
        authenticationSession: any EZZKAuthenticationSessionRunning = EZZKAuthenticationSession()
    ) {
        self.oauthConfiguration = oauthConfiguration
        self.tokenStore = tokenStore
        self.transport = transport
        self.authenticationSession = authenticationSession

        Task { [weak self] in
            await self?.restoreFromKeychain()
        }
    }

    func login() async {
        guard client == nil else { return }
        guard isEnvironmentAvailable else {
            state = .failed("Produkčné pripojenie EZZK ešte nie je povolené.")
            return
        }
        guard let oauthConfiguration, isUsable(oauthConfiguration) else {
            state = .failed("Prihlásenie do EZZK nie je dostupné. Vyžaduje sa potvrdené natívne presmerovanie.")
            return
        }

        state = .authenticating
        do {
            let tokenSet = try await authenticationSession.authenticate(configuration: oauthConfiguration)
            try tokenStore.save(tokenSet, environment: environment)
            let candidate = makeClient(oauthConfiguration: oauthConfiguration)
            let available = try await candidate.availableEvidenceNumbers()
            guard publishAuthenticated(
                candidate,
                availableEvidenceNumberCount: available.availableEvidenceNumbers.count) else { return }
        } catch {
            guard client == nil else { return }
            state = .failed(message(for: error))
        }
    }

    func logout() {
        client = nil
        activeService = nil
        do {
            try tokenStore.delete(environment: environment)
            state = .signedOut
        } catch {
            state = .failed("Odhlásenie z EZZK sa nepodarilo dokončiť.")
        }
    }

    func refresh() async {
        guard isEnvironmentAvailable else {
            client = nil
            activeService = nil
            state = .failed("Produkčné pripojenie EZZK ešte nie je povolené.")
            return
        }
        guard let oauthConfiguration, isUsable(oauthConfiguration) else {
            state = .failed("Obnovenie relácie EZZK nie je dostupné bez potvrdeného natívneho presmerovania.")
            return
        }

        state = .authenticating
        do {
            let candidate = client ?? makeClient(oauthConfiguration: oauthConfiguration)
            let available = try await candidate.availableEvidenceNumbers()
            guard publishAuthenticated(
                candidate,
                availableEvidenceNumberCount: available.availableEvidenceNumbers.count) else { return }
        } catch {
            client = nil
            activeService = nil
            if isAuthenticationFailure(error) {
                try? tokenStore.delete(environment: environment)
                state = .expired
            } else {
                state = .failed(message(for: error))
            }
        }
    }

    func testConnection() async {
        guard isEnvironmentAvailable else {
            state = .failed("Produkčné pripojenie EZZK ešte nie je povolené.")
            return
        }
        guard let oauthConfiguration, isUsable(oauthConfiguration) else {
            state = .failed("Test pripojenia EZZK nie je dostupný bez potvrdeného natívneho presmerovania.")
            return
        }

        do {
            let candidate = client ?? makeClient(oauthConfiguration: oauthConfiguration)
            let available = try await candidate.availableEvidenceNumbers()
            guard publishAuthenticated(
                candidate,
                availableEvidenceNumberCount: available.availableEvidenceNumbers.count) else { return }
        } catch {
            if client == nil, isAuthenticationFailure(error) {
                state = .expired
            } else {
                state = .failed(message(for: error))
            }
        }
    }

    func requestEvidenceNumbers(count: Int) async {
        guard count > 0 else {
            state = .failed("Počet evidenčných čísel musí byť kladný.")
            return
        }
        guard let client else {
            state = .failed("Najprv sa prihláste do EZZK.")
            return
        }

        do {
            let numbers = try await client.requestEvidenceNumbers(count: count)
            state = .authenticated(environment: environment, availableEvidenceNumbers: numbers.count)
        } catch {
            state = .failed(message(for: error))
        }
    }

    private func restoreFromKeychain() async {
        guard isEnvironmentAvailable,
              let oauthConfiguration,
              isUsable(oauthConfiguration) else {
            return
        }
        do {
            guard try tokenStore.load(environment: environment) != nil else { return }
            state = .authenticating
            let candidate = makeClient(oauthConfiguration: oauthConfiguration)
            let available = try await candidate.availableEvidenceNumbers()
            guard publishAuthenticated(
                candidate,
                availableEvidenceNumberCount: available.availableEvidenceNumbers.count) else { return }
        } catch {
            guard client == nil else { return }
            if isAuthenticationFailure(error) {
                state = .expired
            } else {
                state = .failed(message(for: error))
            }
        }
    }

    @discardableResult
    private func publishAuthenticated(
        _ candidate: EZZKClient,
        availableEvidenceNumberCount: Int
    ) -> Bool {
        if let client, client !== candidate { return false }
        if client == nil {
            client = candidate
            activeService = EZZKClientServiceAdapter(client: candidate)
        }
        state = .authenticated(
            environment: environment,
            availableEvidenceNumbers: availableEvidenceNumberCount)
        return true
    }

    private func makeClient(oauthConfiguration: EZZKOAuthConfiguration) -> EZZKClient {
        EZZKClient(
            environment: environment,
            oauth: oauthConfiguration,
            tokenStore: tokenStore,
            transport: transport)
    }

    private var isEnvironmentAvailable: Bool {
        environment != .production || Self.productionAuthorityGate
    }

    private func isAuthenticationFailure(_ error: Error) -> Bool {
        if let error = error as? EZZKError {
            return error == .authenticationFailed
        }
        return error is EZZKAuthenticationError
    }

    private func isUsable(_ oauthConfiguration: EZZKOAuthConfiguration) -> Bool {
        !oauthConfiguration.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !oauthConfiguration.scopes.isEmpty &&
        oauthConfiguration.scopes.allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } &&
        oauthConfiguration.isNativeCallbackConfigured
    }

    private func message(for error: Error) -> String {
        if let error = error as? EZZKAuthenticationError {
            switch error {
            case .nativeCallbackNotConfigured:
                return "Prihlásenie do EZZK nie je dostupné. Vyžaduje sa potvrdené natívne presmerovanie."
            case .cancelled:
                return "Prihlásenie do EZZK bolo zrušené."
            case .authenticationInProgress:
                return "Prihlásenie do EZZK už prebieha."
            case .discoveryFailed, .issuerMismatch, .insecureEndpoint, .invalidAuthorizationEndpoint:
                return "Konfigurácia prihlasovania EZZK je neplatná."
            case .sessionUnavailable:
                return "Prihlasovacia relácia EZZK nie je dostupná."
            case .callback, .tokenExchangeFailed, .malformedTokenResponse, .authenticationFailed:
                return "Prihlásenie do EZZK zlyhalo."
            }
        }
        if let error = error as? EZZKError {
            switch error {
            case .notConfigured:
                return "EZZK nie je nakonfigurované."
            case .authenticationFailed:
                return "Relácia EZZK vypršala. Prihláste sa znova."
            case .invalidResponse:
                return "EZZK vrátilo neplatnú odpoveď."
            case .serverRejected:
                return "EZZK zamietlo operáciu."
            case .networkFailure:
                return "Spojenie s EZZK zlyhalo."
            }
        }
        if error is EZZKTokenStoreError {
            return "Bezpečné úložisko EZZK nie je dostupné."
        }
        return "Operácia EZZK sa nepodarila."
    }

    private static let productionAuthorityGate = false
}

private final class EZZKClientServiceAdapter: EZZKServicing, @unchecked Sendable {
    private let client: EZZKClient

    init(client: EZZKClient) {
        self.client = client
    }

    func serverTime() async throws -> Date {
        try await client.serverTime()
    }

    func requestEvidenceNumbers(count: Int) async throws -> [String] {
        try await client.requestEvidenceNumbers(count: count)
    }

    func submit(_ envelope: ConversionRecordEnvelope) async throws {
        throw EZZKError.notConfigured
    }
}
