import PDFKit
import SwiftUI

struct PDFPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = PDFDocument(url: url)
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: ()) {
        nsView.document = nil
    }
}
