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

    func makeNSView(context: Context) -> PDFPreviewContainerView {
        let view = PDFPreviewContainerView()
        view.pdfView.autoScales = true
        view.overlay.onPlacementChange = { [weak coordinator = context.coordinator] placement in
            coordinator?.placementBinding?.wrappedValue = placement
        }
        context.coordinator.overlay = view.overlay
        observePDFView(view.pdfView, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: PDFPreviewContainerView, context: Context) {
        let coordinator = context.coordinator
        coordinator.placementBinding = _placement
        if coordinator.loadedURL != url {
            nsView.pdfView.document = PDFDocument(url: url)
            coordinator.loadedURL = url
        }
        nsView.overlay.placement = placement
        nsView.overlay.cardPreview = cardPreview
        nsView.overlay.refresh()
    }

    static func dismantleNSView(_ nsView: PDFPreviewContainerView, coordinator: Coordinator) {
        nsView.pdfView.document = nil
    }

    private func observePDFView(_ pdfView: PDFView, coordinator: Coordinator) {
        let center = NotificationCenter.default
        center.addObserver(coordinator, selector: #selector(Coordinator.refreshOverlay), name: .PDFViewScaleChanged, object: pdfView)
        center.addObserver(coordinator, selector: #selector(Coordinator.refreshOverlay), name: .PDFViewPageChanged, object: pdfView)
        center.addObserver(coordinator, selector: #selector(Coordinator.refreshOverlay), name: .PDFViewDocumentChanged, object: pdfView)
    }

}

final class PDFPreviewContainerView: NSView {
    let pdfView = PDFView()
    let overlay = PDFPlacementOverlayView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        pdfView.frame = bounds
        pdfView.autoresizingMask = [.width, .height]
        overlay.frame = bounds
        overlay.autoresizingMask = [.width, .height]
        overlay.pdfView = pdfView
        addSubview(pdfView)
        addSubview(overlay, positioned: .above, relativeTo: pdfView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let pointInOverlay = overlay.convert(point, from: self)
        if overlay.hitTest(pointInOverlay) != nil {
            return overlay
        }
        return super.hitTest(point)
    }
}
