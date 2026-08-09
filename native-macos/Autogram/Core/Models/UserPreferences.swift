import Foundation
import Security

struct UserPreferences: Codable, Sendable, Equatable {
    var driverID: String?
    var certificateSerial: String?
    var outputPolicy: OutputPolicy
    var destinationBehavior: DestinationBehavior
    var revealInFinderAfterSigning: Bool
    var timestampSource: TimestampSourceConfiguration

    static let fixture = UserPreferences(
        driverID: "fixture-driver",
        certificateSerial: "fixture-certificate",
        outputPolicy: .signedSuffix,
        destinationBehavior: .besideSource,
        revealInFinderAfterSigning: true,
        timestampSource: .automatic
    )
}

enum TimestampSource: String, Codable, Sendable, CaseIterable, Identifiable {
    case automatic
    case sectigo
    case belgium
    case custom

    static let sectigoURL = "http://timestamp.sectigo.com/qualified"
    static let belgiumURL = "http://tsa.belgium.be/connect"

    var id: Self { self }

    var endpoints: [String] {
        switch self {
        case .automatic: [Self.sectigoURL, Self.belgiumURL]
        case .sectigo: [Self.sectigoURL]
        case .belgium: [Self.belgiumURL]
        case .custom: []
        }
    }

    var displayName: String {
        switch self {
        case .automatic: "Automatic, recommended"
        case .sectigo: "Sectigo Qualified TSA"
        case .belgium: "Belgium Qualified TSA"
        case .custom: "Custom Provider"
        }
    }
}

enum TimestampAuthenticationKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case none
    case basic
    case bearer

    var id: Self { self }
}

struct TimestampAuthenticationPreference: Codable, Sendable, Equatable {
    var kind: TimestampAuthenticationKind
    var username: String?

    static let none = TimestampAuthenticationPreference(kind: .none, username: nil)
}

struct CustomTimestampProviderConfiguration: Codable, Sendable, Equatable {
    var displayName: String
    var urls: [String]
    var authentication: TimestampAuthenticationPreference
    var credentialKey: UUID

    init(
        displayName: String = "",
        urls: [String] = [],
        authentication: TimestampAuthenticationPreference = .none,
        credentialKey: UUID = UUID()
    ) {
        self.displayName = displayName
        self.urls = urls
        self.authentication = authentication
        self.credentialKey = credentialKey
    }
}

struct TimestampSourceConfiguration: Codable, Sendable, Equatable {
    var source: TimestampSource
    var customProvider: CustomTimestampProviderConfiguration?

    static let automatic = TimestampSourceConfiguration(source: .automatic, customProvider: nil)

    var endpoints: [String] {
        switch source {
        case .custom:
            customProvider?.urls.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
        default:
            source.endpoints
        }
    }
}

protocol TimestampSourceProviding: Sendable {
    func load() -> TimestampSourceConfiguration
    func credential(for provider: CustomTimestampProviderConfiguration) throws -> Secret?
}

final class TimestampSourcePreferencesStore: TimestampSourceProviding, @unchecked Sendable {
    static let storageKey = "preferences.timestampSource"
    private static let keychainService = "digital.slovensko.autogram.timestamp-provider"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> TimestampSourceConfiguration {
        guard let data = defaults.data(forKey: Self.storageKey),
              let configuration = try? JSONDecoder().decode(TimestampSourceConfiguration.self, from: data) else {
            return .automatic
        }
        return configuration
    }

    func save(_ configuration: TimestampSourceConfiguration) {
        defaults.set(try? JSONEncoder().encode(configuration), forKey: Self.storageKey)
    }

    func credential(for provider: CustomTimestampProviderConfiguration) throws -> Secret? {
        guard provider.authentication.kind != .none else { return nil }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: provider.credentialKey.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw TimestampCredentialStoreError.keychain(status)
        }
        query.removeAll()
        return Secret(bytes: Array(data))
    }

    func replaceCredential(_ secret: Secret?, for provider: CustomTimestampProviderConfiguration) throws {
        let account = provider.credentialKey.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account
        ]
        guard let secret else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw TimestampCredentialStoreError.keychain(status)
            }
            return
        }
        var bytes = secret.consumeBytes() ?? []
        defer { bytes.zeroize() }
        let attributes = [kSecValueData as String: Data(bytes)]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = Data(bytes)
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw TimestampCredentialStoreError.keychain(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw TimestampCredentialStoreError.keychain(updateStatus)
        }
    }
}

enum TimestampCredentialStoreError: Error {
    case keychain(OSStatus)
}

enum OutputPolicy: String, Codable, Sendable, CaseIterable, Identifiable {
    case signedSuffix

    var id: Self { self }
}

enum DestinationBehavior: String, Codable, Sendable, CaseIterable, Identifiable {
    case besideSource
    case askEachTime

    var id: Self { self }
}

enum LocalizedMessage {
    static func resolve(messageKey: String, fallback: String) -> String {
        let resolved = NSLocalizedString(messageKey, bundle: .main, value: messageKey, comment: "")
        return resolved == messageKey ? fallback : resolved
    }
}
