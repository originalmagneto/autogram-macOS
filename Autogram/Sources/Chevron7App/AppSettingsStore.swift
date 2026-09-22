import SwiftUI
import Chevron7Kit

@MainActor
@Observable
final class AppSettingsStore {
    var settings: AppSettings {
        didSet {
            settings.save()
        }
    }

    let ezzkAccountController: EZZKAccountController
    var ezzkService: any EZZKServicing {
        ezzkAccountController.service
    }
    private(set) var signingProvider: any QualifiedSigningProviding
    private(set) var evidenceStore: LocalEvidenceStore
    let exampleBank = ExampleBank(directory: ExampleBank.defaultDirectory)

    /// Tests pass a controller with in-memory credentials and a scripted transport.
    init(ezzkAccountController: EZZKAccountController? = nil) {
        let loaded = AppSettings.load()
        self.settings = loaded
        self.ezzkAccountController = ezzkAccountController ?? EZZKAccountController(mode: loaded.ezzkMode)
        self.evidenceStore = LocalEvidenceStore()
        self.signingProvider = SigningProviderFactory.makeDefault()
        self.ezzkAccountController.configure(
            person: { [weak self] in
                guard let self else { return EZZKPerson(corporateBodyFullName: "", ico: "") }
                return EZZKPerson(corporateBodyFullName: settings.ezzkPersonName, ico: settings.ezzkICO)
            },
            usedEvidenceNumbers: { [weak self] in
                Set(self?.evidenceStore.records.compactMap(\.evidenceNumber) ?? [])
            })
    }

    func useRealSigningProvider(_ provider: any QualifiedSigningProviding) {
        signingProvider = provider
    }
}
