import SwiftUI
import AutogramKit

struct RootView: View {
    enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
        case signing = "Podpisovanie"
        case zako = "Zaručená konverzia"
        case evidence = "Evidencia konverzií"
        case settings = "Nastavenia"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .signing: return "signature"
            case .zako: return "building.columns.fill"
            case .evidence: return "archivebox.fill"
            case .settings: return "gearshape.fill"
            }
        }

        var isAdvancedMode: Bool { self == .zako }
    }

    @State private var selection: SidebarSection = .signing
    @State private var settingsStore = AppSettingsStore()

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Autogram") {
                    Label(SidebarSection.signing.rawValue, systemImage: SidebarSection.signing.symbol)
                        .tag(SidebarSection.signing)
                }
                Section("Pokročilé · Advanced") {
                    ForEach([SidebarSection.zako, SidebarSection.evidence]) { section in
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
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            detailView
                .navigationTitle(selection.rawValue)
                .navigationSubtitle(subtitle)
                .backgroundExtensionEffect()
        }
    }

    private var subtitle: String {
        switch selection {
        case .signing:
            return settingsStore.signingProvider is DemoSigningProvider
                ? "demo podpis"
                : "kvalifikované podpisovanie"
        case .zako:
            return "advanced · § 35–39 Zz"
        case .evidence:
            return "register konverzií"
        case .settings:
            return "konfigurácia"
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .signing:
            SigningFlowView(signingProvider: settingsStore.signingProvider,
                            settings: settingsStore.settings)
        case .zako:
            ZakoFlowView(settingsStore: settingsStore)
        case .evidence:
            EvidenceDashboardView(settingsStore: settingsStore)
        case .settings:
            SettingsView(settingsStore: settingsStore)
        }
    }
}
