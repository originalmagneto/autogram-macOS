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
    private(set) var lastConnectivityCheck: Date?
    private var environment: EZZKEnvironment = .sandbox
    private let oauthConfiguration: EZZKOAuthConfiguration?
    private let tokenStore: any EZZKTokenStoring
    private let transport: any EZZKHTTPTransport
    private let authenticationSession: any EZZKAuthenticationSessionRunning
    private let demoMode: Bool
    private let demoService = MockEZZKService()
    private let unavailableService = UnavailableEZZKService()
    private var client: EZZKClient?
    private var activeService: EZZKClientServiceAdapter?
    private var operationGeneration: UInt64 = 0
    private var restorationTask: Task<Void, Never>?

    var selectedEnvironment: EZZKEnvironment {
        get { environment }
        set {
            guard newValue != .production || Self.productionAuthorityGate else { return }
            guard client == nil || newValue == environment else { return }
            environment = newValue
        }
    }

    var service: any EZZKServicing {
        if demoMode { return demoService }
        return activeService ?? unavailableService
    }

    var canSelectProduction: Bool { Self.productionAuthorityGate }

    var canChangeEnvironment: Bool {
        client == nil && state != .authenticating
    }
    var hasNativeCallbackConfiguration: Bool {
        oauthConfiguration?.isNativeCallbackConfigured == true
    }

    var hasAuthenticationCallbackConfiguration: Bool {
        oauthConfiguration?.isAuthenticationCallbackConfigured == true
    }
    var isDemoMode: Bool { demoMode }

    var canStartLogin: Bool {
        !demoMode &&
        state != .authenticating &&
        client == nil &&
        isEnvironmentAvailable &&
        oauthConfiguration.map(isUsableForLogin) == true
    }

    var canRefresh: Bool {
        !demoMode &&
        state != .authenticating &&
        isEnvironmentAvailable &&
        oauthConfiguration.map(isUsableForClient) == true
    }

    var hasActiveSession: Bool {
        if case .authenticated = state { return true }
        return false
    }

    var availableEvidenceNumberCount: Int? {
        guard case let .authenticated(_, count) = state else { return nil }
        return count
    }


    init(
        oauthConfiguration: EZZKOAuthConfiguration? = try? EZZKOAuthConfiguration(),
        tokenStore: any EZZKTokenStoring = EZZKTokenStore(),
        transport: any EZZKHTTPTransport = URLSessionEZZKHTTPTransport(),
        authenticationSession: any EZZKAuthenticationSessionRunning = EZZKAuthenticationSession(),
        demoMode: Bool = false
    ) {
        self.oauthConfiguration = oauthConfiguration
        self.tokenStore = tokenStore
        self.transport = transport
        self.authenticationSession = authenticationSession
        self.demoMode = demoMode
        let restorationGeneration = beginOperation()
        restorationTask = Task { [weak self] in
            await self?.restoreFromKeychain(generation: restorationGeneration)
        }
    }

    func login() async {
        cancelInitialRestore()
        guard state != .authenticating else { return }
        guard !demoMode, client == nil else { return }
        guard isEnvironmentAvailable else {
            state = .failed("Produkčné pripojenie EZZK ešte nie je povolené.")
            return
        }
        guard let oauthConfiguration, isUsableForLogin(oauthConfiguration) else {
            state = .failed("Prihlásenie do EZZK nie je dostupné. Vyžaduje sa potvrdené natívne presmerovanie.")
            return
        }

        let generation = beginOperation()
        state = .authenticating
        do {
            let tokenSet = try await authenticationSession.authenticate(configuration: oauthConfiguration)
            guard isCurrent(generation) else { return }
            try tokenStore.save(tokenSet, environment: environment)
            guard isCurrent(generation) else { return }
            let candidate = makeClient(oauthConfiguration: oauthConfiguration)
            let available = try await candidate.availableEvidenceNumbers()
            guard isCurrent(generation) else { return }
            guard publishAuthenticated(
                candidate,
                availableEvidenceNumberCount: available.availableEvidenceNumbers.count,
                generation: generation) else { return }
        } catch {
            guard isCurrent(generation), client == nil else { return }
            state = .failed(message(for: error))
        }
    }
    func cancelLogin() {
        guard state == .authenticating else { return }
        authenticationSession.cancelAuthentication()
        invalidateOperations()
        client = nil
        activeService = nil
        state = .signedOut
    }

    func logout() {
        invalidateOperations()
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
        cancelInitialRestore()
        guard !demoMode else {
            state = .failed("Relácia EZZK nie je v demo režime dostupná.")
            return
        }
        guard isEnvironmentAvailable else {
            client = nil
            activeService = nil
            state = .failed("Produkčné pripojenie EZZK ešte nie je povolené.")
            return
        }
        guard let oauthConfiguration, isUsableForClient(oauthConfiguration) else {
            state = .failed("Obnovenie relácie EZZK nie je dostupné bez platnej konfigurácie.")
            return
        }

        if !hasActiveSession {
            await login()
            return
        }

        let generation = beginOperation()
        state = .authenticating
        do {
            let candidate = client ?? makeClient(oauthConfiguration: oauthConfiguration)
            let available = try await candidate.availableEvidenceNumbers()
            guard isCurrent(generation) else { return }
            guard publishAuthenticated(
                candidate,
                availableEvidenceNumberCount: available.availableEvidenceNumbers.count,
                generation: generation) else { return }
        } catch {
            guard isCurrent(generation) else { return }
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
        guard !demoMode else {
            state = .failed("Test pripojenia EZZK nie je v demo režime dostupný.")
            return
        }
        guard isEnvironmentAvailable else {
            state = .failed("Produkčné pripojenie EZZK ešte nie je povolené.")
            return
        }
        guard let oauthConfiguration, isUsableForClient(oauthConfiguration) else {
            state = .failed("Test pripojenia EZZK nie je dostupný bez platnej konfigurácie.")
            return
        }

        let generation = beginOperation()
        do {
            let candidate = client ?? makeClient(oauthConfiguration: oauthConfiguration)
            let available = try await candidate.availableEvidenceNumbers()
            guard isCurrent(generation) else { return }
            guard publishAuthenticated(
                candidate,
                availableEvidenceNumberCount: available.availableEvidenceNumbers.count,
                generation: generation) else { return }
        } catch {
            guard isCurrent(generation) else { return }
            if isAuthenticationFailure(error) {
                client = nil
                activeService = nil
                try? tokenStore.delete(environment: environment)
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
        guard !demoMode, let client else {
            state = .failed("Najprv sa prihláste do EZZK.")
            return
        }

        let generation = beginOperation()
        do {
            let numbers = try await client.requestEvidenceNumbers(count: count)
            guard isCurrent(generation) else { return }
            state = .authenticated(environment: environment, availableEvidenceNumbers: numbers.count)
        } catch {
            guard isCurrent(generation) else { return }
            if isAuthenticationFailure(error) {
                self.client = nil
                activeService = nil
                try? tokenStore.delete(environment: environment)
                state = .expired
            } else {
                state = .failed(message(for: error))
            }
        }
    }

    private func restoreFromKeychain(generation: UInt64) async {
        guard !demoMode,
              isEnvironmentAvailable,
              let oauthConfiguration,
              isUsableForClient(oauthConfiguration),
              isCurrent(generation) else {
            return
        }
        do {
            guard try tokenStore.load(environment: environment) != nil else { return }
            guard isCurrent(generation) else { return }
            state = .authenticating
            let candidate = makeClient(oauthConfiguration: oauthConfiguration)
            let available = try await candidate.availableEvidenceNumbers()
            guard isCurrent(generation) else { return }
            guard publishAuthenticated(
                candidate,
                availableEvidenceNumberCount: available.availableEvidenceNumbers.count,
                generation: generation) else { return }
        } catch {
            guard isCurrent(generation), client == nil else { return }
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
        availableEvidenceNumberCount: Int,
        generation: UInt64
    ) -> Bool {
        guard isCurrent(generation) else { return false }
        if let client, client !== candidate { return false }
        if client == nil {
            client = candidate
            activeService = EZZKClientServiceAdapter(client: candidate)
        }
        state = .authenticated(
            environment: environment,
            availableEvidenceNumbers: availableEvidenceNumberCount)
        lastConnectivityCheck = Date()
        return true
    }

    private func makeClient(oauthConfiguration: EZZKOAuthConfiguration) -> EZZKClient {
        EZZKClient(
            environment: environment,
            oauth: oauthConfiguration,
            tokenStore: tokenStore,
            transport: transport)
    }
    private func cancelInitialRestore() {
        guard restorationTask != nil else { return }
        restorationTask?.cancel()
        restorationTask = nil
        invalidateOperations()
        if client == nil, state == .authenticating {
            state = .signedOut
        }
    }


    private func beginOperation() -> UInt64 {
        operationGeneration &+= 1
        return operationGeneration
    }

    private func invalidateOperations() {
        operationGeneration &+= 1
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        operationGeneration == generation
    }

    private var isEnvironmentAvailable: Bool {
        environment != .production || Self.productionAuthorityGate
    }

    private func isUsableForClient(_ oauthConfiguration: EZZKOAuthConfiguration) -> Bool {
        !oauthConfiguration.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !oauthConfiguration.scopes.isEmpty &&
        oauthConfiguration.scopes.allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func isUsableForLogin(_ oauthConfiguration: EZZKOAuthConfiguration) -> Bool {
        isUsableForClient(oauthConfiguration) && oauthConfiguration.isAuthenticationCallbackConfigured
    }

    private func isAuthenticationFailure(_ error: Error) -> Bool {
        if let error = error as? EZZKError {
            return error == .authenticationFailed
        }
        return error is EZZKAuthenticationError
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

private struct UnavailableEZZKService: EZZKServicing, Sendable {
    func serverTime() async throws -> Date {
        throw EZZKError.notConfigured
    }

    func requestEvidenceNumbers(count: Int) async throws -> [String] {
        throw EZZKError.notConfigured
    }

    func submit(_ envelope: ConversionRecordEnvelope) async throws {
        throw EZZKError.notConfigured
    }
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
