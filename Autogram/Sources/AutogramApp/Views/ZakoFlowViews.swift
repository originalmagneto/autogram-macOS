import SwiftUI
import AutogramKit
import PDFKit
import UniformTypeIdentifiers
import AppKit

struct ZakoFlowView: View {
    @Bindable var store: ZakoSessionStore
    @State private var showOpenPanel = false
    @State private var isTargeted = false

    private var steps: [(title: String, symbol: String)] {
        [
            ("Vstupný dokument", "doc.badge.plus"),
            ("Overenie originálu", "shield.checkerboard"),
            ("Osvedčovacia doložka", "building.columns.fill"),
            ("Autorizácia KEP", "signature.badge.checkmark"),
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
        .toolbar {
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
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
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
            IntakeView(store: store, showOpenPanel: $showOpenPanel)
        case .analysis:
            AnalysisCanvasView(store: store)
        case .attestation:
            AttestationFormView(store: store)
                .task(id: store.currentRecordID) {
                    await store.preparePreflight()
                }
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

// MARK: - Intake View for ZaKo
struct IntakeView: View {
    let store: ZakoSessionStore
    @Binding var showOpenPanel: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            DropzoneArtwork(icon: "arrow.down.doc.fill", tint: .indigo)

            VStack(spacing: 8) {
                Text("Pretiahnite naskenovaný papierový dokument")
                    .font(.title2.weight(.bold))

                Text("Originál alebo úradne osvedčená kópia vo formáte PDF. Autogram automaticky analyzuje strany, listy a bezpečnostné prvky podľa § 35-39 zákona č. 305/2013 Z. z.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
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
                .keyboardShortcut("o", modifiers: [.command, .option])
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.indigo)
            }

            HStack(spacing: 16) {
                Label("Automatická AI detekcia", systemImage: "brain.head.profile")
                Label("Výpočet SHA-256 odtlačku", systemImage: "number.square")
                Label("Osvedčovacia doložka", systemImage: "building.columns")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.top, 4)

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
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Vyberte naskenovaný dokument na zaručenú konverziu."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await store.loadDocument(at: url)
            }
        }
    }
}

// MARK: - PDFKit Preview Wrapper
struct PDFKitPreview: NSViewRepresentable {
    let document: PDFDocument
    var stampState: StampOverlayState? = nil

    struct StampOverlayState {
        var rect: NormalizedRect
        var pageIndex: Int
        var image: NSImage?
        var title: String
        var onChange: (NormalizedRect) -> Void
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = document
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
        }
    }
}
