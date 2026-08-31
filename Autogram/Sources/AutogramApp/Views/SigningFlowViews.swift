import SwiftUI
import PDFKit
import AutogramKit
import UniformTypeIdentifiers
import AppKit

struct SigningFlowView: View {
    @Bindable var store: SigningSessionStore
    @State private var isTargeted = false

    private var steps: [(title: String, symbol: String)] {
        [
            ("Dokument", "doc.badge.plus"),
            ("Nastavenie podpisu", "signature"),
            ("Hotovo", "checkmark.seal.fill")
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            FlowStepBar(steps: steps, currentStepIndex: store.step.rawValue)

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if isTargeted { targetedOverlay }
        }
        .onDrop(of: [UTType.pdf, UTType(filenameExtension: "asice") ?? .data, .jpeg, .png, .tiff], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .task { await store.refreshIdentities() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await store.refreshIdentities()
            }
        }
    }

    private var targetedOverlay: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: 3)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(12)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var stepContent: some View {
        if store.batchPhase != .idle || !store.batchItems.isEmpty {
            SigningBatchView(store: store)
        } else {
            switch store.step {
            case .intake:
                SigningIntakeView(store: store)
            case .prepare:
                SigningPrepareView(store: store)
            case .done:
                SigningDoneView(store: store)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let pdfProvider = providers.first { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }
        let asiceType = UTType(filenameExtension: "asice") ?? .data
        let asiceProvider = providers.first { $0.hasItemConformingToTypeIdentifier(asiceType.identifier) }
        let imageTypes = [UTType.jpeg, .png, .tiff, .heic]
        let imageProvider = imageTypes.compactMap { type in
            providers.first { $0.hasItemConformingToTypeIdentifier(type.identifier) } != nil ? type : nil
        }.first
        let isPDF = pdfProvider != nil || asiceProvider != nil
        let typeIdentifier = pdfProvider != nil
            ? UTType.pdf.identifier
            : (asiceProvider != nil ? asiceType.identifier : (imageProvider?.identifier ?? UTType.png.identifier))
        let provider = (pdfProvider ?? asiceProvider ?? providers.first)!

        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            guard let data else { return }
            Task { @MainActor in
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("sign-import-\(UUID().uuidString).pdf")

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

// MARK: - Step 1: Intake View
struct SigningIntakeView: View {
    let store: SigningSessionStore

    private var isDemoProvider: Bool {
        store.signingProvider is DemoSigningProvider
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            DropzoneArtwork(icon: "signature", tint: .accentColor)

            VStack(spacing: 8) {
                Text("Pretiahnite dokument na podpísanie")
                    .font(.title2.weight(.bold))

                Text("Podporované formáty: PDF, JPEG, PNG, TIFF. Autogram dokument podpíše kvalifikovaným elektronickým podpisom (KEP) s voliteľnou časovou pečiatkou.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            HStack(spacing: 12) {
                Button {
                    openPanel()
                } label: {
                    Label("Vybrať súbor…", systemImage: "folder")
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                }
                .keyboardShortcut("o", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            HStack(spacing: 16) {
                Label("PAdES / ASiC-E", systemImage: "doc.richtext")
                Label("Časová pečiatka QTS", systemImage: "clock.badge.checkmark")
                Label("Vizuálna pečiatka", systemImage: "seal")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.top, 4)

            if isDemoProvider {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("Demo režim podpisu: pre platný KEP pripojte eID kartu alebo čítačku.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
            }

            if let error = store.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, UTType(filenameExtension: "asice") ?? .data]
        panel.allowsMultipleSelection = true
        panel.message = "Vyberte PDF dokumenty na podpísanie."
        panel.begin { response in
            guard response == .OK else { return }
            Task { @MainActor in
                let urls = panel.urls
                if urls.count == 1 {
                    await store.addDocuments(at: urls, selectLast: true)
                } else {
                    await store.addDocuments(at: urls, selectLast: false)
                    let selectedURLs = Set(urls.map(\.standardizedFileURL))
                    let ids = store.queue
                        .filter {
                            selectedURLs.contains($0.url.standardizedFileURL)
                                && ($0.status == .ready || $0.status == .failed)
                        }
                        .map(\.id)
                    await store.prepareBatch(ids: ids)
                }
            }
        }
    }
}

// MARK: - Step 2: Prepare & Settings View
enum SigningOutputFormatPresentation: CaseIterable, Identifiable {
    case embeddedPAdES
    case attachedASIC

    var id: String { format.rawValue }

    var format: SigningOutputFormat {
        switch self {
        case .embeddedPAdES:
            .embeddedPAdES
        case .attachedASIC:
            .attachedASIC
        }
    }

    var label: String {
        switch self {
        case .embeddedPAdES:
            "PAdES"
        case .attachedASIC:
            "ASiC-E / XAdES"
        }
    }

    var explanation: String {
        switch self {
        case .embeddedPAdES:
            "PAdES vloží podpis priamo do PDF dokumentu."
        case .attachedASIC:
            "ASiC-E / XAdES vytvorí kontajner s podpísaným PDF dokumentom."
        }
    }
}


struct SigningPrepareView: View {
    @Bindable var store: SigningSessionStore
    @State private var customTSADraft = ""
    @State private var visualState: SignaturePlacementState?
    @FocusState private var signingPINFocused: Bool
    @State private var bridgePlacement: VisibleSignaturePlacement?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            previewColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                ScrollView {
                    settingsContent
                        .padding(16)
                }

                StickyActionBar {
                    Button {
                        store.reset()
                        store.step = .intake
                    } label: {
                        Label("Iný dokument", systemImage: "chevron.left")
                    }
                    .controlSize(.large)

                    Spacer()

                    signButton
                }
            }
            .frame(width: 380)
            .background(.bar)
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
            }
        }
        .task(id: store.document?.dataRepresentation()?.count ?? 0) {
            setupVisualComposition()
        }
        .task(id: "\(store.signingPIN)|\(store.includeVisibleSignature)") {
            guard store.includeVisibleSignature,
                  !store.signingProviderIsDemo,
                  !store.hasResolvedCertificate,
                  !store.signingPIN.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await resolveCertificateForPreview(relinquishApplicationFocus: false)
        }
        .onChange(of: bridgePlacement) { _, newValue in
            syncPlacementToStore(newValue)
        }
        .onChange(of: visualState?.placement) { _, newValue in
            if let newValue, newValue != bridgePlacement {
                bridgePlacement = newValue
            }
        }
        .onChange(of: store.includeVisibleSignature) { _, enabled in
            guard let visualState else { return }
            if enabled {
                visualState.setEnabled(true)
                if bridgePlacement == nil {
                    bridgePlacement = visualState.placement
                }
            } else {
                bridgePlacement = nil
            }
        }
        .onChange(of: store.identities) { _, _ in
            refreshVisualCardContent()
            enableVisualCompositionIfReady()
        }
        .onChange(of: store.selectedIdentityID) { _, _ in
            refreshVisualCardContent()
        }
        .onChange(of: store.certificateLoadError) { _, _ in
            refreshVisualCardContent()
        }
        .onChange(of: store.isResolvingCertificate) { _, _ in
            refreshVisualCardContent()
        }
    }

    private func refreshVisualCardContent() {
        guard let visualState else { return }
        let identity = store.identities.first(where: { $0.id == store.selectedIdentityID })
        guard store.hasResolvedCertificate, let identity else {
            if let error = store.certificateLoadError {
                visualState.setContent(signerName: "Certifikát sa nenačítal", qualification: error)
            } else if store.isResolvingCertificate {
                visualState.setContent(signerName: "Načítavam certifikát…", qualification: nil)
            } else {
                visualState.setContent(signerName: "Podpisový certifikát", qualification: "Zadajte PIN pre náhľad")
            }
            return
        }
        visualState.setContent(
            signerName: identity.label,
            certificateName: identity.label,
            qualification: identity.isQualified
                ? "Kvalifikovaný elektronický podpis"
                : "Nekvalifikovaný certifikát",
            timestampAuthorityName: store.includeQualifiedTimestamp ? store.settings.activeTSA.name : nil
        )
    }

    private var usesBridgeComposition: Bool {
        store.includeVisibleSignature && visualState != nil
    }

    private func setupVisualComposition() {
        guard let document = store.document else { return }
        let state = SignaturePlacementState(document: document)
        visualState = state
        refreshVisualCardContent()
        if store.includeVisibleSignature {
            state.setEnabled(true)
            bridgePlacement = state.placement
        }
    }

    private func enableVisualCompositionIfReady() {
        guard store.includeVisibleSignature,
              let visualState,
              bridgePlacement == nil else { return }
        visualState.setEnabled(true)
        bridgePlacement = visualState.placement
    }

    private func syncPlacementToStore(_ placement: VisibleSignaturePlacement?) {
        guard let placement else { return }
        visualState?.update(placement: placement)
        store.visualPlacement = placement
        store.signaturePage = min(max(placement.pageIndex, 0), max(store.analysis.totalPages - 1, 0))
        if let page = store.document?.page(at: store.signaturePage) {
            let cropBox = page.bounds(for: .cropBox)
            guard cropBox.width > 0, cropBox.height > 0 else { return }
            let rect = placement.pageRect
            store.signatureRect = NormalizedRect(
                x: Double(rect.minX / cropBox.width),
                y: Double(1 - (rect.maxY / cropBox.height)),
                width: Double(rect.width / cropBox.width),
                height: Double(rect.height / cropBox.height)
            )
        }
        if let state = visualState, let asset = state.selectedAsset {
            store.visualArtworkOverride = try? Data(contentsOf: state.artworkURL(for: asset))
        } else {
            store.visualArtworkOverride = nil
        }
    }

    private var previewColumn: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                if let document = store.document {
                    if usesBridgeComposition {
                        PDFPreviewView(
                            document: document,
                            placement: Binding(
                                get: { store.includeVisibleSignature ? bridgePlacement : nil },
                                set: { bridgePlacement = $0 }
                            ),
                            cardPreview: visualState?.cardPreview
                        )
                    } else {
                        PDFKitPreview(document: document, stampState: nil)
                    }
                }
            }
            .glassCard(cornerRadius: 18, padding: 6)

            HStack(spacing: 12) {
                StatChip(title: "Strany", value: "\(store.analysis.totalPages)", symbol: "doc.on.doc", tint: .blue)
                if store.analysis.nonEmptyPages != store.analysis.totalPages {
                    StatChip(title: "Neprázdne", value: "\(store.analysis.nonEmptyPages)", symbol: "doc.text", tint: .teal)
                }

                Spacer()

                if let url = store.sourceURL {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(url.path)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(14)
    }

    private var tokenStatusLine: some View {
        Group {
            if store.identities.isEmpty {
                Label("Karta nie je detegovaná: vložte eID alebo advokátsky preukaz.", systemImage: "creditcard")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Label("Karta je pripojená a aktívna.", systemImage: "creditcard.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
    }

    private var existingSignaturesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.isInspectingSignatures {
                ProgressView("Kontrolujem podpisy…")
                    .font(.caption)
            } else if store.existingSignatures.isEmpty {
                Text("Dokument zatiaľ neobsahuje elektronický podpis. Podpísanie pridá prvý KEP podpis.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.existingSignatures) { signature in
                    SignatureInfoRow(info: signature)
                }
                Text("Podpísaním sa pridá ďalší podpis (prírastkový podpis PAdES).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedOutputFormatPresentation: SigningOutputFormatPresentation {
        switch store.outputFormat {
        case .embeddedPAdES:
            .embeddedPAdES
        case .attachedASIC:
            .attachedASIC
        }
    }
    @MainActor
    private func resolveCertificateForPreview(
        force: Bool = false,
        relinquishApplicationFocus: Bool = true
    ) async {
        if relinquishApplicationFocus {
            signingPINFocused = false
            NSApp.deactivate()
        }
        await store.resolveCertificateForPreview(force: force)
        if relinquishApplicationFocus {
            NSApp.activate(ignoringOtherApps: true)
        }
    }


    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section 1: Podpisový certifikát & PIN
            VStack(alignment: .leading, spacing: 12) {
                Label("Podpisový certifikát", systemImage: "creditcard.fill")
                    .font(.headline)

                tokenStatusLine

                if store.identities.isEmpty {
                    Text("Pripojte čítačku eID alebo advokátsky preukaz SAK.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    if store.signingProvider is DemoSigningProvider {
                        Label("DEMO režim: podpis nie je právne záväzný.", systemImage: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    ForEach(store.identities) { identity in
                        IdentityRow(
                            identity: identity,
                            isSelected: store.selectedIdentityID == identity.id,
                            onSelect: { store.selectedIdentityID = identity.id }
                        )
                    }

                    if let selected = store.identities.first(where: { $0.id == store.selectedIdentityID }),
                       selected.requiresPIN {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                SecureField("Zadajte PIN karty", text: $store.signingPIN)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($signingPINFocused)
                                    .onSubmit {
                                        Task {
                                            await resolveCertificateForPreview(
                                                force: true,
                                                relinquishApplicationFocus: true)
                                        }
                                    }

                                Button {
                                    Task {
                                        await resolveCertificateForPreview(
                                            force: true,
                                            relinquishApplicationFocus: true)
                                    }
                                } label: {
                                    Label("Načítať certifikáty", systemImage: "arrow.clockwise")
                                }
                                .controlSize(.small)
                                .disabled(store.signingPIN.isEmpty || store.isResolvingCertificate)
                                .help("Načítať certifikáty z vloženej karty")
                            }

                            Text("PIN sa používa iba na túto operáciu a neukladá sa.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)

                            if store.isResolvingCertificate {
                                ProgressView("Načítavam certifikát pre náhľad…")
                                    .font(.caption2)
                            }
                            if let error = store.certificateLoadError {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .glassCard(cornerRadius: 14, padding: 14)

            // Section 2: Parametre výstupu & TSA
            VStack(alignment: .leading, spacing: 12) {
                Label("Parametre podpisu", systemImage: "slider.horizontal.3")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Formát výstupu")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(SigningOutputFormatPresentation.allCases) { presentation in
                            let isSelected = store.outputFormat == presentation.format
                            Button {
                                store.outputFormat = presentation.format
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(presentation.label)
                                        .font(.callout.weight(isSelected ? .semibold : .medium))
                                    Text(presentation.format == .embeddedPAdES
                                         ? "Podpis priamo v PDF"
                                         : "Kontajner s XAdES")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    isSelected
                                        ? Color.accentColor.opacity(0.12)
                                        : Color.primary.opacity(0.03),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(
                                            isSelected
                                                ? Color.accentColor.opacity(0.55)
                                                : Color.primary.opacity(0.10),
                                            lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Formát výstupu \(presentation.label)")
                            .accessibilityValue(isSelected ? "Vybraný" : "Nevybraný")
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }

                    Text(selectedOutputFormatPresentation.explanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider().opacity(0.5)

                Toggle(isOn: $store.includeQualifiedTimestamp) {
                    Label("Kvalifikovaná časová pečiatka (QTS)", systemImage: "clock.badge.checkmark")
                        .font(.callout)
                }

                if store.includeQualifiedTimestamp {
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $store.selectedTSAURL) {
                            ForEach(store.settings.availableTSAServers) { server in
                                Text(server.name).tag(server.url)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .padding(.leading, 8)
                }

                Divider().opacity(0.5)

                Toggle(isOn: $store.convertToPDFA) {
                    Label("Konvertovať do PDF/A pred podpisom", systemImage: "doc.badge.arrow.up")
                        .font(.callout)
                }
            }
            .glassCard(cornerRadius: 14, padding: 14)

            // Section 3: Vizuálna pečiatka podpisu
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Vizuálna pečiatka v PDF", systemImage: "seal")
                        .font(.headline)
                    Spacer()
                    Toggle("", isOn: $store.includeVisibleSignature)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if store.includeVisibleSignature, let visualState {
                    Divider().opacity(0.5)
                    VisibleAppearanceInspector(state: visualState)
                }
            }
            .glassCard(cornerRadius: 14, padding: 14)

            // Section 4: Existujúce podpisy
            VStack(alignment: .leading, spacing: 8) {
                Label("Podpisy v dokumente", systemImage: "signature")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                existingSignaturesSection
            }
            .glassCard(cornerRadius: 14, padding: 12)

            if let error = store.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private var signButton: some View {
        Button {
            Task { await store.sign() }
        } label: {
            HStack(spacing: 8) {
                if store.isSigning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "signature.badge.checkmark")
                }
                Text(store.isSigning ? (store.statusText.isEmpty ? "Podpisujem…" : store.statusText) : "Podpísať KEP")
                    .font(.body.weight(.semibold))
            }
            .padding(.horizontal, 10)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!store.canSign)
        .keyboardShortcut(.defaultAction)
    }
}

// MARK: - Signature Info Row
struct SignatureInfoRow: View {
    let info: DocumentSignatureInfo

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.signerDisplayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let format = info.format {
                        Text(format).font(.caption2.monospaced())
                    }
                    if info.hasQualifiedTimestamp {
                        Text("QTS").font(.caption2.weight(.semibold)).foregroundStyle(.green)
                    }
                    Text(stateLabel).font(.caption2).foregroundStyle(tint)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var icon: String {
        switch info.state {
        case .valid: "checkmark.seal.fill"
        case .invalid: "xmark.seal.fill"
        case .indeterminate, .unknown: "questionmark.seal.fill"
        }
    }

    private var tint: Color {
        switch info.state {
        case .valid: .green
        case .invalid: .red
        case .indeterminate, .unknown: .orange
        }
    }

    private var stateLabel: String {
        switch info.state {
        case .valid: "Platný"
        case .invalid: "Neplatný"
        case .indeterminate: "Dočasný"
        case .unknown: "Neoverené"
        }
    }
}

// MARK: - Step 3: Done View
struct SigningDoneView: View {
    let store: SigningSessionStore

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            previewColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                ScrollView {
                    resultContent
                        .padding(18)
                }

                StickyActionBar {
                    Button {
                        store.reset()
                        store.step = .intake
                    } label: {
                        Label("Nový podpis", systemImage: "plus")
                    }
                    .controlSize(.large)

                    Spacer()

                    if let url = store.signedOutputURL {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Label("Ukázať vo Finderi", systemImage: "folder")
                        }
                        .controlSize(.large)

                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Otvoriť", systemImage: "doc.richtext")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
            }
            .frame(width: 380)
            .background(.bar)
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
            }
        }
    }

    private var previewColumn: some View {
        VStack(spacing: 10) {
            ZStack {
                if let document = store.signedPreviewDocument {
                    PDFKitPreview(document: document)
                } else {
                    ContentUnavailableView(
                        "Náhľad podpísaného súboru",
                        systemImage: "doc.richtext",
                        description: Text("Súbor bol úspešne uložený.")
                    )
                }
            }
            .glassCard(cornerRadius: 18, padding: 6)

            if let url = store.signedOutputURL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    private var resultContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(Color.green.gradient)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Podpis je úspešne uložený")
                        .font(.headline)
                    if let result = store.result {
                        Text(result.isLegallyBinding ? "Kvalifikovaný elektronický podpis (KEP)" : "DEMO podpis")
                            .font(.caption)
                            .foregroundStyle(result.isLegallyBinding ? .green : .orange)
                    }
                }
            }

            GroupBox("Stav súboru a PDF/A") {
                VStack(alignment: .leading, spacing: 6) {
                    Label(store.pdfaPrepared ? "Pred podpisom: PDF/A pripravené" : "Pred podpisom: bez konverzie",
                          systemImage: store.pdfaPrepared ? "checkmark.circle.fill" : "minus.circle")
                        .font(.caption)
                        .foregroundStyle(store.pdfaPrepared ? .green : .secondary)

                    Label(store.pdfaAfterSign ? "Po podpise: PDF/A zachované" : "Po podpise: PAdES formát",
                          systemImage: store.pdfaAfterSign ? "checkmark.circle.fill" : "info.circle")
                        .font(.caption)
                        .foregroundStyle(store.pdfaAfterSign ? .green : .secondary)
                }
                .padding(4)
            }

            GroupBox("Overenie podpisov v súbore") {
                VStack(alignment: .leading, spacing: 8) {
                    if store.resultSignatures.isEmpty {
                        Text("Podpísaný súbor je pripravený.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.resultSignatures) { signature in
                            SignatureInfoRow(info: signature)
                        }
                    }
                }
                .padding(4)
            }
            if let identity = store.identities.first(where: { $0.id == store.selectedIdentityID }) {
                GroupBox("Použitý certifikát") {
                    VStack(alignment: .leading, spacing: 5) {
                        detailRow("Názov", identity.label)
                        detailRow("Vydal", identity.issuerSummary)
                        detailRow("Kvalifikácia", identity.isQualified ? "Kvalifikovaný" : "Nekvalifikovaný")
                        if let validUntil = identity.validUntil {
                            detailRow("Platný do", validUntil.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    .padding(4)
                }
            }

            if store.includeQualifiedTimestamp {
                GroupBox("Kvalifikovaná časová pečiatka") {
                    VStack(alignment: .leading, spacing: 5) {
                        detailRow("Autorita", store.settings.activeTSA.name)
                        detailRow("Adresa", store.settings.activeTSA.url)
                        if let signature = store.resultSignatures.first,
                           let signingTime = signature.signingTime {
                            detailRow("Čas podpisu", signingTime.formatted(date: .abbreviated, time: .standard))
                        }
                        if let detail = store.resultSignatures.first?.detail {
                            detailRow("Validácia", detail)
                        }
                    }
                    .padding(4)
                }
            }
        }
    }
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

}

// MARK: - Batch Review, Progress & Summary
struct SigningBatchView: View {
    @Bindable var store: SigningSessionStore

    private var completedCount: Int {
        store.batchItems.filter { $0.state == .signed }.count
    }

    private var failedCount: Int {
        store.batchItems.filter { $0.state == .failed }.count
    }

    private var skippedCount: Int {
        store.batchItems.filter { $0.state == .skipped }.count
    }

    private var cancelledCount: Int {
        store.batchItems.filter { $0.state == .cancelled }.count
    }

    private var pendingCount: Int {
        store.batchItems.filter { $0.state == .pending }.count
    }

    private var selectedIdentity: SigningIdentityInfo? {
        store.identities.first { $0.id == store.selectedIdentityID }
    }

    private var requiresPIN: Bool {
        selectedIdentity?.requiresPIN == true
            || (!store.signingProviderIsDemo && store.batchSettingsSnapshot?.includeVisibleSignature == true)
            || (!store.signingProviderIsDemo && store.identities.isEmpty)
    }

    private var pinMissing: Bool {
        requiresPIN && store.signingPIN.isEmpty
    }

    private var hasBlockingItems: Bool {
        store.batchItems.contains { $0.state == .failed }
    }

    private var canStart: Bool {
        store.batchPhase == .ready && pendingCount > 0 && !hasBlockingItems && !pinMissing
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    batchErrorBanner
                    if store.batchPhase == .signing {
                        progressCard
                    }
                    if store.batchPhase == .completed || store.batchPhase == .cancelled {
                        summaryCard
                    }
                    settingsCard
                    itemsCard
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }

            StickyActionBar {
                actionBar
            }
        }
        .alert(item: $store.batchErrorDecisionRequest) { request in
            Alert(
                title: Text("Podpis dokumentu zlyhal"),
                message: Text("\(request.displayName)\n\(request.errorMessage)"),
                primaryButton: .default(Text("Pokračovať na ďalšie")) {
                    store.decideBatchFailure(.continueBatch)
                },
                secondaryButton: .destructive(Text("Zastaviť dávku")) {
                    store.decideBatchFailure(.stopBatch)
                }
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: headerIcon)
                .font(.title2)
                .foregroundStyle(headerTint)
                .frame(width: 38, height: 38)
                .background(headerTint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(headerTitle)
                    .font(.title2.weight(.bold))
                Text(headerDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dávka podpisov")
        .accessibilityValue("\(headerTitle). \(headerDetail)")
    }

    @ViewBuilder
    private var batchErrorBanner: some View {
        if let error = store.lastError, !error.isEmpty {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.red.opacity(0.18), lineWidth: 1)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Chyba dávky")
                .accessibilityValue(error)
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Nastavenie dávky", systemImage: "slider.horizontal.3")
                .font(.headline)

            if requiresPIN {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("Zadajte PIN karty", text: $store.signingPIN)
                        .textFieldStyle(.roundedBorder)
                        .disabled(store.batchPhase == .preflighting || store.batchPhase == .signing)
                        .accessibilityLabel("PIN podpisovej karty")
                        .accessibilityValue(
                            store.signingPIN.isEmpty ? "PIN nie je zadaný" : "PIN je zadaný"
                        )

                    HStack(spacing: 8) {
                        Button {
                            Task { await refreshCertificate() }
                        } label: {
                            Label("Obnoviť certifikát", systemImage: "arrow.clockwise")
                        }
                        .controlSize(.small)
                        .disabled(store.batchPhase == .preflighting || store.batchPhase == .signing)
                        .accessibilityLabel("Obnoviť podpisový certifikát")
                        .accessibilityValue("Načítať certifikát z pripojenej karty")

                        Text("PIN sa používa iba počas tejto operácie a neukladá sa.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if let snapshot = store.batchSettingsSnapshot {
                settingRow("Podpisový certifikát", value: snapshot.identityLabel)
                settingRow("Formát výstupu", value: outputFormatLabel(snapshot.outputFormat))
                settingRow(
                    "Časová pečiatka",
                    value: snapshot.includeQualifiedTimestamp
                        ? (snapshot.tsaURL ?? "QTS zapnutá")
                        : "Vypnutá"
                )
                settingRow("PDF/A", value: snapshot.convertToPDFA ? "Zapnuté" : "Vypnuté")
                settingRow(
                    "Vizuálna pečiatka",
                    value: snapshot.includeVisibleSignature
                        ? "Zapnutá"
                        : "Vypnutá"
                )
            } else {
                Text("Načítavam spoločné nastavenia a kontrolujem dokumenty…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard(cornerRadius: 14, padding: 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spoločné nastavenia dávky")
    }

    private func settingRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private var itemsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Dokumenty v dávke", systemImage: "doc.on.doc")
                    .font(.headline)
                Spacer()
                Text("\(store.batchItems.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ForEach(store.batchItems) { item in
                batchItemRow(item)
            }
        }
        .glassCard(cornerRadius: 14, padding: 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dokumenty v dávke, \(store.batchItems.count) položiek")
    }

    private func batchItemRow(_ item: SigningSessionStore.BatchItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: itemIcon(item.state))
                    .foregroundStyle(itemTint(item.state))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text(itemStateLabel(item.state))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(itemTint(item.state))
                        Text(inputAvailability(item.url))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let inspectionState = item.inputSignatureState {
                        Text("Podpisy vstupu: \(inputSignatureStateLabel(inspectionState))")
                            .font(.caption2)
                        .foregroundStyle(inspectionState == .valid ? Color.secondary : Color.red)
                    }
                    if let plannedOutputURL = item.plannedOutputURL {
                        Text(
                            item.outputURL == nil
                                ? "Plánovaný výstup: \(plannedOutputURL.lastPathComponent)"
                                : "Výstup: \(plannedOutputURL.lastPathComponent)"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)

                if let outputURL = item.outputURL, item.state == .signed {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Ukázať výstup vo Finderi")
                    .accessibilityLabel("Ukázať výstup dokumentu \(item.displayName) vo Finderi")
                    .accessibilityValue(outputURL.lastPathComponent)
                }
            }

            if let error = item.errorMessage, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.leading, 27)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dokument \(item.displayName)")
        .accessibilityValue(itemAccessibilityValue(item))
    }

    private var progressCard: some View {
        let total = max(store.batchItems.count, 1)
        let currentName = store.batchCurrentIndex.flatMap { index in
            store.batchItems.indices.contains(index) ? store.batchItems[index].displayName : nil
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Priebeh podpisovania", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                Spacer()
                Text("\(completedCount) z \(store.batchItems.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(completedCount), total: Double(total))
                .progressViewStyle(.linear)
                .tint(.accentColor)

            if let currentName {
                Label("Aktuálny dokument: \(currentName)", systemImage: "signature")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                progressMetric("Hotové", count: completedCount, tint: .green, symbol: "checkmark.circle.fill")
                progressMetric("Zlyhania", count: failedCount, tint: .red, symbol: "xmark.circle.fill")
            }
        }
        .glassCard(cornerRadius: 14, padding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Priebeh podpisovania")
        .accessibilityValue(
            "\(completedCount) z \(store.batchItems.count) hotových, \(failedCount) zlyhaní"
            + (currentName.map { ", podpisuje sa \($0)" } ?? "")
        )
    }

    private func progressMetric(_ title: String, count: Int, tint: Color, symbol: String) -> some View {
        Label("\(title): \(count)", systemImage: symbol)
            .font(.caption)
            .foregroundStyle(tint)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                store.batchPhase == .completed ? "Dávka dokončená" : "Dávka zrušená",
                systemImage: store.batchPhase == .completed
                    ? "checkmark.seal.fill"
                    : "pause.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(store.batchPhase == .completed ? .green : .orange)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading)
                ],
                spacing: 8
            ) {
                summaryMetric("Úspešné", count: completedCount, tint: .green)
                summaryMetric("Neúspešné", count: failedCount, tint: .red)
                summaryMetric("Preskočené", count: skippedCount, tint: .orange)
                summaryMetric("Zrušené", count: cancelledCount, tint: .secondary)
            }
        }
        .glassCard(cornerRadius: 14, padding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Záverečné zhrnutie dávky")
        .accessibilityValue(
            "\(completedCount) úspešných, \(failedCount) neúspešných, "
            + "\(skippedCount) preskočených, \(cancelledCount) zrušených"
        )
    }

    private func summaryMetric(_ title: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text("\(title): \(count)")
                .font(.caption)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(count)")
    }

    @ViewBuilder
    private var actionBar: some View {
        switch store.batchPhase {
        case .preflighting:
            ProgressView("Kontrolujem dokumenty…")
                .font(.callout)
            Spacer()
            Button("Zrušiť kontrolu") {
                store.cancelBatch()
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Zrušiť kontrolu dávky")
            .accessibilityValue("Kontrola preflightu prebieha")
        case .ready, .idle:
            Button {
                beginNewBatch()
            } label: {
                Label("Iná dávka", systemImage: "chevron.left")
            }
            .controlSize(.large)
            .accessibilityLabel("Vybrať inú dávku")

            if !store.batchItems.isEmpty {
                Button {
                    let ids = store.batchItems.map(\.id)
                    Task { await store.prepareBatch(ids: ids) }
                } label: {
                    Label("Znova skontrolovať", systemImage: "arrow.clockwise")
                }
                .controlSize(.large)
                .disabled(store.batchPhase == .preflighting || store.batchPhase == .signing)
                .accessibilityLabel("Znova skontrolovať dávku")
                .accessibilityValue("Spustiť preflight dokumentov a nastavení")
            }

            Spacer()

            if canStart {
                Button {
                    Task { await store.startBatch() }
                } label: {
                    Label("Spustiť dávku", systemImage: "signature.badge.checkmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityLabel("Spustiť dávku podpisov")
                .accessibilityValue("\(pendingCount) dokumentov čaká na podpis")
            } else if store.batchPhase == .ready {
                Text(
                    pinMissing
                        ? "Zadajte PIN a znova skontrolujte dávku."
                        : "Odstráňte blokujúce problémy pred spustením."
                )
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Dávku nie je možné spustiť")
                    .accessibilityValue(
                        pinMissing
                            ? "Zadajte PIN a znova skontrolujte dávku"
                            : "Odstráňte blokujúce problémy"
                    )
            }
        case .signing:
            Text("Podpisujem dokumenty…")
                .font(.callout)
            Spacer()
            Button("Zrušiť dávku") {
                store.cancelBatch()
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Zrušiť podpisovanie dávky")
            .accessibilityValue("Dávka je v priebehu")
        case .completed, .cancelled:
            Button {
                beginNewBatch()
            } label: {
                Label("Nová dávka", systemImage: "plus")
            }
            .controlSize(.large)
            .accessibilityLabel("Začať novú dávku")

            Spacer()

            if failedCount > 0 {
                Button {
                    Task { await store.retryFailedBatchItems() }
                } label: {
                    Label("Opakovať neúspešné", systemImage: "arrow.clockwise")
                }
                .controlSize(.large)
                .accessibilityLabel("Opakovať neúspešné dokumenty")
                .accessibilityValue("\(failedCount) dokumentov")
            }

            if store.batchItems.contains(where: { $0.outputURL != nil }) {
                Button {
                    revealOutputs()
                } label: {
                    Label("Ukázať výstupy", systemImage: "folder")
                }
                .controlSize(.large)
                .accessibilityLabel("Ukázať podpísané výstupy vo Finderi")
                .accessibilityValue("\(completedCount) súborov")
            }

            Button {
                exportLog()
            } label: {
                Label("Exportovať protokol…", systemImage: "square.and.arrow.down")
            }
            .controlSize(.large)
            .accessibilityLabel("Exportovať protokol dávky")
            .accessibilityValue("Uložiť textový protokol do vybraného súboru")
        }
    }

    private var headerTitle: String {
        switch store.batchPhase {
        case .preflighting: "Kontrola dávky"
        case .ready: "Dávka pripravená na podpis"
        case .signing: "Podpisovanie dávky"
        case .completed: "Dávka dokončená"
        case .cancelled: "Dávka zrušená"
        case .idle: "Kontrola dávky"
        }
    }

    private var headerDetail: String {
        switch store.batchPhase {
        case .preflighting:
            "Overujem dostupnosť súborov a spoločné nastavenia."
        case .ready:
            hasBlockingItems
                ? "Niektoré dokumenty obsahujú blokujúce problémy."
                : "\(pendingCount) dokumentov je pripravených na podpis."
        case .signing:
            "Dokumenty sa podpisujú postupne. Výstupy sa ukladajú bezpečne."
        case .completed:
            "Skontrolujte výsledky a prípadne zopakujte neúspešné dokumenty."
        case .cancelled:
            "Podpisovanie bolo zastavené; hotové výstupy zostali zachované."
        case .idle:
            "Preflight dávky sa nedokončil."
        }
    }

    private var headerIcon: String {
        switch store.batchPhase {
        case .preflighting: "checklist"
        case .ready: "signature"
        case .signing: "arrow.triangle.2.circlepath"
        case .completed: "checkmark.seal.fill"
        case .cancelled: "pause.circle.fill"
        case .idle: "exclamationmark.triangle.fill"
        }
    }

    private var headerTint: Color {
        switch store.batchPhase {
        case .preflighting, .signing: .accentColor
        case .ready: .blue
        case .completed: .green
        case .cancelled: .orange
        case .idle: .red
        }
    }

    private func itemAccessibilityValue(_ item: SigningSessionStore.BatchItem) -> String {
        var value = "\(itemStateLabel(item.state)); \(inputAvailability(item.url))"
        if let inspectionState = item.inputSignatureState {
            value += "; vstupné podpisy \(inputSignatureStateLabel(inspectionState))"
        }
        if let detail = item.inputSignatureDetail, !detail.isEmpty {
            value += "; detail \(detail)"
        }
        if let error = item.errorMessage, !error.isEmpty {
            value += "; blokovanie: \(error)"
        }
        if let planned = item.plannedOutputURL, item.outputURL == nil {
            value += "; plánovaný výstup \(planned.lastPathComponent)"
        }
        if let output = item.outputURL {
            value += "; výstup \(output.lastPathComponent)"
        }
        return value
    }

    private func inputAvailability(_ url: URL) -> String {
        FileManager.default.isReadableFile(atPath: url.path) ? "Vstup dostupný" : "Vstup nedostupný"
    }

    private func inputSignatureStateLabel(
        _ state: InputSignatureInspectionResult.State
    ) -> String {
        switch state {
        case .valid: "Overené"
        case .invalid: "Neplatné alebo konfliktné"
        case .unknown: "Neznáme"
        case .unavailable: "Nedostupné"
        }
    }

    private func itemIcon(_ state: SigningSessionStore.BatchItemState) -> String {
        switch state {
        case .pending: "circle"
        case .signing: "arrow.triangle.2.circlepath"
        case .signed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .skipped: "forward.end"
        case .cancelled: "xmark.circle"
        }
    }

    private func itemTint(_ state: SigningSessionStore.BatchItemState) -> Color {
        switch state {
        case .pending: .secondary
        case .signing: .accentColor
        case .signed: .green
        case .failed: .red
        case .skipped: .orange
        case .cancelled: .secondary
        }
    }

    private func itemStateLabel(_ state: SigningSessionStore.BatchItemState) -> String {
        switch state {
        case .pending: "Čaká"
        case .signing: "Podpisuje sa"
        case .signed: "Podpísané"
        case .failed: "Zlyhalo"
        case .skipped: "Preskočené"
        case .cancelled: "Zrušené"
        }
    }

    private func outputFormatLabel(_ format: SigningOutputFormat) -> String {
        switch format {
        case .embeddedPAdES: "PAdES"
        case .attachedASIC: "ASiC-E / XAdES"
        }
    }

    private func beginNewBatch() {
        store.batchItems = []
        store.batchPhase = .idle
        store.batchErrorDecisionRequest = nil
        store.reset()
        store.step = .intake
    }

    private func refreshCertificate() async {
        await store.refreshIdentities()
        if !store.signingProviderIsDemo, !store.signingPIN.isEmpty {
            await store.resolveCertificateForPreview(force: true)
        }
    }

    private func revealOutputs() {
        let outputs = store.batchItems.compactMap(\.outputURL)
        guard !outputs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(outputs)
    }

    private func exportLog() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "autogram-davka.txt"
        panel.message = "Vyberte miesto na uloženie protokolu dávky."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try batchLog().write(to: url, atomically: true, encoding: .utf8)
            } catch {
                store.lastError = "Protokol sa nepodarilo uložiť: \(error.localizedDescription)"
            }
        }
    }

    private func batchLog() -> String {
        var lines = [
            "Autogram: protokol podpisovania dávky",
            "Stav: \(headerTitle)",
            "Úspešné: \(completedCount)",
            "Neúspešné: \(failedCount)",
            "Preskočené: \(skippedCount)",
            "Zrušené: \(cancelledCount)",
            "",
            "Dokumenty:"
        ]

        for item in store.batchItems {
            lines.append("- \(item.displayName): \(itemStateLabel(item.state))")
            lines.append("  Vstup: \(item.url.path)")
            if let outputURL = item.outputURL {
                lines.append("  Výstup: \(outputURL.path)")
            }
            if let error = item.errorMessage, !error.isEmpty {
                lines.append("  Chyba: \(error)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
