import SwiftUI
import AppKit
import UniformTypeIdentifiers
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
    @State private var queueItemToDelete: UUID?
    @State private var showQueueDeleteConfirmation = false

    init(model: AutogramAppModel) {
        self._model = Bindable(wrappedValue: model)
    }

    private var settingsStore: AppSettingsStore { model.settingsStore }
    private var recentDocumentStore: RecentDocumentStore { model.recentDocumentStore }

    private var signingStore: SigningSessionStore { model.signingStore }

    private var batchIsActive: Bool {
        signingStore.batchPhase == .preflighting
            || signingStore.batchPhase == .ready
            || signingStore.batchPhase == .signing
    }
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

                if recentDocumentStore.isEnabled && !recentDocumentStore.entries.isEmpty {
                    Section {
                        ForEach(recentDocumentStore.entries) { entry in
                            let isAvailable = recentDocumentStore.isAvailable(entry)
                            Button {
                                guard isAvailable else { return }
                                selection = .signing
                                Task {
                                    await recentDocumentStore.withResolvedURL(entry) { resolvedURL in
                                        await signingStore.loadDocument(at: resolvedURL)
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isAvailable ? "clock.arrow.circlepath" : "doc.badge.ellipsis")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 16)
                                    Text(entry.displayName)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .font(.callout)
                                    if !isAvailable {
                                        Spacer(minLength: 0)
                                        Text("Nedostupný")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(!isAvailable)
                            .accessibilityLabel("Nedávny dokument \(entry.displayName)")
                            .accessibilityValue(isAvailable ? "Dostupný" : "Nedostupný")
                            .contextMenu {
                                Button("Odstrániť z nedávnych", role: .destructive) {
                                    recentDocumentStore.remove(id: entry.id)
                                }
                            }
                        }
                    } header: {
                        Text("Nedávne dokumenty")
                            .contextMenu {
                                Button("Vymazať všetky nedávne dokumenty", role: .destructive) {
                                    recentDocumentStore.clear()
                                }
                            }
                    }
                }


                if !signingStore.queue.isEmpty {
                    Section("Fronta podpisovania (\(signingStore.queue.count))") {
                        ForEach(signingStore.queue) { item in
                            let isSelected = signingStore.selectedQueueID == item.id
                            Button {
                                selection = .signing
                                Task { await signingStore.selectQueueItem(item.id) }
                            } label: {
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
                            }
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                            .accessibilityLabel("Dokument \(item.displayName)")
                            .accessibilityValue("\(queueStatusLabel(item.status)); \(isSelected ? "Vybraný" : "Nevybraný")")
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                            .padding(.vertical, 2)
                            .listRowBackground(
                                isSelected
                                    ? Color.primary.opacity(0.08)
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
                                    queueItemToDelete = item.id
                                    showQueueDeleteConfirmation = true
                                }
                                .disabled(batchIsActive)
                            }
                        }

                        if signingStore.unsignedQueueItems.count > 1 {
                            Button {
                                selection = .signing
                                let ids = signingStore.unsignedQueueItems.map(\.id)
                                Task { await signingStore.prepareBatch(ids: ids) }
                            } label: {
                                Label("Podpísať všetky (\(signingStore.unsignedQueueItems.count))",
                                      systemImage: "signature.badge.checkmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                            .disabled(batchIsActive)
                            .padding(.top, 4)
                            .accessibilityLabel("Pripraviť dávku podpisov")
                            .accessibilityValue(
                                batchIsActive
                                    ? "Dávka už prebieha"
                                    : "\(signingStore.unsignedQueueItems.count) dokumentov"
                            )
                        }
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
        .focusedValue(\.autogramCommandActions, AutogramCommandActions(
            openDocument: openDocument,
            addFiles: openMoreFiles,
            toggleSidebar: toggleSidebar))
        .confirmationDialog(
            "Naozaj chcete odstrániť dokument z fronty?",
            isPresented: $showQueueDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Odstrániť z fronty", role: .destructive) {
                if let id = queueItemToDelete { signingStore.removeQueueItem(id) }
                queueItemToDelete = nil
            }
            Button("Zrušiť", role: .cancel) { queueItemToDelete = nil }
        } message: {
            Text("Dokument zostane v pôvodnom umiestnení; odstráni sa iba z fronty podpisovania.")
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

            HStack {
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Nastavenia")
                .help("Otvoriť nastavenia")
                Spacer(minLength: 0)
            }
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
    private func queueStatusLabel(_ status: SigningSessionStore.SigningQueueItem.Status) -> String {
        switch status {
        case .ready: "Pripravené"
        case .signing: "Podpisuje sa"
        case .signed: "Podpísané"
        case .failed: "Podpis zlyhal"
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
        panel.allowedContentTypes = [.pdf, UTType(filenameExtension: "asice") ?? .data]
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
        guard !batchIsActive else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, UTType(filenameExtension: "asice") ?? .data]
        panel.begin { response in
            guard response == .OK else { return }
            Task { @MainActor in
                selection = .signing
                let urls = panel.urls
                if urls.count == 1 {
                    await signingStore.addDocuments(at: urls, selectLast: true)
                } else {
                    await prepareReviewedBatch(for: urls)
                }
            }
        }
    }

    private func prepareReviewedBatch(for urls: [URL]) async {
        guard !batchIsActive else { return }
        await signingStore.addDocuments(at: urls, selectLast: false)
        let selectedURLs = Set(urls.map(\.standardizedFileURL))
        let ids = signingStore.queue
            .filter {
                selectedURLs.contains($0.url.standardizedFileURL)
                    && ($0.status == .ready || $0.status == .failed)
            }
            .map(\.id)
        await signingStore.prepareBatch(ids: ids)
    }

    private func toggleSidebar() {
        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
    }
}
