import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Panel „Grafický podpis" – port z Autogram macOS 2, viazaný na SignaturePlacementState.
public struct VisibleAppearanceInspector: View {
    @Bindable var state: SignaturePlacementState

    public init(state: SignaturePlacementState) {
        self.state = state
    }

    public var body: some View {
        Section("Graphic signature") {
            Toggle("Show signature on document", isOn: Binding(
                get: { state.isEnabled },
                set: { state.setEnabled($0) }
            ))
            .disabled(state.selectedAsset == nil)
            if state.assets.isEmpty {
                Text("Choose PNG or PDF artwork to add a graphic signature.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(state.assets) { asset in
                            Button {
                                state.select(asset)
                            } label: {
                                artworkThumbnail(for: asset)
                            }
                            .buttonStyle(.plain)
                            .padding(3)
                            .background(
                                state.selectedAsset?.id == asset.id
                                    ? Color.accentColor.opacity(0.22)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                        }
                    }
                }
                .frame(height: 70)
            }
            HStack {
                Button("Choose PNG or PDF") {
                    chooseArtwork()
                }
                Button("Delete artwork", role: .destructive) {
                    deleteSelectedArtwork()
                }
                .disabled(state.selectedAsset == nil)
            }
            pageSelector
            Button("Reset placement") {
                state.resetRotation()
            }
            .disabled(state.placement == nil)
            Text("Drag, resize, or rotate the card directly on the page.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var pageSelector: some View {
        Picker("Page", selection: Binding(
            get: { state.placement?.pageIndex ?? 0 },
            set: { state.selectPage($0) }
        )) {
            ForEach(state.pageIndices, id: \.self) { pageIndex in
                Text("Page \(pageIndex + 1)").tag(pageIndex)
            }
        }
        .disabled(state.placement == nil || state.pageCount == 0)
    }

    private func chooseArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .pdf]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try state.importArtwork(from: url,
                                        pdfPageIndex: selectedPDFPageIndex(for: url))
            } catch {
                NSLog("VisibleAppearance import failed: \(error.localizedDescription)")
            }
        }
    }

    @ViewBuilder
    private func artworkThumbnail(for asset: SignatureAsset) -> some View {
        if let image = NSImage(contentsOf: state.artworkURL(for: asset)) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 58)
        } else {
            Image(systemName: "photo")
                .frame(width: 88, height: 58)
        }
    }

    private func deleteSelectedArtwork() {
        guard let asset = state.selectedAsset else { return }
        do {
            try state.delete(asset)
        } catch {
            NSLog("VisibleAppearance delete failed: \(error.localizedDescription)")
        }
    }

    private func selectedPDFPageIndex(for url: URL) -> Int {
        guard url.pathExtension.lowercased() == "pdf",
              let document = PDFDocument(url: url),
              document.pageCount > 1 else {
            return 0
        }
        let alert = NSAlert()
        alert.messageText = "Choose PDF artwork page"
        alert.informativeText = "Enter the page number to import."
        let field = NSTextField(string: "1")
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn,
              let page = Int(field.stringValue),
              document.page(at: page - 1) != nil else {
            return 0
        }
        return page - 1
    }
}
