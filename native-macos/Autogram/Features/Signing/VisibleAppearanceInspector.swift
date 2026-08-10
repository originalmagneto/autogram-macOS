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
            placementControls
            Button("Reset placement") {
                workspace.resetVisibleSignaturePlacement()
            }
            .disabled(workspace.visibleSignaturePlacement == nil)
            Text("Drag, resize, or rotate the card directly on the page.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var placementControls: some View {
        Group {
            placementField("Page", keyPath: \.pageIndex, offset: 1)
            placementField("X", keyPath: \.pageRect.origin.x)
            placementField("Y", keyPath: \.pageRect.origin.y)
            placementField("Width", keyPath: \.pageRect.size.width)
            placementField("Height", keyPath: \.pageRect.size.height)
            placementField("Rotation", keyPath: \.rotationDegrees)
        }
        .disabled(workspace.visibleSignaturePlacement == nil)
    }

    private func placementField(
        _ title: String,
        keyPath: WritableKeyPath<VisibleSignaturePlacement, CGFloat>
    ) -> some View {
        TextField(title, value: Binding(
            get: { Double(workspace.visibleSignaturePlacement?[keyPath: keyPath] ?? 0) },
            set: { value in
                guard var placement = workspace.visibleSignaturePlacement else { return }
                placement[keyPath: keyPath] = CGFloat(value)
                workspace.updateVisibleSignaturePlacement(placement)
            }
        ), format: .number)
    }

    private func placementField(
        _ title: String,
        keyPath: WritableKeyPath<VisibleSignaturePlacement, Double>
    ) -> some View {
        TextField(title, value: Binding(
            get: { workspace.visibleSignaturePlacement?[keyPath: keyPath] ?? 0 },
            set: { value in
                guard var placement = workspace.visibleSignaturePlacement else { return }
                placement[keyPath: keyPath] = value
                workspace.updateVisibleSignaturePlacement(placement)
            }
        ), format: .number)
    }

    private func placementField(
        _ title: String,
        keyPath: WritableKeyPath<VisibleSignaturePlacement, Int>,
        offset: Int
    ) -> some View {
        TextField(title, value: Binding(
            get: { (workspace.visibleSignaturePlacement?[keyPath: keyPath] ?? 0) + offset },
            set: { value in
                guard var placement = workspace.visibleSignaturePlacement else { return }
                placement[keyPath: keyPath] = value - offset
                workspace.updateVisibleSignaturePlacement(placement)
            }
        ), format: .number)
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
