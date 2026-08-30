import Foundation
import Security

public enum EZZKTokenStoreError: Error, Equatable, Sendable {
    case keychainFailure(status: Int32)
    case malformedData
    case encodingFailure
}

public enum EZZKKeychainAdapterError: Error, Equatable, Sendable {
    case status(Int32)
}

public protocol EZZKKeychainAdapter: Sendable {
    func read(service: String, account: String) throws -> Data?
    func write(_ data: Data, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

public struct EZZKTokenStore: EZZKTokenStoring, Sendable {
    static let keychainService = "sk.autogram.Autogram.ezzk.oauth.tokens"

    private let adapter: any EZZKKeychainAdapter

    public init() {
        self.adapter = SystemEZZKKeychainAdapter()
    }

    public init(adapter: any EZZKKeychainAdapter) {
        self.adapter = adapter
    }

    public func load(environment: EZZKEnvironment) throws -> EZZKTokenSet? {
        let data: Data?
        do {
            data = try adapter.read(service: Self.keychainService, account: account(for: environment))
        } catch {
            throw mapKeychainError(error)
        }

        guard let data else { return nil }
        do {
            return try JSONDecoder().decode(EZZKTokenSet.self, from: data)
        } catch {
            throw EZZKTokenStoreError.malformedData
        }
    }

    public func save(_ tokenSet: EZZKTokenSet, environment: EZZKEnvironment) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(tokenSet)
        } catch {
            throw EZZKTokenStoreError.encodingFailure
        }

        do {
            try adapter.write(data, service: Self.keychainService, account: account(for: environment))
        } catch {
            throw mapKeychainError(error)
        }
    }

    public func delete(environment: EZZKEnvironment) throws {
        do {
            try adapter.delete(service: Self.keychainService, account: account(for: environment))
        } catch {
            throw mapKeychainError(error)
        }
    }

    private func account(for environment: EZZKEnvironment) -> String {
        "ezzk.oauth.\(environment.rawValue)"
    }

    private func mapKeychainError(_ error: Error) -> EZZKTokenStoreError {
        if case let EZZKKeychainAdapterError.status(status) = error {
            return .keychainFailure(status: status)
        }
        return .keychainFailure(status: Int32(errSecInternalComponent))
    }
}

private struct SystemEZZKKeychainAdapter: EZZKKeychainAdapter {
    func read(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw EZZKKeychainAdapterError.status(Int32(status))
        }
        guard let data = result as? Data else {
            throw EZZKKeychainAdapterError.status(Int32(errSecDecode))
        }
        return data
    }

    func write(_ data: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var item = query
            item.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw EZZKKeychainAdapterError.status(Int32(addStatus))
            }
        } else if updateStatus != errSecSuccess {
            throw EZZKKeychainAdapterError.status(Int32(updateStatus))
        }
    }

    func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw EZZKKeychainAdapterError.status(Int32(status))
        }
    }
}
