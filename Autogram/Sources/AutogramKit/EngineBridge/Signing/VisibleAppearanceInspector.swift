import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Panel vizuálneho podpisu s výberom grafickej pečiatky a nastavením strany.
public struct VisibleAppearanceInspector: View {
    @Bindable var state: SignaturePlacementState

    public init(state: SignaturePlacementState) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Zobraziť vizuálnu pečiatku v PDF", isOn: Binding(
                get: { state.isEnabled },
                set: { state.setEnabled($0) }
            ))
            .disabled(state.selectedAsset == nil)

            if state.assets.isEmpty {
                Text("Vyberte obrázok podpisu (PNG, JPEG alebo PDF).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
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
                                    ? Color.accentColor.opacity(0.25)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(
                                        state.selectedAsset?.id == asset.id
                                            ? Color.accentColor
                                            : Color.primary.opacity(0.08),
                                        lineWidth: 1
                                    )
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 64)
            }

            HStack(spacing: 8) {
                Button {
                    chooseArtwork()
                } label: {
                    Label("Pridať obrázok…", systemImage: "plus")
                }
                .controlSize(.small)

                if state.selectedAsset != nil {
                    Button(role: .destructive) {
                        deleteSelectedArtwork()
                    } label: {
                        Label("Zmazať", systemImage: "trash")
                    }
                    .controlSize(.small)
                }
            }

            if state.pageCount > 1 {
                pageSelector
            }

            if state.placement != nil {
                HStack {
                    Button {
                        state.resetRotation()
                    } label: {
                        Label("Obnoviť pozíciu", systemImage: "arrow.counterclockwise")
                    }
                    .controlSize(.small)
                }
            }

            Text("Pozíciu, veľkosť a rotáciu pečiatky upravíte priamo na plátne dokumentu.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var pageSelector: some View {
        Picker("Strana", selection: Binding(
            get: { state.placement?.pageIndex ?? 0 },
            set: { state.selectPage($0) }
        )) {
            ForEach(state.pageIndices, id: \.self) { pageIndex in
                Text("Strana \(pageIndex + 1)").tag(pageIndex)
            }
        }
        .disabled(state.placement == nil || state.pageCount == 0)
        .pickerStyle(.menu)
    }

    private func chooseArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .pdf]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Vyberte obrázok alebo vektorovú pečiatku podpisu."
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
                .frame(width: 80, height: 50)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: "photo")
                .frame(width: 80, height: 50)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
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
        alert.messageText = "Výber strany PDF pečiatky"
        alert.informativeText = "Zadajte číslo strany z PDF, ktorú chcete použiť."
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
