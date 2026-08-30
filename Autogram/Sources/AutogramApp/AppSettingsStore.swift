import SwiftUI
import AutogramKit

@MainActor
@Observable
final class AppSettingsStore {
    var settings: AppSettings {
        didSet {
            settings.save()
        }
    }
    // Kept for legacy settings migration. It is not used to authenticate EZZK.
    var ezzkPassword: String

    let ezzkSessionController: EZZKSessionController
    var ezzkService: any EZZKServicing {
        ezzkSessionController.service
    }
    private(set) var signingProvider: any QualifiedSigningProviding
    private(set) var evidenceStore: LocalEvidenceStore

    init() {
        let loaded = AppSettings.load()
        let storedPassword = KeychainStore.load(account: "ezzk.password") ?? ""
        let isDemoMode = loaded.ezzkICO.isEmpty &&
            loaded.ezzkUsername.isEmpty &&
            storedPassword.isEmpty
        self.settings = loaded
        self.ezzkPassword = storedPassword
        self.ezzkSessionController = EZZKSessionController(demoMode: isDemoMode)
        self.evidenceStore = LocalEvidenceStore()
        self.signingProvider = SigningProviderFactory.makeDefault()
    }

    func saveEZZKPassword() {
        if ezzkPassword.isEmpty {
            KeychainStore.delete(account: "ezzk.password")
        } else {
            _ = KeychainStore.save(secret: ezzkPassword, account: "ezzk.password")
        }
    }

    func useRealSigningProvider(_ provider: any QualifiedSigningProviding) {
        signingProvider = provider
    }
}
