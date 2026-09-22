import Chevron7Identity
import Foundation
import Security

public struct EZZKSOAPCredentials: Codable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public var login: String
    public var password: String

    public init(login: String, password: String) {
        self.login = login
        self.password = password
    }

    public var description: String { "EZZKSOAPCredentials(login: \(login), password: <redacted>)" }
    public var debugDescription: String { description }
}

public protocol EZZKSOAPCredentialStoring: Sendable {
    func load(environment: EZZKEnvironment) throws -> EZZKSOAPCredentials?
    func save(_ credentials: EZZKSOAPCredentials, environment: EZZKEnvironment) throws
    func delete(environment: EZZKEnvironment) throws
}

/// The advocate's EZZK name and password, one Keychain item per environment.
public struct EZZKSOAPCredentialStore: EZZKSOAPCredentialStoring {
    static let keychainService = "\(ProductIdentity.bundleIdentifier).ezzk.soap"

    private let adapter: any EZZKKeychainAdapter

    public init() {
        self.adapter = SystemEZZKKeychainAdapter()
    }

    public init(adapter: any EZZKKeychainAdapter) {
        self.adapter = adapter
    }

    static func account(for environment: EZZKEnvironment) -> String {
        switch environment {
        case .sandbox: "test"
        case .production: "production"
        }
    }

    public func load(environment: EZZKEnvironment) throws -> EZZKSOAPCredentials? {
        let data: Data?
        do {
            data = try adapter.read(service: Self.keychainService, account: Self.account(for: environment))
        } catch {
            throw EZZKTokenStoreError.keychainFailure(status: Self.status(of: error))
        }
        guard let data else { return nil }
        guard let credentials = try? JSONDecoder().decode(EZZKSOAPCredentials.self, from: data) else {
            throw EZZKTokenStoreError.malformedData
        }
        return credentials
    }

    public func save(_ credentials: EZZKSOAPCredentials, environment: EZZKEnvironment) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(credentials)
        } catch {
            throw EZZKTokenStoreError.encodingFailure
        }
        do {
            try adapter.write(data, service: Self.keychainService, account: Self.account(for: environment))
        } catch {
            throw EZZKTokenStoreError.keychainFailure(status: Self.status(of: error))
        }
    }

    public func delete(environment: EZZKEnvironment) throws {
        do {
            try adapter.delete(service: Self.keychainService, account: Self.account(for: environment))
        } catch {
            throw EZZKTokenStoreError.keychainFailure(status: Self.status(of: error))
        }
    }

    private static func status(of error: Error) -> Int32 {
        if case let EZZKKeychainAdapterError.status(status) = error {
            return status
        }
        return Int32(errSecInternalComponent)
    }
}
