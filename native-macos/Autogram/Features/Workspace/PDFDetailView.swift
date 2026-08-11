import AppKit
import SwiftUI

struct PDFDetailView: View {
    let item: PDFItem?
    let workspace: WorkspaceModel

    var visibleSignaturePlacement: Binding<VisibleSignaturePlacement?> {
        Binding(
            get: { workspace.visibleSignaturePlacement },
            set: { workspace.updateVisibleSignaturePlacement($0) }
        )
    }

    var cardPreview: NSImage? {
        workspace.visibleSignatureCardPreview
    }

    var body: some View {
        if let item {
            VStack(spacing: 0) {
                if item.descriptor.isPDF {
                    PDFPreviewView(
                        url: item.descriptor.sourceURL,
                        placement: visibleSignaturePlacement,
                        cardPreview: cardPreview
                    )
                } else {
                    ASiCContentsView(inspection: item.inspection)
                }
            }
            .navigationTitle(item.descriptor.redactedDisplayName)
            .onAppear {
                workspace.updateVisibleSignatureDocument()
            }
            .onChange(of: item.descriptor.sourceURL) {
                workspace.updateVisibleSignatureDocument()
            }
        } else {
            ContentUnavailableView {
                Label("No PDF Selected", systemImage: "doc.richtext")
            } description: {
                Text("Select a PDF from the sidebar to preview it.")
            }
        }
    }
}

private struct ASiCContentsView: View {
    let inspection: PDFItemInspection

    var body: some View {
        GroupBox("ASiC-E Contents") {
            switch inspection {
            case .pending:
                ProgressView("Inspecting container")
            case .failed:
                ContentUnavailableView(
                    "ASiC inspection failed",
                    systemImage: "exclamationmark.triangle"
                )
            case .completed(let document):
                ForEach(document.documents, id: \.self) { name in
                    Label(name, systemImage: "doc")
                }
            }
        }
        .padding()
    }
}
