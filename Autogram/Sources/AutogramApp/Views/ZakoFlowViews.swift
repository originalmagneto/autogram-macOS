import SwiftUI
import AutogramKit
import PDFKit
import UniformTypeIdentifiers

struct ZakoFlowView: View {
    @State var store: ZakoSessionStore
    @State private var showOpenPanel = false
    @State private var isTargeted = false

    init(settingsStore: AppSettingsStore) {
        let created = ZakoSessionStore(
            settings: settingsStore.settings,
            ezzkService: settingsStore.ezzkService,
            signingProvider: settingsStore.signingProvider,
            evidenceStore: settingsStore.evidenceStore)
        created.profilePersister = { [weak settingsStore] profile in
            guard let settingsStore else { return }
            if let index = settingsStore.settings.profiles.firstIndex(where: { $0.id == profile.id }) {
                settingsStore.settings.profiles[index] = profile
            } else {
                settingsStore.settings.profiles.append(profile)
                settingsStore.settings.activeProfileID = profile.id
            }
        }
        _store = State(initialValue: created)
    }

    var body: some View {
        VStack(spacing: 0) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if isTargeted { targetedOverlay }
        }
        .onDrop(of: [UTType.pdf, .jpeg, .png, .tiff], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .toolbar {
            ToolbarItem(placement: .principal) { stepperBar }
            ToolbarItemGroup(placement: .primaryAction) {
                if store.isAnalyzing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(store.analysisProgressText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var targetedOverlay: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: 3)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
            .padding(10)
            .allowsHitTesting(false)
    }

    private var stepperBar: some View {
        HStack(spacing: 12) {
            ForEach(Array(ZakoSessionStore.Step.allCases.enumerated()), id: \.element) { _, stepCase in
                StepperPill(
                    index: stepCase.rawValue,
                    title: title(for: stepCase),
                    symbol: symbol(for: stepCase),
                    state: pillState(stepCase))
                if stepCase != .done {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.quaternary)
                }
            }
        }
    }

    private func title(for step: ZakoSessionStore.Step) -> String {
        switch step {
        case .intake: return "Vstupný dokument"
        case .analysis: return "Overenie originálu"
        case .attestation: return "Osvedčovacia doložka"
        case .authorize: return "Autorizácia KEP"
        case .done: return "Hotovo"
        }
    }

    private func symbol(for step: ZakoSessionStore.Step) -> String {
        switch step {
        case .intake: return "doc.badge.plus"
        case .analysis: return "shield.checkerboard"
        case .attestation: return "building.columns.fill"
        case .authorize: return "signature.badge.checkmark"
        case .done: return "checkmark.seal.fill"
        }
    }

    private func pillState(_ step: ZakoSessionStore.Step) -> StepperPill.StepState {
        if step.rawValue < store.step.rawValue { return .complete }
        if step == store.step { return .active }
        return .pending
    }

    @ViewBuilder
    private var stepContent: some View {
        switch store.step {
        case .intake:
            IntakeView(store: store, showOpenPanel: $showOpenPanel)
        case .analysis:
            AnalysisCanvasView(store: store)
        case .attestation:
            AttestationFormView(store: store)
        case .authorize:
            AuthorizeView(store: store)
        case .done:
            DoneView(store: store)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let pdfProvider = providers.first { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }
        let imageTypes = [UTType.jpeg, .png, .tiff, .heic]
        let imageProvider = imageTypes.first { type in
            providers.contains { $0.hasItemConformingToTypeIdentifier(type.identifier) }
        }

        let isPDF = pdfProvider != nil
        let typeIdentifier = isPDF ? UTType.pdf.identifier : (imageProvider?.identifier ?? UTType.png.identifier)
        guard let provider = pdfProvider ?? providers.first else {
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            guard let data else { return }
            Task { @MainActor in
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("zako-import-\(UUID().uuidString).pdf")

                if isPDF || data.starts(with: Data("%PDF".utf8)) {
                    try? data.write(to: tempURL)
                } else if let converted = ImageToPDFConverter.pdf(fromImageData: data) {
                    try? converted.write(to: tempURL)
                } else {
                    return
                }
                await store.loadDocument(at: tempURL)
            }
        }
        return true
    }
}

struct IntakeView: View {
    let store: ZakoSessionStore
    @Binding var showOpenPanel: Bool

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 132, height: 132)
                Circle()
                    .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 158, height: 158)
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Color.accentColor.gradient)
            }
            VStack(spacing: 6) {
                Text("Pretiahnite naskenovaný papierový dokument")
                    .font(.title2.weight(.semibold))
                Text("Originál alebo úradne osvedčená kópia vo formáte PDF. Autogram automaticky rozpozná strany, listy a bezpečnostné prvky.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            HStack(spacing: 12) {
                Button {
                    openPanel()
                } label: {
                    Label("Vybrať súbor…", systemImage: "folder")
                        .frame(minWidth: 140)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)

                Button {
                    store.resetSession(keepingProfile: true)
                } label: {
                    Label("Nová konverzia", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.glass)
            }
            if let error = store.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await store.loadDocument(at: url)
            }
        }
    }
}

struct PDFKitPreview: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.document = document
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
        }
    }
}
