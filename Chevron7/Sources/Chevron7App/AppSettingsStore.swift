// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Chevron7Identity
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
    let exampleBank: ExampleBank
    /// Root for every file the app keeps: evidence register, vision bank, output,
    /// templates and signature images.
    let storageRoot: URL

    /// Tests pass a controller with in-memory credentials and a scripted transport, and a
    /// temporary `storageRoot` so they never read or write the user's real evidence register.
    init(ezzkAccountController: EZZKAccountController? = nil,
         storageRoot: URL = ProductIdentity.applicationSupportDirectory()) {
        let loaded = AppSettings.load()
        self.settings = loaded
        self.storageRoot = storageRoot
        self.ezzkAccountController = ezzkAccountController ?? EZZKAccountController(mode: loaded.ezzkMode)
        self.evidenceStore = LocalEvidenceStore(
            directory: storageRoot.appendingPathComponent("Evidence", isDirectory: true))
        self.exampleBank = ExampleBank(directory: Self.exampleBankDirectory(in: storageRoot))
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

    var exampleBankDirectory: URL { Self.exampleBankDirectory(in: storageRoot) }
    /// Fallback for signed and converted files when the source folder is not writable.
    var outputDirectory: URL { storageRoot.appendingPathComponent("Output", isDirectory: true) }
    var templatesDirectory: URL { storageRoot.appendingPathComponent("Templates", isDirectory: true) }
    var signaturesDirectory: URL { storageRoot.appendingPathComponent("Signatures", isDirectory: true) }

    private nonisolated static func exampleBankDirectory(in root: URL) -> URL {
        root.appendingPathComponent("VisionBank", isDirectory: true)
    }
}
