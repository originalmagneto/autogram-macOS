import SwiftUI

struct PDFDetailView: View {
    let item: PDFItem?

    var body: some View {
        if let item {
            VStack(spacing: 0) {
                if item.descriptor.isPDF {
                    PDFPreviewView(url: item.descriptor.sourceURL)
                } else {
                    ASiCContentsView(inspection: item.inspection)
                }
            }
            .navigationTitle(item.descriptor.redactedDisplayName)
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
            if case .completed(let document) = inspection {
                ForEach(document.documents, id: \.self) { name in
                    Label(name, systemImage: "doc")
                }
            } else {
                Text("Inspecting container contents…")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
