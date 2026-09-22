import Chevron7Kit
import Foundation
import Observation

/// EZZK access for Settings, ZaKo and the Register konverzií: the selected mode, the
/// advocate's verified SOAP login, and the service ZaKo calls.
@MainActor
@Observable
final class EZZKAccountController {
    enum State: Equatable {
        case signedOut
        case verifying
        case signedIn(accountName: String, checkedAt: Date)
        case failed(String)
    }

    private(set) var state: State = .signedOut
    private(set) var mode: AppSettings.EZZKMode
    /// Login name saved for the current environment. Never the password.
    private(set) var storedLogin = ""

    private let credentialStore: any EZZKSOAPCredentialStoring
    private let transportFactory: @Sendable (EZZKEnvironment) -> any EZZKHTTPTransport
    @ObservationIgnored private var personProvider: @MainActor () -> EZZKPerson = {
        EZZKPerson(corporateBodyFullName: "", ico: "")
    }
    @ObservationIgnored private var usedEvidenceNumbersProvider: @MainActor () -> Set<String> = { [] }
    private let demoService = MockEZZKService()
    /// Clients read the password from the credential store for each login.
    @ObservationIgnored private var clients: [EZZKEnvironment: EZZKSOAPClient] = [:]
    /// One transport (and so one URLSession) per environment for the controller's lifetime.
    @ObservationIgnored private var transports: [EZZKEnvironment: any EZZKHTTPTransport] = [:]
    @ObservationIgnored private var generation: UInt64 = 0

    init(mode: AppSettings.EZZKMode,
         credentialStore: any EZZKSOAPCredentialStoring = EZZKSOAPCredentialStore(),
         transportFactory: @escaping @Sendable (EZZKEnvironment) -> any EZZKHTTPTransport = {
             URLSessionEZZKSOAPTransport(environment: $0)
         }) {
        self.mode = mode
        self.credentialStore = credentialStore
        self.transportFactory = transportFactory
        reloadStoredLogin()
    }

    /// Settings owns the person and the evidence store, and exists only after this controller.
    func configure(person: @escaping @MainActor () -> EZZKPerson,
                   usedEvidenceNumbers: @escaping @MainActor () -> Set<String>) {
        personProvider = person
        usedEvidenceNumbersProvider = usedEvidenceNumbers
    }

    var isDemoMode: Bool { mode == .demo }
    var environment: EZZKEnvironment? { mode.environment }
    var hasStoredCredentials: Bool { !storedLogin.isEmpty }

    var service: any EZZKServicing {
        guard let environment else { return demoService }
        return EZZKSOAPServiceAdapter(client: client(for: environment), person: personProvider(),
                                      usedEvidenceNumbers: usedEvidenceNumbersProvider())
    }

    func setMode(_ newMode: AppSettings.EZZKMode) {
        guard newMode != mode else { return }
        generation &+= 1
        mode = newMode
        state = .signedOut
        reloadStoredLogin()
    }

    /// Verifies the name and password with EZZK and saves them only when EZZK accepts them.
    func signIn(login: String, password: String) async {
        guard let environment else { return }
        let login = login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !login.isEmpty, !password.isEmpty else {
            state = .failed("Zadajte prihlasovacie meno aj heslo.")
            return
        }
        generation &+= 1
        let operation = generation
        state = .verifying
        let candidate = EZZKSOAPCredentials(login: login, password: password)
        let verification = EZZKSOAPClient(environment: environment, transport: transport(for: environment),
                                          credentials: { candidate })
        do {
            let accountName = try await verification.logIn()
            guard operation == generation else { return }
            try credentialStore.save(candidate, environment: environment)
            // The verification client keeps the password in its closure; never cache it. The next
            // call builds a client that reads the saved item, at the cost of one more LogIn.
            clients[environment] = nil
            storedLogin = login
            state = .signedIn(accountName: accountName, checkedAt: Date())
        } catch {
            guard operation == generation else { return }
            state = .failed(Self.message(for: error))
        }
    }

    func signOut() {
        guard let environment else { return }
        generation &+= 1
        // Drop the live token first, even when the Keychain item cannot be deleted.
        clients[environment] = nil
        do {
            try credentialStore.delete(environment: environment)
        } catch {
            state = .failed(Self.message(for: error))
            return
        }
        storedLogin = ""
        state = .signedOut
    }

    func lookUp(evidenceNumber: String) async throws -> EZZKRecordLookup {
        guard let environment else { throw EZZKError.notConfigured }
        return try await client(for: environment)
            .publicRecord(evidenceNumber: evidenceNumber.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Raw list of the person's unconsumed numbers, for the test environment only.
    func requestTestNumbers() async throws -> [String] {
        guard mode == .test, let environment else { throw EZZKError.productionAllocationDisabled }
        return try await client(for: environment).evidenceNumbers(for: personProvider())
    }

    static func message(for error: Error) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    private func client(for environment: EZZKEnvironment) -> EZZKSOAPClient {
        if let client = clients[environment] { return client }
        let store = credentialStore
        let client = EZZKSOAPClient(environment: environment, transport: transport(for: environment),
                                    credentials: { try store.load(environment: environment) })
        clients[environment] = client
        return client
    }

    private func transport(for environment: EZZKEnvironment) -> any EZZKHTTPTransport {
        if let transport = transports[environment] { return transport }
        let transport = transportFactory(environment)
        transports[environment] = transport
        return transport
    }

    private func reloadStoredLogin() {
        guard let environment else {
            storedLogin = ""
            return
        }
        storedLogin = (try? credentialStore.load(environment: environment))?.login ?? ""
    }
}
