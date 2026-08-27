import SwiftUI
import AppKit
import AutogramKit

struct RootView: View {
    enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
        case signing = "Podpisovanie"
        case zako = "Zaručená konverzia"
        case evidence = "Register konverzií"
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
                Section("Kancelária") {
                    Label(SidebarSection.signing.rawValue, systemImage: SidebarSection.signing.symbol)
                        .tag(SidebarSection.signing)

                    Label(SidebarSection.zako.rawValue, systemImage: SidebarSection.zako.symbol)
                        .tag(SidebarSection.zako)

                    Label(SidebarSection.evidence.rawValue, systemImage: SidebarSection.evidence.symbol)
                        .tag(SidebarSection.evidence)
                }

                if !signingStore.queue.isEmpty {
                    Section("Fronta podpisovania (\(signingStore.queue.count))") {
                        ForEach(signingStore.queue) { item in
                            HStack(spacing: 8) {
                                Image(systemName: queueIcon(item.status))
                                    .foregroundStyle(queueColor(item.status))
                                    .frame(width: 16)
                                Text(item.displayName)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .font(.callout)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 2)
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
                                Button("Vybrať na podpis") {
                                    selection = .signing
                                    Task { await signingStore.selectQueueItem(item.id) }
                                }
                                if let outputURL = item.signedOutputURL {
                                    Button("Ukázať vo Finderi") {
                                        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                                    }
                                }
                                Divider()
                                Button("Odstrániť z fronty", role: .destructive) {
                                    signingStore.removeQueueItem(item.id)
                                }
                            }
                        }

                        if signingStore.unsignedQueueItems.count > 1 {
                            Button {
                                selection = .signing
                                Task { await signingStore.signAllUnsigned() }
                            } label: {
                                Label("Podpísať všetky (\(signingStore.unsignedQueueItems.count))",
                                      systemImage: "signature.badge.checkmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                }

                Section("Predvoľby") {
                    Label(SidebarSection.settings.rawValue, systemImage: SidebarSection.settings.symbol)
                        .tag(SidebarSection.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Autogram")
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
            .safeAreaInset(edge: .bottom) {
                sidebarBottomBar
            }
        } detail: {
            detailView
                .navigationTitle(selection.rawValue)
                .navigationSubtitle(subtitle)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        }
    }

    private var sidebarBottomBar: some View {
        VStack(spacing: 8) {
            Divider()

            let isCardConnected = !signingStore.identities.isEmpty
            let cardLabel = signingStore.identities.first?.label ?? (settingsStore.signingProvider is DemoSigningProvider ? "DEMO režim" : "Karta nepripojená")
            let cardDetail = isCardConnected ? "Čítačka je pripravená" : "Vložte eID alebo SAK kartu"

            SmartcardHUDStatus(
                isConnected: isCardConnected,
                label: cardLabel,
                detail: cardDetail
            )

            Button {
                openMoreFiles()
            } label: {
                Label("Pridať súbory…", systemImage: "plus")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(.bar)
    }

    private var subtitle: String {
        switch selection {
        case .signing:
            return settingsStore.signingProvider is DemoSigningProvider
                ? "demo podpis"
                : "kvalifikované podpisovanie KEP"
        case .zako:
            return "zaručená konverzia (§ 35-39 Zz)"
        case .evidence:
            return "register konverzií a CEZZK"
        case .settings:
            return "konfigurácia a profily"
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
