import PDFKit
import SwiftUI

struct PDFPreviewView: NSViewRepresentable {
    let url: URL

    final class Coordinator {
        var loadedURL: URL?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        nsView.document = PDFDocument(url: url)
        context.coordinator.loadedURL = url
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        nsView.document = nil
    }
}
