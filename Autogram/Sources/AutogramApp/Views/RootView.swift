import SwiftUI
import AppKit
import AutogramKit

struct RootView: View {
    enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
        case signing = "Podpisovanie"
        case zako = "Zaručená konverzia"
        case evidence = "Register konverzií"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .signing: return "signature"
            case .zako: return "building.columns.fill"
            case .evidence: return "archivebox.fill"
            }
        }
    }

    @Bindable var model: AutogramAppModel
    @State private var selection: SidebarSection = .signing

    init(model: AutogramAppModel) {
        self._model = Bindable(wrappedValue: model)
    }

    private var settingsStore: AppSettingsStore { model.settingsStore }
    private var signingStore: SigningSessionStore { model.signingStore }
    private var zakoStore: ZakoSessionStore { model.zakoStore }

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
                    SettingsLink {
                        Label("Nastavenia", systemImage: "gearshape.fill")
                    }
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
        }
        .task {
            FinderSigningRouter.shared.install { urls in
                selection = .signing
                Task { await signingStore.signFromFinder(urls) }
            }
        }
        .focusedValue(\.autogramCommandActions, AutogramCommandActions(
            openDocument: openDocument,
            addFiles: openMoreFiles,
            toggleSidebar: toggleSidebar))
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

    private func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                selection = .signing
                await signingStore.loadDocument(at: url)
            }
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

    private func toggleSidebar() {
        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
    }
}
