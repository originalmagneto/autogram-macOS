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
                Section("Pokročilé") {
                    ForEach([SidebarSection.zako, SidebarSection.evidence]) { section in
                        HStack {
                            Label(section.rawValue, systemImage: section.symbol)
                            if section.isAdvancedMode {
                                Text("ADVANCED")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .tracking(0.6)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.16), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                        }
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
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
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
                ? "štandardný režim · demo podpis (spustite Autogram službu pre KEP)"
                : "štandardný režim · kvalifikované podpisovanie"
        case .zako:
            return "advanced mode · § 35–39 zákona č. 305/2013 Z. z."
        case .evidence:
            return "lokálny register zaručených konverzií"
        case .settings:
            return "konfigurácia aplikácie"
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .signing:
            SigningFlowView(signingProvider: settingsStore.signingProvider)
        case .zako:
            ZakoFlowView(settingsStore: settingsStore)
        case .evidence:
            EvidenceDashboardView(store: settingsStore.evidenceStore)
        case .settings:
            SettingsView(settingsStore: settingsStore)
        }
    }
}
