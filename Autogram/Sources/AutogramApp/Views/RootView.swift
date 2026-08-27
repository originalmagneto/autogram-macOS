import SwiftUI
import AppKit
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
    @State private var settingsStore: AppSettingsStore
    @State private var signingStore: SigningSessionStore
    @State private var zakoStore: ZakoSessionStore

    init() {
        let settings = AppSettingsStore()
        _settingsStore = State(initialValue: settings)
        _signingStore = State(initialValue: SigningSessionStore(
            signingProvider: settings.signingProvider,
            settingsStore: settings))
        _zakoStore = State(initialValue: ZakoSessionStore(settingsStore: settings))
    }

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
                if !signingStore.queue.isEmpty {
                    Section("Otvorené súbory") {
                        ForEach(signingStore.queue) { item in
                            Label {
                                Text(item.displayName).lineLimit(1)
                            } icon: {
                                Image(systemName: queueIcon(item.status))
                                    .foregroundStyle(queueColor(item.status))
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selection = .signing
                                Task { await signingStore.selectQueueItem(item.id) }
                            }
                            .listRowBackground(
                                signingStore.selectedQueueID == item.id
                                    ? Color.accentColor.opacity(0.14)
                                    : Color.clear
                            )
                            .contextMenu {
                                Button("Odstrániť zo zoznamu", role: .destructive) {
                                    signingStore.removeQueueItem(item.id)
                                }
                            }
                        }
                        Label("Pridať súbory…", systemImage: "plus")
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                            .onTapGesture { openMoreFiles() }
                        if signingStore.unsignedQueueItems.count > 1 {
                            Label("Podpísať všetky (\(signingStore.unsignedQueueItems.count))",
                                  systemImage: "signature")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selection = .signing
                                    Task { await signingStore.signAllUnsigned() }
                                }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Autogram")
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            detailView
                .navigationTitle(selection.rawValue)
                .navigationSubtitle(subtitle)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
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
            SigningFlowView(store: signingStore)
        case .zako:
            ZakoFlowView(store: zakoStore)
        case .evidence:
            EvidenceDashboardView(settingsStore: settingsStore)
        case .settings:
            SettingsView(settingsStore: settingsStore)
        }
    }

    private func queueIcon(_ status: SigningSessionStore.SigningQueueItem.Status) -> String {
        switch status {
        case .ready: "doc.richtext"
        case .signing: "hourglass"
        case .signed: "checkmark.seal.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func queueColor(_ status: SigningSessionStore.SigningQueueItem.Status) -> Color {
        switch status {
        case .ready: .secondary
        case .signing: .orange
        case .signed: .green
        case .failed: .red
        }
    }

    private func openMoreFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            Task { @MainActor in
                selection = .signing
                await signingStore.addDocuments(at: panel.urls)
            }
        }
    }
}
