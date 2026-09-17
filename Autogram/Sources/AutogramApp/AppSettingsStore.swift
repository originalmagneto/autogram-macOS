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

    let ezzkAccountController: EZZKAccountController
    var ezzkService: any EZZKServicing {
        ezzkAccountController.service
    }
    private(set) var signingProvider: any QualifiedSigningProviding
    private(set) var evidenceStore: LocalEvidenceStore
    let exampleBank = ExampleBank(directory: ExampleBank.defaultDirectory)

    init() {
        let loaded = AppSettings.load()
        self.settings = loaded
        self.ezzkAccountController = EZZKAccountController(mode: loaded.ezzkMode)
        self.evidenceStore = LocalEvidenceStore()
        self.signingProvider = SigningProviderFactory.makeDefault()
        ezzkAccountController.configure(
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
