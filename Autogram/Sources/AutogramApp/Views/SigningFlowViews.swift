import SwiftUI
import PDFKit
import AutogramKit
import UniformTypeIdentifiers

struct SigningFlowView: View {
    @Bindable var store: SigningSessionStore
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .principal) { headerBar }
        }
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
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
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
            .padding(10)
            .allowsHitTesting(false)
    }

    private var headerBar: some View {
        HStack(spacing: 14) {
            ForEach(Array(SigningSessionStore.Step.allCases.enumerated()), id: \.element) { _, stepCase in
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
        .padding(.horizontal, 8)
    }

    private func title(for step: SigningSessionStore.Step) -> String {
        switch step {
        case .intake: return "Dokument"
        case .prepare: return "Podpis"
        case .done: return "Hotovo"
        }
    }

    private func symbol(for step: SigningSessionStore.Step) -> String {
        switch step {
        case .intake: return "doc.badge.plus"
        case .prepare: return "signature"
        case .done: return "checkmark.seal.fill"
        }
    }

    private func pillState(_ step: SigningSessionStore.Step) -> StepperPill.StepState {
        if step.rawValue < store.step.rawValue { return .complete }
        if step == store.step { return .active }
        return .pending
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

struct SigningIntakeView: View {
    let store: SigningSessionStore

    private var isDemoProvider: Bool {
        store.signingProvider is DemoSigningProvider
    }

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
                Image(systemName: "signature")
                    .font(.system(size: 50, weight: .light))
                    .foregroundStyle(Color.accentColor.gradient)
            }
            VStack(spacing: 6) {
                Text("Pretiahnite dokument na podpísanie")
                    .font(.title2.weight(.semibold))
                Text("PDF dokument. Autogram ho podpíše kvalifikovaným elektronickým podpisom (KEP) s voliteľnou časovou pečiatkou.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            Button {
                openPanel()
            } label: {
                Label("Vybrať súbor…", systemImage: "folder")
                    .frame(minWidth: 140)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.glassProminent)

            if isDemoProvider {
                Label("Demo režim podpisu — pre KEP pripojte Autogram službu alebo kartu",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            Task { @MainActor in
                await store.addDocuments(at: panel.urls)
            }
        }
    }
}

struct SigningPrepareView: View {
    @Bindable var store: SigningSessionStore
    @State private var customTSADraft = ""
    @State private var visualState: SignaturePlacementState?
    @State private var bridgePlacement: VisibleSignaturePlacement?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            previewColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            settingsColumn
                .frame(width: 340)
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

    /// Grafická karta v náhľade reflektuje konkrétny certifikát, ktorým sa podpisuje.
    /// Pred načítaním certifikátu zobrazuje neutrálne miesto opisu.
    private func refreshVisualCardContent() {
        guard let visualState else { return }
        let identity = store.identities.first(where: { $0.id == store.selectedIdentityID })
        guard store.hasResolvedCertificate, let identity else {
            if let error = store.certificateLoadError {
                visualState.setContent(signerName: "Certifikát sa nenačítal",
                                       qualification: error)
            } else if store.isResolvingCertificate {
                visualState.setContent(signerName: "Načítavam certifikát…",
                                       qualification: nil)
            } else {
                visualState.setContent(signerName: "Podpisový certifikát",
                                       qualification: "Načítajte certifikát v paneli PIN")
            }
            return
        }
        visualState.setContent(
            signerName: identity.label,
            qualification: identity.isQualified
                ? "Kvalifikovaný elektronický podpis"
                : "Nekvalifikovaný certifikát")
    }

    /// Grafický podpis komponovaný priamo na stránke (port Autogram macOS 2).
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
                height: Double(rect.height / cropBox.height))
        }
        if let state = visualState, let asset = state.selectedAsset {
            // Pass only the original artwork. cardPreview already contains the outer card.
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
                        PDFPreviewView(document: document,
                                       placement: Binding(
                                           get: { store.includeVisibleSignature ? bridgePlacement : nil },
                                           set: { bridgePlacement = $0 }),
                                       cardPreview: visualState?.cardPreview)
                    } else {
                        PDFKitPreview(document: document, stampState: nil)
                    }
                }
            }
            .glassCard(padding: 6)

            HStack(spacing: 10) {
                StatChip(title: "Strany", value: "\(store.analysis.totalPages)", symbol: "doc.on.doc", tint: .blue)
                Spacer()
                Text(store.sourceURL?.lastPathComponent ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.trailing)
                    .help(store.sourceURL?.lastPathComponent ?? "")
            }
        }
        .padding(14)
    }

    private var stampImage: NSImage? {
        guard let data = VisualSignatureStore.imageData(for: store.selectedVisualAppearanceID) else { return nil }
        return NSImage(data: data)
    }

    private var tokenStatusLine: some View {
        Group {
            if store.identities.isEmpty {
                Label("Karta nie je detegovaná — vložte eID alebo advokátsky preukaz.",
                      systemImage: "creditcard")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Label("Karta je pripojená. Obnova každých pár sekúnd.",
                      systemImage: "creditcard.fill")
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
                Text("Dokument zatiaľ nemá elektronický podpis. Podpísať KEP pridá prvý podpis; ďalším podpisom môžete pridať aj druhý (PAdES prírastok).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(store.existingSignatures) { signature in
                    SignatureInfoRow(info: signature)
                }
                Text("Podpísať KEP pridá ďalší podpis do tohto istého dokumentu, existujúce ostanú.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(4)
    }

    private var certificateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            tokenStatusLine

            if store.identities.isEmpty {
                Label("Žiadny certifikát k dispozícii — pripojte kartu (eID alebo advokátsky preukaz).",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if store.signingProvider is DemoSigningProvider {
                    Label("Bez karty beží DEMO režim — podpis nie je právne záväzný.",
                          systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                ForEach(store.identities) { identity in
                    IdentityRow(identity: identity,
                                isSelected: store.selectedIdentityID == identity.id,
                                onSelect: { store.selectedIdentityID = identity.id })
                }
            }
        }
        .padding(4)
    }

    private var settingsColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("Nastavenia podpisu", systemImage: "signature")
                    .font(.headline)

                GroupBox("Existujúce podpisy") {
                    existingSignaturesSection
                }

                GroupBox("Certifikát") {
                    certificateSection
                }

                if let selected = store.identities.first(where: { $0.id == store.selectedIdentityID }),
                   selected.requiresPIN {
                    GroupBox("PIN karty") {
                        SecureField("PIN", text: $store.signingPIN)
                            .textFieldStyle(.roundedBorder)
                        Text("PIN sa používa len na toto podpisovanie a neukladá sa.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("Pri eID sa natívny BOK dialóg zobrazí až počas podpisovania.")
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
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !store.hasResolvedCertificate, !store.signingProviderIsDemo {
                            Button {
                                Task { await store.resolveCertificateForPreview(force: true) }
                            } label: {
                                Label("Načítať certifikát pre náhľad", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.small)
                            .disabled(store.signingPIN.isEmpty || store.isResolvingCertificate)
                        }
                    }
                }

                GroupBox("Parametre") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Formát výstupu")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: $store.outputFormat) {
                                ForEach(SigningOutputFormat.allCases) { format in
                                    Text(format.rawValue).tag(format)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 276)
                        }

                        Toggle(isOn: $store.includeQualifiedTimestamp) {
                            Label("Časová pečiatka (TSA)", systemImage: "clock.badge.checkmark")
                        }
                        if store.includeQualifiedTimestamp {
                            timestampPicker
                        }

                        Toggle(isOn: $store.convertToPDFA) {
                            Label("Konvertovať do PDF/A pred podpisom", systemImage: "doc.badge.arrow.up")
                        }
                        if store.convertToPDFA {
                            Picker("", selection: $store.pdfaMode) {
                                ForEach(PDFAConversionMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 276)
                        }

                        Toggle(isOn: $store.includeVisibleSignature) {
                            Label("Vizuálny podpis v dokumente", systemImage: "rectangle.and.pencil.and.ellipsis")
                        }
                        .toggleStyle(.switch)

                        if store.includeVisibleSignature, let visualState {
                            VisibleAppearanceInspector(state: visualState)
                                .frame(width: 276)
                        }

                        if false {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Strana vizuálneho podpisu")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Stepper("\(store.signaturePage + 1)",
                                        value: $store.signaturePage,
                                        in: 0...max(store.analysis.totalPages - 1, 0))
                                    .font(.callout.monospacedDigit())
                            }
                            Text("Rámček vizuálneho podpisu potiahnite priamo v náhľade dokumentu.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(4)
                }

                if let error = store.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                HStack {
                    Button {
                        store.reset()
                        store.step = .intake
                    } label: {
                        Label("Iný dokument", systemImage: "chevron.left")
                    }
                    Spacer()
                    signButton
                }
                .padding(.top, 6)
            }
            .frame(width: 308)
            .padding(.vertical, 16)
        }
    }

    private var timestampPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: $store.selectedTSAURL) {
                ForEach(store.settings.availableTSAServers) { server in
                    Text(server.isQualified ? server.name : "\(server.name)")
                        .tag(server.url)
                }
            }
            .labelsHidden()
            .frame(width: 276)
            if let active = store.settings.availableTSAServers.first(where: { $0.url == store.selectedTSAURL }) {
                Text(active.isQualified
                     ? "Kvalifikovaná TSA (eIDAS)."
                     : "Nekvalifikovaná TSA — podpisuj.sk ju neuzná ako QTS.")
                    .font(.caption2)
                    .foregroundStyle(active.isQualified ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                TextField("https://vlastna-tsa/…", text: $customTSADraft)
                    .textFieldStyle(.roundedBorder)
                Button("Pridať") {
                    store.addCustomTSA(customTSADraft)
                    customTSADraft = ""
                }
                .disabled(customTSADraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var visualSignaturePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Vzhľad podpisu")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $store.selectedVisualAppearanceID) {
                ForEach(VisualSignatureStore.items()) { item in
                    Text(item.name).tag(item.id)
                }
            }
            .labelsHidden()
            .frame(width: 276)
            visualAppearancePreview
            Button("Pridať obrázok podpisu…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
                panel.canChooseFiles = true
                panel.allowsMultipleSelection = false
                panel.message = "Vyber PNG/JPEG s vizuálnym podpisom."
                if panel.runModal() == .OK, let url = panel.url,
                   let id = VisualSignatureStore.importImage(from: url) {
                    store.selectedVisualAppearanceID = id
                }
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private var visualAppearancePreview: some View {
        if let data = VisualSignatureStore.imageData(for: store.selectedVisualAppearanceID),
           let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 276, maxHeight: 72)
                .padding(6)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        } else {
            Text("Textový vizuál: meno, dátum a označenie KEP.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!store.canSign)
    }
}

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
        case .indeterminate: "Dočasný / neurčitý"
        case .unknown: "Neoverené"
        }
    }
}

struct SigningDoneView: View {
    let store: SigningSessionStore

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            previewColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            resultColumn
                .frame(width: 340)
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
                    ContentUnavailableView("Náhľad podpísaného súboru",
                                           systemImage: "doc.richtext",
                                           description: Text("Súbor otvorte vo Finderi alebo v Náhľade."))
                }
            }
            .glassCard(padding: 6)
            if let url = store.signedOutputURL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    private var resultColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("Podpis je uložený", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                if let result = store.result {
                    Text(result.signatureLabel + (result.isLegallyBinding ? "" : " — DEMO režim"))
                        .font(.callout)
                        .foregroundStyle(result.isLegallyBinding ? Color.secondary : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                GroupBox("PDF/A") {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(store.pdfaPrepared ? "Pred podpisom: PDF/A pripravené" : "Pred podpisom: bez konverzie",
                              systemImage: store.pdfaPrepared ? "checkmark.circle.fill" : "minus.circle")
                            .font(.caption)
                            .foregroundStyle(store.pdfaPrepared ? .green : .secondary)
                        Label(store.pdfaAfterSign ? "Po podpise: PDF/A zachované" : "Po podpise: nie je PDF/A (PAdES prírastok to často zruší)",
                              systemImage: store.pdfaAfterSign ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(store.pdfaAfterSign ? .green : .orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(4)
                }

                GroupBox("Podpisy v súbore") {
                    VStack(alignment: .leading, spacing: 8) {
                        if store.resultSignatures.isEmpty {
                            Text("Engine nenašiel čitateľný podpis na kontrolu — otvorte súbor v Náhľade.")
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

                if let url = store.signedOutputURL {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Otvoriť podpísaný súbor", systemImage: "doc.richtext")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Label("Ukázat vo Finderi", systemImage: "folder")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

                Button {
                    store.reset()
                    store.step = .intake
                } label: {
                    Label("Nový podpis", systemImage: "plus")
                }
            }
            .frame(width: 308)
            .padding(.vertical, 16)
        }
    }
}

import AppKit
