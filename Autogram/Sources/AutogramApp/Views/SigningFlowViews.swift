import SwiftUI
import PDFKit
import AutogramKit
import UniformTypeIdentifiers

struct SigningFlowView: View {
    @Bindable var store: SigningSessionStore
    @State private var isTargeted = false

    init(signingProvider: any QualifiedSigningProviding, settings: AppSettings = .standard) {
        _store = Bindable(wrappedValue: SigningSessionStore(signingProvider: signingProvider,
                                                            settings: settings))
    }

    var body: some View {
        VStack(spacing: 0) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .principal) { headerBar }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if isTargeted { targetedOverlay }
        }
        .onDrop(of: [UTType.pdf, .jpeg, .png, .tiff], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .task { await store.refreshIdentities() }
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
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await store.loadDocument(at: url)
            }
        }
    }
}

struct SigningPrepareView: View {
    @Bindable var store: SigningSessionStore

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
    }

    private var previewColumn: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                if let document = store.document {
                    PDFKitPreview(document: document)
                }
                GeometryReader { geometry in
                    Canvas { context, _ in
                        if store.includeVisibleSignature {
                            let rect = CGRect(x: store.signatureRect.x * geometry.size.width,
                                              y: store.signatureRect.y * geometry.size.height,
                                              width: store.signatureRect.width * geometry.size.width,
                                              height: store.signatureRect.height * geometry.size.height)
                            context.stroke(Path(roundedRect: rect, cornerRadius: 3),
                                           with: .color(.accentColor),
                                           lineWidth: 2)
                            context.fill(Path(roundedRect: rect, cornerRadius: 3),
                                         with: .color(.accentColor.opacity(0.12)))
                        }
                    }
                    .gesture(DragGesture().onChanged { value in
                        guard store.includeVisibleSignature else { return }
                        let w = store.signatureRect.width
                        let h = store.signatureRect.height
                        store.signatureRect.x = min(max(value.location.x / geometry.size.width - w / 2, 0), 1 - w)
                        store.signatureRect.y = min(max(value.location.y / geometry.size.height - h / 2, 0), 1 - h)
                    })
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

    private var tokenStatusLine: some View {
        let tokens = KeychainIdentityScanner.connectedTokenNames()
        return Group {
            if tokens.isEmpty {
                Label("Nie je vložená žiadna karta s certifikátmi.",
                      systemImage: "creditcard")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Label("Karty: \(tokens.joined(separator: ", "))",
                      systemImage: "creditcard.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
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

                GroupBox("Certifikát") {
                    certificateSection
                }

                GroupBox("Parametre") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $store.includeQualifiedTimestamp) {
                            Label("Kvalifikovaná časová pečiatka (QTS)", systemImage: "clock.badge.checkmark")
                        }
                        Toggle(isOn: $store.convertToPDFA) {
                            Label("Konvertovať do PDF/A pred podpisom", systemImage: "doc.badge.arrow.up")
                        }
                        if store.convertToPDFA {
                            Text("Dokument sa pred podpisom prevedie do PDF/A-2b (\(store.settings.pdfaMode.rawValue)). Režim konverzie zmeníš v Nastavenia › Konverzia PDF/A.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Toggle(isOn: $store.includeVisibleSignature) {
                            Label("Vizuálny podpis v dokumente", systemImage: "rectangle.and.pencil.and.ellipsis")
                        }
                        .toggleStyle(.switch)

                        LabeledRow(label: "Formát výstupu") {
                            Picker("", selection: $store.outputFormat) {
                                ForEach(SigningOutputFormat.allCases) { format in
                                    Text(format.rawValue).tag(format)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 220)
                        }

                        if store.includeVisibleSignature {
                            LabeledRow(label: "Strana") {
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
            .padding(16)
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

struct SigningDoneView: View {
    let store: SigningSessionStore

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.13))
                    .frame(width: 128, height: 128)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(Color.green.gradient)
            }
            VStack(spacing: 6) {
                Text("Dokument bol podpísaný")
                    .font(.title.weight(.semibold))
                if let result = store.result {
                    Text(result.signatureLabel + (result.isLegallyBinding ? "" : " — DEMO režim"))
                        .font(.callout)
                        .foregroundStyle(result.isLegallyBinding ? Color.secondary : Color.orange)
                }
            }
            if let directory = store.outputDirectory {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Uložené do:").font(.subheadline.weight(.semibold))
                    Text(directory.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .glassCard(cornerRadius: 14, padding: 12)

                HStack(spacing: 12) {
                    Button {
                        NSWorkspace.shared.open(directory)
                    } label: {
                        Label("Otvoriť vo Finderi", systemImage: "folder")
                    }
                    Button {
                        store.reset()
                        store.step = .intake
                    } label: {
                        Label("Nový podpis", systemImage: "plus")
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

import AppKit
