import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct VisibleAppearanceInspector: View {
    let workspace: WorkspaceModel

    var body: some View {
        Section("Graphic signature") {
            Toggle("Show signature on document", isOn: Binding(
                get: { workspace.visibleSignatureEnabled },
                set: { workspace.setVisibleSignatureEnabled($0) }
            ))
            if let url = workspace.visibleSignatureArtworkURL,
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 96)
            } else {
                Text("Choose PNG or PDF artwork to add a graphic signature.")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Choose PNG or PDF") {
                    chooseArtwork()
                }
                Button("Remove artwork", role: .destructive) {
                    workspace.removeVisibleSignatureArtwork()
                }
                .disabled(workspace.visibleSignatureAsset == nil)
            }
            pageSelector
            Button("Reset placement") {
                workspace.resetVisibleSignaturePlacement()
            }
            .disabled(workspace.visibleSignaturePlacement == nil)
            Text("Drag, resize, or rotate the card directly on the page.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var pageSelector: some View {
        Picker("Page", selection: Binding(
            get: { workspace.visibleSignaturePlacement?.pageIndex ?? 0 },
            set: { workspace.selectVisibleSignaturePage($0) }
        )) {
            ForEach(workspace.visibleSignaturePageIndices, id: \.self) { pageIndex in
                Text("Page \(pageIndex + 1)").tag(pageIndex)
            }
        }
        .disabled(workspace.visibleSignaturePlacement == nil || workspace.visibleSignaturePageCount == 0)
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
                try workspace.importVisibleSignatureArtwork(
                    from: url,
                    pdfPageIndex: selectedPDFPageIndex(for: url)
                )
            } catch {
                workspace.setVisibleSignatureError(error)
            }
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
