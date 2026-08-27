import SwiftUI
import AutogramKit
import PDFKit
import UniformTypeIdentifiers

struct ZakoFlowView: View {
    @Bindable var store: ZakoSessionStore
    @State private var showOpenPanel = false
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if isTargeted { targetedOverlay }
        }
        .onDrop(of: [UTType.pdf, .jpeg, .png, .tiff], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .toolbar {
            ToolbarItem(placement: .principal) { stepperBar }
            ToolbarItemGroup(placement: .primaryAction) {
                if store.isAnalyzing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(store.analysisProgressText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
    }

    private var targetedOverlay: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: 3)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
            .padding(10)
            .allowsHitTesting(false)
    }

    private var stepperBar: some View {
        HStack(spacing: 10) {
            ForEach(Array(ZakoSessionStore.Step.allCases.enumerated()), id: \.element) { _, stepCase in
                StepperPill(
                    index: stepCase.rawValue,
                    title: shortTitle(for: stepCase),
                    symbol: symbol(for: stepCase),
                    state: pillState(stepCase))
                if stepCase != .done {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .lineLimit(1)
        .allowsTightening(true)
        .minimumScaleFactor(0.72)
    }

    private var stepperBarFull: some View {
        HStack(spacing: 12) {
            ForEach(Array(ZakoSessionStore.Step.allCases.enumerated()), id: \.element) { _, stepCase in
                StepperPill(
                    index: stepCase.rawValue,
                    title: title(for: stepCase),
                    symbol: symbol(for: stepCase),
                    state: pillState(stepCase))
                if stepCase != .done {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.quaternary)
                }
            }
        }
    }

    private func shortTitle(for step: ZakoSessionStore.Step) -> String {
        switch step {
        case .intake: return "Dokument"
        case .analysis: return "Overenie"
        case .attestation: return "Doložka"
        case .authorize: return "Autorizácia"
        case .done: return "Hotovo"
        }
    }

    private func title(for step: ZakoSessionStore.Step) -> String {
        switch step {
        case .intake: return "Vstupný dokument"
        case .analysis: return "Overenie originálu"
        case .attestation: return "Osvedčovacia doložka"
        case .authorize: return "Autorizácia KEP"
        case .done: return "Hotovo"
        }
    }

    private func symbol(for step: ZakoSessionStore.Step) -> String {
        switch step {
        case .intake: return "doc.badge.plus"
        case .analysis: return "shield.checkerboard"
        case .attestation: return "building.columns.fill"
        case .authorize: return "signature.badge.checkmark"
        case .done: return "checkmark.seal.fill"
        }
    }

    private func pillState(_ step: ZakoSessionStore.Step) -> StepperPill.StepState {
        if step.rawValue < store.step.rawValue { return .complete }
        if step == store.step { return .active }
        return .pending
    }

    @ViewBuilder
    private var stepContent: some View {
        switch store.step {
        case .intake:
            IntakeView(store: store, showOpenPanel: $showOpenPanel)
        case .analysis:
            AnalysisCanvasView(store: store)
        case .attestation:
            AttestationFormView(store: store)
        case .authorize:
            AuthorizeView(store: store)
        case .done:
            DoneView(store: store)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let pdfProvider = providers.first { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }
        let imageTypes = [UTType.jpeg, .png, .tiff, .heic]
        let imageProvider = imageTypes.first { type in
            providers.contains { $0.hasItemConformingToTypeIdentifier(type.identifier) }
        }

        let isPDF = pdfProvider != nil
        let typeIdentifier = isPDF ? UTType.pdf.identifier : (imageProvider?.identifier ?? UTType.png.identifier)
        guard let provider = pdfProvider ?? providers.first else {
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            guard let data else { return }
            Task { @MainActor in
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("zako-import-\(UUID().uuidString).pdf")

                if isPDF || data.starts(with: Data("%PDF".utf8)) {
                    try? data.write(to: tempURL)
                } else if let converted = ImageToPDFConverter.pdf(fromImageData: data) {
                    try? converted.write(to: tempURL)
                } else {
                    return
                }
                await store.loadDocument(at: tempURL)
            }
        }
        return true
    }
}

struct IntakeView: View {
    let store: ZakoSessionStore
    @Binding var showOpenPanel: Bool

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 132, height: 132)
                Circle()
                    .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 158, height: 158)
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Color.accentColor.gradient)
            }
            VStack(spacing: 6) {
                Text("Pretiahnite naskenovaný papierový dokument")
                    .font(.title2.weight(.semibold))
                Text("Originál alebo úradne osvedčená kópia vo formáte PDF. Autogram automaticky rozpozná strany, listy a bezpečnostné prvky.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            HStack(spacing: 12) {
                Button {
                    openPanel()
                } label: {
                    Label("Vybrať súbor…", systemImage: "folder")
                        .frame(minWidth: 140)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)

                Button {
                    store.resetSession(keepingProfile: true)
                } label: {
                    Label("Nová konverzia", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.glass)
            }
            if let error = store.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await store.loadDocument(at: url)
            }
        }
    }
}

struct PDFKitPreview: NSViewRepresentable {
    let document: PDFDocument
    var stampState: StampOverlayState? = nil

    struct StampOverlayState {
        var rect: NormalizedRect
        var pageIndex: Int
        var image: NSImage?
        var title: String
        var onChange: (NormalizedRect) -> Void
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.minScaleFactor = 0.4
        view.maxScaleFactor = 4.0
        view.document = document
        context.coordinator.install(view: view)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
            context.coordinator.overlay = nil
        }
        context.coordinator.sync(stampState, pdfView: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        weak var pdfView: PDFView?
        var overlay: StampOverlayView?
        var state: StampOverlayState?

        func install(view: PDFView) {
            pdfView = view
        }

        func sync(_ newState: StampOverlayState?, pdfView: PDFView) {
            guard let state = newState else {
                overlay?.removeFromSuperview()
                overlay = nil
                self.state = nil
                return
            }
            self.state = state
            let overlay = self.overlay ?? StampOverlayView()
            overlay.onChange = state.onChange
            overlay.title = state.title
            overlay.image = state.image
            if !overlay.isDragging {
                overlay.update(rect: state.rect, pageIndex: state.pageIndex, pdfView: pdfView)
            }
            if overlay.superview == nil {
                let scrollView = pdfView.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView
                if let documentView = scrollView?.documentView {
                    documentView.addSubview(overlay)
                } else {
                    pdfView.addSubview(overlay)
                }
            }
            self.overlay = overlay
        }
    }
}

@MainActor
final class StampOverlayView: NSView {
    var rect: NormalizedRect = NormalizedRect(x: 0.6, y: 0.8, width: 0.3, height: 0.09)
    var pageIndex: Int = 0
    var image: NSImage?
    var title: String = ""
    var onChange: ((NormalizedRect) -> Void)?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        DispatchQueue.main.async { [weak self] in
            guard let self, let pdfView = self.ancestorPDFView() else { return }
            self.layoutIn(pdfView: pdfView)
        }
    }

    private var pageFrame: CGRect = .zero
    private var dragMode: DragMode = .none
    private var dragStartRect: NormalizedRect?
    private var dragStartLocation: NSPoint = .zero

    enum DragMode { case none, move, resize }

    var isDragging: Bool { dragMode != .none }

    override var isFlipped: Bool { true }

    func update(rect: NormalizedRect, pageIndex: Int, pdfView: PDFView) {
        self.rect = rect
        self.pageIndex = pageIndex
        needsDisplay = true
        layoutIn(pdfView: pdfView)
    }

    private func layoutIn(pdfView: PDFView) {
        guard let document = pdfView.document,
              pageIndex >= 0,
              let page = document.page(at: pageIndex) else {
            frame = .zero
            return
        }
        let inPdfView = pdfView.convert(page.bounds(for: .mediaBox), from: page)
        if let documentView = superview, documentView !== pdfView {
            pageFrame = documentView.convert(inPdfView, from: pdfView)
        } else {
            pageFrame = inPdfView
        }
        let box = boxRect()
        frame = box.integral
        needsDisplay = true
    }

    private func boxRect() -> CGRect {
        let w = max(rect.width * pageFrame.width, 60)
        let h = max(rect.height * pageFrame.height, 24)
        return CGRect(x: pageFrame.minX + rect.x * pageFrame.width,
                      y: pageFrame.minY + rect.y * pageFrame.height,
                      width: w, height: h)
    }

    override func layout() {
        super.layout()
        if let pdfView = ancestorPDFView() {
            layoutIn(pdfView: pdfView)
        }
    }

    private func ancestorPDFView() -> PDFView? {
        var responder: NSView? = self
        while let view = responder {
            if let pdfView = view as? PDFView { return pdfView }
            responder = view.superview
        }
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        dragStartLocation = location
        dragStartRect = rect
        let handleZone = CGRect(x: bounds.width - 22, y: bounds.height - 22, width: 22, height: 22)
        dragMode = handleZone.contains(location) ? .resize : .move
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragMode != .none, let start = dragStartRect,
              let pdfView = ancestorPDFView(), pageFrame.width > 1 else { return }
        let location = convert(event.locationInWindow, from: nil)
        let dx = (location.x - dragStartLocation.x) / pageFrame.width
        let dy = (location.y - dragStartLocation.y) / pageFrame.height
        if dragMode == .move {
            rect = NormalizedRect(
                x: min(max(start.x + dx, 0), 1 - start.width),
                y: min(max(start.y + dy, 0), 1 - start.height),
                width: start.width, height: start.height)
        } else {
            let locationInPage = CGPoint(x: location.x + (frame.minX - pageFrame.minX),
                                         y: location.y + (frame.minY - pageFrame.minY))
            let newW = locationInPage.x / pageFrame.width
            let newH = locationInPage.y / pageFrame.height
            rect = NormalizedRect(
                x: start.x, y: start.y,
                width: min(max(newW, 0.08), 1 - start.x),
                height: min(max(newH, 0.03), 1 - start.y))
        }
        layoutIn(pdfView: pdfView)
    }

    override func mouseUp(with event: NSEvent) {
        if dragMode != .none {
            onChange?(rect)
        }
        dragMode = .none
        dragStartRect = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).fill()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
        NSColor.controlAccentColor.setStroke()
        border.lineWidth = 1.5
        let dash: [CGFloat] = [5, 3]
        border.setLineDash(dash, count: 2, phase: 0)
        border.stroke()

        let inner = bounds.insetBy(dx: 5, dy: 4)
        if let image {
            drawImageFit(image, in: inner)
        } else {
            drawTextLayout(in: inner)
        }

        let handleRect = CGRect(x: bounds.width - 15, y: bounds.height - 15, width: 11, height: 11)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: handleRect).fill()
        NSColor.white.setStroke()
        let ring = NSBezierPath(ovalIn: handleRect.insetBy(dx: -1.5, dy: -1.5))
        ring.lineWidth = 1.5
        ring.stroke()
    }

    private func drawImageFit(_ image: NSImage, in rect: NSRect) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: rect.midX - drawSize.width / 2, y: rect.midY - drawSize.height / 2)
        image.draw(in: NSRect(origin: origin, size: drawSize))
    }

    private func drawTextLayout(in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let captionAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(6, bounds.height * 0.14)),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(8, bounds.height * 0.2), weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(6, bounds.height * 0.13)),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
        let formatter = DateFormatter()
        formatter.dateFormat = "d. M. yyyy HH:mm"
        let caption = NSAttributedString(string: "Elektronicky podpisane · KEP", attributes: captionAttrs)
        let name = NSAttributedString(string: title.isEmpty ? "Podpis" : title, attributes: nameAttrs)
        let date = NSAttributedString(string: formatter.string(from: Date()), attributes: dateAttrs)
        var y = rect.minY
        for line in [caption, name, date] {
            let size = line.size()
            if y + size.height > rect.maxY { break }
            line.draw(with: CGRect(x: rect.minX, y: y, width: rect.width, height: size.height))
            y += size.height + 1
        }
    }
}
