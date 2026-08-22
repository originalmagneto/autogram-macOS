import Foundation
import Security

public enum KeychainStore {
    static let service = "sk.autogram.Autogram"

    public static func save(secret: String, account: String) -> Bool {
        let data = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    public static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public struct AppSettings: Codable, Sendable {
    public enum AIMode: String, Codable, CaseIterable, Identifiable, Sendable {
        case builtInOnDevice = "Interný (on-device Vision)"
        case ollamaLocal = "Lokálny model (Ollama)"
        case customAPIKey = "Vlastný API kľúč (OpenAI-compatible)"
        case disabled = "Vypnuté"

        public var id: String { rawValue }
    }

    public var aiMode: AIMode
    public var ollamaURL: String
    public var ollamaModel: String
    public var openAICompatibleBaseURL: String
    public var openAICompatibleModel: String
    public var tsaURL: String
    public var pdfaMode: PDFAConversionMode
    public var profiles: [AdvocateProfile]
    public var activeProfileID: UUID?
    public var ezzkICO: String
    public var ezzkUsername: String
    public var ezzkNotificationEmail: String
    public var ezzkEdeskAddress: String

    public init(aiMode: AIMode = .builtInOnDevice,
                ollamaURL: String = "http://localhost:11434",
                ollamaModel: String = "llava",
                openAICompatibleBaseURL: String = "https://api.openai.com/v1",
                openAICompatibleModel: String = "gpt-4o-mini",
                tsaURL: String = "http://tsa.disig.sk/qts",
                pdfaMode: PDFAConversionMode = .vectorPreserving,
                profiles: [AdvocateProfile] = [],
                activeProfileID: UUID? = nil,
                ezzkICO: String = "",
                ezzkUsername: String = "",
                ezzkNotificationEmail: String = "",
                ezzkEdeskAddress: String = "") {
        self.aiMode = aiMode
        self.ollamaURL = ollamaURL
        self.ollamaModel = ollamaModel
        self.openAICompatibleBaseURL = openAICompatibleBaseURL
        self.openAICompatibleModel = openAICompatibleModel
        self.tsaURL = tsaURL
        self.pdfaMode = pdfaMode
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.ezzkICO = ezzkICO
        self.ezzkUsername = ezzkUsername
        self.ezzkNotificationEmail = ezzkNotificationEmail
        self.ezzkEdeskAddress = ezzkEdeskAddress
    }

    public static let standard = AppSettings()

    public static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .standard
        }
        return settings
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    static let storageKey = "sk.autogram.settings.v1"
}
