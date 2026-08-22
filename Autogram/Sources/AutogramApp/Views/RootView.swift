import SwiftUI
import AutogramKit
import PDFKit

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
        let storedPassword = KeychainStore.load(account: "ezzk.password") ?? ""
        self.settings = loaded
        self.ezzkPassword = storedPassword
        self.evidenceStore = LocalEvidenceStore()
        let credentials = EZZKCredentials(ico: loaded.ezzkICO,
                                         username: loaded.ezzkUsername,
                                         password: storedPassword,
                                         notificationEmail: loaded.ezzkNotificationEmail,
                                         edeskAddress: loaded.ezzkEdeskAddress)
        if credentials.isConfigured {
            self.ezzkService = HTTPSEZZKService(credentials: credentials)
        } else {
            self.ezzkService = MockEZZKService()
        }
        self.signingProvider = DemoSigningProvider()
    }

    func saveEZZKPassword() {
        if ezzkPassword.isEmpty {
            KeychainStore.delete(account: "ezzk.password")
        } else {
            _ = KeychainStore.save(secret: ezzkPassword, account: "ezzk.password")
        }
        rebuildServices()
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

struct RootView: View {
    enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
        case zako = "Zaručená konverzia"
        case signing = "Podpisovanie"
        case evidence = "Evidencia konverzií"
        case settings = "Nastavenia"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .zako: return "building.columns.fill"
            case .signing: return "signature"
            case .evidence: return "archivebox.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    @State private var selection: SidebarSection = .zako
    @State private var settingsStore = AppSettingsStore()

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Autogram") {
                    ForEach([SidebarSection.zako, SidebarSection.signing, SidebarSection.evidence]) { section in
                        Label(section.rawValue, systemImage: section.symbol)
                            .tag(section)
                    }
                }
                Section {
                    Label(SidebarSection.settings.rawValue, systemImage: SidebarSection.settings.symbol)
                        .tag(SidebarSection.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Autogram")
        } detail: {
            detailView
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .zako:
            ZakoFlowView(settingsStore: settingsStore)
        case .signing:
            SigningPlaceholderView()
        case .evidence:
            EvidenceDashboardView(store: settingsStore.evidenceStore)
        case .settings:            SettingsView(settingsStore: settingsStore)
        }
    }
}

struct SigningPlaceholderView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "signature")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Modul podpisovania")
                .font(.title2.weight(.semibold))
            Text("KEP/PAdES podpisovanie bude pripojené v ďalšej fáze. Modul Zaručená konverzia už obsahuje kompletný autorizačný tok vrátane časovej pečiatky.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
