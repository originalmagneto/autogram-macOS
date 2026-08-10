import PDFKit
import SwiftUI

struct PDFPreviewView: NSViewRepresentable {
    let url: URL
    @Binding var placement: VisibleSignaturePlacement?
    let cardPreview: NSImage?

    @MainActor
    final class Coordinator: NSObject {
        var loadedURL: URL?
        weak var overlay: PDFPlacementOverlayView?
        var placementBinding: Binding<VisibleSignaturePlacement?>?

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc func refreshOverlay() {
            overlay?.refresh()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        observePDFView(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        let coordinator = context.coordinator
        coordinator.placementBinding = _placement
        if coordinator.loadedURL != url {
            nsView.document = PDFDocument(url: url)
            coordinator.loadedURL = url
        }
        installOverlay(in: nsView, coordinator: coordinator)
        coordinator.overlay?.placement = placement
        coordinator.overlay?.cardPreview = cardPreview
        coordinator.overlay?.refresh()
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        nsView.document = nil
    }

    private func observePDFView(_ pdfView: PDFView, coordinator: Coordinator) {
        let center = NotificationCenter.default
        center.addObserver(coordinator, selector: #selector(Coordinator.refreshOverlay), name: .PDFViewScaleChanged, object: pdfView)
        center.addObserver(coordinator, selector: #selector(Coordinator.refreshOverlay), name: .PDFViewPageChanged, object: pdfView)
        center.addObserver(coordinator, selector: #selector(Coordinator.refreshOverlay), name: .PDFViewDocumentChanged, object: pdfView)
    }

    private func installOverlay(in pdfView: PDFView, coordinator: Coordinator) {
        guard let documentView = pdfView.documentView else { return }
        if coordinator.overlay?.superview !== documentView {
            let overlay = PDFPlacementOverlayView(frame: documentView.bounds)
            overlay.autoresizingMask = [.width, .height]
            overlay.pdfView = pdfView
            overlay.onPlacementChange = { [weak coordinator] placement in
                coordinator?.placementBinding?.wrappedValue = placement
            }
            documentView.addSubview(overlay)
            coordinator.overlay = overlay
        }
    }
}
