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
        case omlxLocal = "Lokálny model (oMLX - Apple Silicon)"
        case ollamaLocal = "Lokálny model (Ollama)"
        case customAPIKey = "Vlastný API kľúč (OpenAI-compatible)"
        case disabled = "Vypnuté"

        public var id: String { rawValue }
    }

    public var aiMode: AIMode
    public var aiPrompt: String?
    public var omlxURL: String
    public var omlxModel: String
    public var ollamaURL: String
    public var ollamaModel: String
    public var openAICompatibleBaseURL: String
    public var openAICompatibleModel: String
    public var customTSAServers: [String]
    public var selectedTSAURL: String
    public var pdfaMode: PDFAConversionMode
    public var profiles: [AdvocateProfile]
    public var activeProfileID: UUID?
    public var ezzkICO: String
    public var ezzkUsername: String
    public var ezzkNotificationEmail: String
    public var ezzkEdeskAddress: String

    private enum CodingKeys: String, CodingKey {
        case aiMode, aiPrompt
        case omlxURL, omlxModel
        case ollamaURL, ollamaModel
        case openAICompatibleBaseURL, openAICompatibleModel
        case customTSAServers, selectedTSAURL, legacyTSAURL = "tsaURL"
        case pdfaMode, profiles, activeProfileID
        case ezzkICO, ezzkUsername, ezzkNotificationEmail, ezzkEdeskAddress
    }

    public init(aiMode: AIMode = .builtInOnDevice,
                aiPrompt: String? = nil,
                omlxURL: String = "http://localhost:8000/v1",
                omlxModel: String = "mlx-community/Qwen2.5-VL-7B-Instruct-4bit",
                ollamaURL: String = "http://localhost:11434",
                ollamaModel: String = "llava",
                openAICompatibleBaseURL: String = "https://api.openai.com/v1",
                openAICompatibleModel: String = "gpt-4o-mini",
                customTSAServers: [String] = [],
                selectedTSAURL: String = TimestampAuthority.legacyDefaultURL,
                pdfaMode: PDFAConversionMode = .vectorPreserving,
                profiles: [AdvocateProfile] = [],
                activeProfileID: UUID? = nil,
                ezzkICO: String = "",
                ezzkUsername: String = "",
                ezzkNotificationEmail: String = "",
                ezzkEdeskAddress: String = "") {
        self.aiMode = aiMode
        self.aiPrompt = aiPrompt
        self.omlxURL = omlxURL
        self.omlxModel = omlxModel
        self.ollamaURL = ollamaURL
        self.ollamaModel = ollamaModel
        self.openAICompatibleBaseURL = openAICompatibleBaseURL
        self.openAICompatibleModel = openAICompatibleModel
        self.customTSAServers = customTSAServers
        self.selectedTSAURL = selectedTSAURL
        self.pdfaMode = pdfaMode
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.ezzkICO = ezzkICO
        self.ezzkUsername = ezzkUsername
        self.ezzkNotificationEmail = ezzkNotificationEmail
        self.ezzkEdeskAddress = ezzkEdeskAddress
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.aiMode = try container.decodeIfPresent(AIMode.self, forKey: .aiMode) ?? .builtInOnDevice
        self.aiPrompt = try container.decodeIfPresent(String.self, forKey: .aiPrompt)
        self.omlxURL = try container.decodeIfPresent(String.self, forKey: .omlxURL) ?? "http://localhost:8000/v1"
        self.omlxModel = try container.decodeIfPresent(String.self, forKey: .omlxModel)
            ?? "mlx-community/Qwen2.5-VL-7B-Instruct-4bit"
        self.ollamaURL = try container.decodeIfPresent(String.self, forKey: .ollamaURL) ?? "http://localhost:11434"
        self.ollamaModel = try container.decodeIfPresent(String.self, forKey: .ollamaModel) ?? "llava"
        self.openAICompatibleBaseURL = try container.decodeIfPresent(String.self, forKey: .openAICompatibleBaseURL)
            ?? "https://api.openai.com/v1"
        self.openAICompatibleModel = try container.decodeIfPresent(String.self, forKey: .openAICompatibleModel) ?? "gpt-4o-mini"

        let legacy = try container.decodeIfPresent(String.self, forKey: .legacyTSAURL)
        var customs = try container.decodeIfPresent([String].self, forKey: .customTSAServers) ?? []
        if let legacy, !legacy.isEmpty,
           !TimestampAuthority.builtIn.contains(where: { $0.url.caseInsensitiveCompare(legacy) == .orderedSame }),
           !customs.contains(where: { $0.caseInsensitiveCompare(legacy) == .orderedSame }) {
            customs.append(legacy)
        }
        self.customTSAServers = customs

        let storedSelection = try container.decodeIfPresent(String.self, forKey: .selectedTSAURL)
        if let storedSelection, !storedSelection.isEmpty {
            self.selectedTSAURL = storedSelection
        } else if let legacy, !legacy.isEmpty {
            self.selectedTSAURL = legacy
        } else {
            self.selectedTSAURL = TimestampAuthority.legacyDefaultURL
        }

        self.pdfaMode = try container.decodeIfPresent(PDFAConversionMode.self, forKey: .pdfaMode) ?? .vectorPreserving
        self.profiles = try container.decodeIfPresent([AdvocateProfile].self, forKey: .profiles) ?? []
        self.activeProfileID = try container.decodeIfPresent(UUID.self, forKey: .activeProfileID)
        self.ezzkICO = try container.decodeIfPresent(String.self, forKey: .ezzkICO) ?? ""
        self.ezzkUsername = try container.decodeIfPresent(String.self, forKey: .ezzkUsername) ?? ""
        self.ezzkNotificationEmail = try container.decodeIfPresent(String.self, forKey: .ezzkNotificationEmail) ?? ""
        self.ezzkEdeskAddress = try container.decodeIfPresent(String.self, forKey: .ezzkEdeskAddress) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(aiMode, forKey: .aiMode)
        try container.encodeIfPresent(aiPrompt, forKey: .aiPrompt)
        try container.encode(omlxURL, forKey: .omlxURL)
        try container.encode(omlxModel, forKey: .omlxModel)
        try container.encode(ollamaURL, forKey: .ollamaURL)
        try container.encode(ollamaModel, forKey: .ollamaModel)
        try container.encode(openAICompatibleBaseURL, forKey: .openAICompatibleBaseURL)
        try container.encode(openAICompatibleModel, forKey: .openAICompatibleModel)
        try container.encode(customTSAServers, forKey: .customTSAServers)
        try container.encode(selectedTSAURL, forKey: .selectedTSAURL)
        try container.encode(pdfaMode, forKey: .pdfaMode)
        try container.encode(profiles, forKey: .profiles)
        try container.encodeIfPresent(activeProfileID, forKey: .activeProfileID)
        try container.encode(ezzkICO, forKey: .ezzkICO)
        try container.encode(ezzkUsername, forKey: .ezzkUsername)
        try container.encode(ezzkNotificationEmail, forKey: .ezzkNotificationEmail)
        try container.encode(ezzkEdeskAddress, forKey: .ezzkEdeskAddress)
    }

    public var availableTSAServers: [TimestampAuthority] {
        TimestampAuthority.resolveSelected(customServers: customTSAServers,
                                           selectedTSAURL: selectedTSAURL)
    }

    public var activeTSA: TimestampAuthority {
        availableTSAServers.first { $0.url == selectedTSAURL }
            ?? availableTSAServers.first
            ?? TimestampAuthority.builtIn[0]
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
