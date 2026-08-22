import SwiftUI
import AutogramKit

@MainActor
@Observable
final class AppSettingsStore {
    var settings: AppSettings {
        didSet {
            settings.save()
            rebuildServices()
        }
    }
    var ezzkPassword: String

    private(set) var ezzkService: any EZZKServicing
    private(set) var signingProvider: any QualifiedSigningProviding
    private(set) var evidenceStore: LocalEvidenceStore

    init() {
        let loaded = AppSettings.load()
        self.settings = loaded
        let storedPassword = KeychainStore.load(account: "ezzk.password") ?? ""
        self.ezzkPassword = storedPassword
        self.evidenceStore = LocalEvidenceStore()

        let credentials = EZZKCredentials(ico: loaded.ezzkICO,
                                         username: loaded.ezzkUsername,
                                         password: storedPassword,
                                         notificationEmail: loaded.ezzkNotificationEmail,
                                         edeskAddress: loaded.ezzkEdeskAddress)
        ezzkService = credentials.isConfigured
            ? HTTPSEZZKService(credentials: credentials)
            : MockEZZKService()
        signingProvider = DemoSigningProvider()
    }

    func saveEZZKPassword() {
        if ezzkPassword.isEmpty {
            KeychainStore.delete(account: "ezzk.password")
        } else {
            _ = KeychainStore.save(secret: ezzkPassword, account: "ezzk.password")
        }
        rebuildServices()
    }

    func useRealSigningProvider(_ provider: any QualifiedSigningProviding) {
        signingProvider = provider
    }

    private func rebuildServices() {
        let credentials = EZZKCredentials(ico: settings.ezzkICO,
                                         username: settings.ezzkUsername,
                                         password: ezzkPassword,
                                         notificationEmail: settings.ezzkNotificationEmail,
                                         edeskAddress: settings.ezzkEdeskAddress)
        ezzkService = credentials.isConfigured
            ? HTTPSEZZKService(credentials: credentials)
            : MockEZZKService()
    }
}
