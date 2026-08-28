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
        .onDrop(of: [UTType.pdf, .jpeg, .png, .tiff], isTargeted: $isTargeted) { providers in
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
        switch store.step {
        case .intake:
            SigningIntakeView(store: store)
        case .prepare:
            SigningPrepareView(store: store)
        case .done:
            SigningDoneView(store: store)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let pdfProvider = providers.first { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }
        let imageTypes = [UTType.jpeg, .png, .tiff, .heic]
        let imageProvider = imageTypes.compactMap { type in
            providers.first { $0.hasItemConformingToTypeIdentifier(type.identifier) } != nil ? type : nil
        }.first

        guard pdfProvider != nil || imageProvider != nil else { return false }

        let isPDF = pdfProvider != nil
        let typeIdentifier = isPDF ? UTType.pdf.identifier : (imageProvider?.identifier ?? UTType.png.identifier)
        let provider = (pdfProvider ?? providers.first)!

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
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.message = "Vyberte PDF dokumenty na podpísanie."
        panel.begin { response in
            guard response == .OK else { return }
            Task { @MainActor in
                await store.addDocuments(at: panel.urls)
            }
        }
    }
}

// MARK: - Step 2: Prepare & Settings View
struct SigningPrepareView: View {
    @Bindable var store: SigningSessionStore
    @State private var customTSADraft = ""
    @State private var visualState: SignaturePlacementState?
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
            await store.resolveCertificateForPreview()
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
            qualification: identity.isQualified
                ? "Kvalifikovaný elektronický podpis"
                : "Nekvalifikovaný certifikát"
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
                            SecureField("Zadajte PIN karty", text: $store.signingPIN)
                                .textFieldStyle(.roundedBorder)

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

                    Picker("", selection: $store.outputFormat) {
                        ForEach(SigningOutputFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
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
        }
    }
}
