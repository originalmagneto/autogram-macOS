import PDFKit
import SwiftUI

public struct PDFPreviewView: NSViewRepresentable {
    public var url: URL
    @Binding public var placement: VisibleSignaturePlacement?
    public var cardPreview: NSImage?
    var preloadDocument: PDFDocument?

    @MainActor
    public final class Coordinator: NSObject {
        var loadedURL: URL?
        weak var overlay: PDFPlacementOverlayView?
        weak var pdfView: PDFView?
        var placementBinding: Binding<VisibleSignaturePlacement?>?

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc func refreshOverlay() {
            overlay?.refresh()
        }

        func observe(_ pdfView: PDFView) {
            NotificationCenter.default.removeObserver(self)
            self.pdfView = pdfView
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(refreshOverlay), name: .PDFViewScaleChanged, object: pdfView)
            center.addObserver(self, selector: #selector(refreshOverlay), name: .PDFViewPageChanged, object: pdfView)
            center.addObserver(self, selector: #selector(refreshOverlay), name: .PDFViewDocumentChanged, object: pdfView)
            attachScrollObservers(on: pdfView)
        }

        func attachScrollObservers(on pdfView: PDFView) {
            let center = NotificationCenter.default
            if let scroll = pdfView.subviews.compactMap({ $0 as? NSScrollView }).first {
                let clip = scroll.contentView
                clip.postsBoundsChangedNotifications = true
                center.addObserver(self, selector: #selector(refreshOverlay),
                                   name: NSView.boundsDidChangeNotification, object: clip)
                if let documentView = scroll.documentView {
                    documentView.postsFrameChangedNotifications = true
                    center.addObserver(self, selector: #selector(refreshOverlay),
                                       name: NSView.frameDidChangeNotification, object: documentView)
                }
            } else if let documentView = pdfView.documentView {
                documentView.postsBoundsChangedNotifications = true
                documentView.postsFrameChangedNotifications = true
                center.addObserver(self, selector: #selector(refreshOverlay),
                                   name: NSView.boundsDidChangeNotification, object: documentView)
                center.addObserver(self, selector: #selector(refreshOverlay),
                                   name: NSView.frameDidChangeNotification, object: documentView)
            }
        }
    }

    public init(url: URL, placement: Binding<VisibleSignaturePlacement?>, cardPreview: NSImage?) {
        self.url = url
        self._placement = placement
        self.cardPreview = cardPreview
        self.preloadDocument = nil
    }

    public init(document: PDFDocument, placement: Binding<VisibleSignaturePlacement?>, cardPreview: NSImage?) {
        self.url = URL(fileURLWithPath: "/dev/null")
        self._placement = placement
        self.cardPreview = cardPreview
        self.preloadDocument = document
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> PDFPreviewContainerView {
        let view = PDFPreviewContainerView()
        view.pdfView.autoScales = true
        view.overlay.onPlacementChange = { [weak coordinator = context.coordinator] placement in
            coordinator?.placementBinding?.wrappedValue = placement
        }
        context.coordinator.overlay = view.overlay
        context.coordinator.observe(view.pdfView)
        return view
    }

    public func updateNSView(_ nsView: PDFPreviewContainerView, context: Context) {
        let coordinator = context.coordinator
        coordinator.placementBinding = _placement
        if coordinator.loadedURL != url {
            nsView.pdfView.document = preloadDocument ?? PDFDocument(url: url)
            coordinator.loadedURL = url
            coordinator.observe(nsView.pdfView)
        }
        nsView.overlay.placement = placement
        nsView.overlay.cardPreview = cardPreview
        nsView.overlay.refresh()
    }

    public static func dismantleNSView(_ nsView: PDFPreviewContainerView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        nsView.pdfView.document = nil
    }
}

public final class PDFPreviewContainerView: NSView {
    public let pdfView = PDFView()
    public let overlay = PDFPlacementOverlayView()

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        pdfView.frame = bounds
        pdfView.autoresizingMask = [.width, .height]
        overlay.frame = bounds
        overlay.autoresizingMask = [.width, .height]
        overlay.pdfView = pdfView
        addSubview(pdfView)
        addSubview(overlay, positioned: .above, relativeTo: pdfView)
    }

    public required init?(coder: NSCoder) {
        nil
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        let pointInOverlay = overlay.convert(point, from: self)
        if overlay.hitTest(pointInOverlay) != nil {
            return overlay
        }
        return super.hitTest(point)
    }
}
