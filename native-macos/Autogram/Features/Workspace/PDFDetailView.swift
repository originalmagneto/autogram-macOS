import SwiftUI

struct PDFDetailView: View {
    let item: PDFItem?

    var body: some View {
        if let item {
            PDFPreviewView(url: item.descriptor.sourceURL)
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
