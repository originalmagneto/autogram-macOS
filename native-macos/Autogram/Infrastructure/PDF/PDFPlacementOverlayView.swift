import AppKit
import PDFKit

struct PDFPlacementGeometry {
    let rect: CGRect
    let rotationDegrees: Double

    var transform: CGAffineTransform {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: CGFloat(rotationDegrees) * .pi / 180)
            .translatedBy(x: -center.x, y: -center.y)
    }

    var visualBounds: CGRect {
        rect.applying(transform)
    }

    func rotatedPoint(_ point: CGPoint) -> CGPoint {
        point.applying(transform)
    }

    func unrotatedPoint(_ point: CGPoint) -> CGPoint {
        point.applying(transform.inverted())
    }

    func contains(_ point: CGPoint) -> Bool {
        rect.contains(unrotatedPoint(point))
    }
}

final class PDFPlacementOverlayView: NSView {
    private enum Handle: CaseIterable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight

        var accessibilityLabel: String {
            switch self {
            case .topLeft: "Resize signature from top left corner"
            case .topRight: "Resize signature from top right corner"
            case .bottomLeft: "Resize signature from bottom left corner"
            case .bottomRight: "Resize signature from bottom right corner"
            }
        }
    }

    private enum Interaction {
        case drag(startPoint: CGPoint, startRect: CGRect)
        case resize(handle: Handle, geometry: PDFPlacementGeometry, aspectRatio: CGFloat)
        case rotate(center: CGPoint, startAngle: CGFloat, startRotation: Double)
    }

    weak var pdfView: PDFView?
    var onPlacementChange: ((VisibleSignaturePlacement?) -> Void)?

    var placement: VisibleSignaturePlacement? {
        didSet { needsDisplay = true }
    }

    var cardPreview: NSImage? {
        didSet { needsDisplay = true }
    }

    private let converter = PDFCoordinateConverter()
    private let handleDiameter = NSFont.systemFontSize
    private var interaction: Interaction?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let geometry = placementGeometry() else { return }
        let targetRect = geometry.rect
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.concatenate(geometry.transform)
        defer { NSGraphicsContext.restoreGraphicsState() }

        if let cardPreview {
            cardPreview.draw(in: targetRect)
        } else {
            NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
            NSBezierPath(roundedRect: targetRect, xRadius: handleDiameter, yRadius: handleDiameter).fill()
        }

        NSColor.controlAccentColor.setStroke()
        let outline = NSBezierPath(rect: targetRect)
        outline.lineWidth = 1
        outline.stroke()

        for handle in Handle.allCases {
            drawHandle(handle, in: targetRect)
        }
        drawRotationHandle(in: targetRect)
    }

    override func mouseDown(with event: NSEvent) {
        guard let geometry = placementGeometry() else { return }
        let targetRect = geometry.rect
        let point = convert(event.locationInWindow, from: nil)
        let unrotatedPoint = geometry.unrotatedPoint(point)

        if let handle = Handle.allCases.first(where: { handleRect(for: $0, in: targetRect).contains(unrotatedPoint) }) {
            interaction = .resize(
                handle: handle,
                geometry: geometry,
                aspectRatio: targetRect.width / targetRect.height
            )
        } else if rotationHandleRect(in: targetRect).contains(unrotatedPoint) {
            let center = CGPoint(x: targetRect.midX, y: targetRect.midY)
            interaction = .rotate(
                center: center,
                startAngle: angle(from: center, to: point),
                startRotation: placement?.rotationDegrees ?? 0
            )
        } else if geometry.contains(point) {
            interaction = .drag(startPoint: point, startRect: targetRect)
        } else {
            interaction = nil
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let interaction else { return }
        let point = convert(event.locationInWindow, from: nil)

        switch interaction {
        case let .drag(startPoint, startRect):
            let rect = startRect.offsetBy(dx: point.x - startPoint.x, dy: point.y - startPoint.y)
            updatePlacement(from: snapped(
                rect,
                rotationDegrees: placement?.rotationDegrees ?? 0,
                near: point
            ))
        case let .resize(handle, geometry, aspectRatio):
            let rect = resizedRect(
                handle: handle,
                geometry: geometry,
                point: point,
                aspectRatio: aspectRatio,
                preservesAspectRatio: !event.modifierFlags.contains(.option)
            )
            updatePlacement(from: snapped(
                rect,
                rotationDegrees: geometry.rotationDegrees,
                near: point
            ))
        case let .rotate(center, startAngle, startRotation):
            var updated = placement
            updated?.rotationDegrees = startRotation + Double(angle(from: center, to: point) - startAngle) * 180 / .pi
            publish(updated)
        }
    }

    override func mouseUp(with event: NSEvent) {
        interaction = nil
    }

    override func accessibilityChildren() -> [Any]? {
        guard placementGeometry() != nil else { return [] }
        return Handle.allCases.map { handle in
            let element = NSAccessibilityElement()
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(handle.accessibilityLabel)
            return element
        }
    }

    func refresh() {
        frame = superview?.bounds ?? .zero
        needsDisplay = true
    }

    private func drawHandle(_ handle: Handle, in rect: CGRect) {
        let handleRect = handleRect(for: handle, in: rect)
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(ovalIn: handleRect).fill()
        NSColor.controlAccentColor.setStroke()
        NSBezierPath(ovalIn: handleRect).stroke()
    }

    private func drawRotationHandle(in rect: CGRect) {
        let handleRect = rotationHandleRect(in: rect)
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(ovalIn: handleRect).fill()
        NSColor.controlAccentColor.setStroke()
        NSBezierPath(ovalIn: handleRect).stroke()
    }

    private func placementRectInOverlay() -> CGRect? {
        guard let placement,
              let pdfView,
              let document = pdfView.document,
              let page = document.page(at: placement.pageIndex) else {
            return nil
        }
        let cropBox = page.bounds(for: .cropBox)
        let pageRect = converter.pageRect(placement.pageRect, in: cropBox)
        let pdfViewRect = pdfView.convert(pageRect, from: page)
        return convert(pdfViewRect, from: pdfView)
    }

    private func placementGeometry() -> PDFPlacementGeometry? {
        guard let placement, let rect = placementRectInOverlay() else { return nil }
        return PDFPlacementGeometry(rect: rect, rotationDegrees: placement.rotationDegrees)
    }

    private func updatePlacement(from overlayRect: CGRect) {
        guard let pdfView,
              let document = pdfView.document else {
            return
        }
        let centerInPDFView = pdfView.convert(CGPoint(x: overlayRect.midX, y: overlayRect.midY), from: self)
        guard let page = pdfView.page(for: centerInPDFView, nearest: false) else { return }
        let pageRect = pdfView.convert(overlayRect, to: page)
        let cropBox = page.bounds(for: .cropBox)
        guard let pageIndex = document.index(for: page).nonNegative else { return }

        var updated = placement ?? VisibleSignaturePlacement(
            pageIndex: pageIndex,
            pageRect: .zero,
            rotationDegrees: 0
        )
        updated.pageIndex = pageIndex
        updated.pageRect = converter.cropBoxLocalRect(pageRect, cropBox: cropBox)
        publish(updated)
    }

    private func snapped(_ rect: CGRect, rotationDegrees: Double, near point: CGPoint) -> CGRect {
        guard let page = pageRect(at: point) else { return rect }
        let visualBounds = PDFPlacementGeometry(
            rect: rect,
            rotationDegrees: rotationDegrees
        ).visualBounds
        let distance = handleDiameter / 2
        let xCandidates = [page.minX, page.midX - visualBounds.width / 2, page.maxX - visualBounds.width]
        let yCandidates = [page.minY, page.midY - visualBounds.height / 2, page.maxY - visualBounds.height]
        let xOffset = xCandidates.first { abs($0 - visualBounds.minX) <= distance }
            .map { $0 - visualBounds.minX } ?? 0
        let yOffset = yCandidates.first { abs($0 - visualBounds.minY) <= distance }
            .map { $0 - visualBounds.minY } ?? 0
        return rect.offsetBy(dx: xOffset, dy: yOffset)
    }

    private func pageRect(at point: CGPoint) -> CGRect? {
        guard let pdfView else { return nil }
        let pointInPDFView = pdfView.convert(point, from: self)
        guard let page = pdfView.page(for: pointInPDFView, nearest: false) else { return nil }
        return convert(pdfView.convert(page.bounds(for: .cropBox), from: page), from: pdfView)
    }

    private func resizedRect(
        handle: Handle,
        geometry: PDFPlacementGeometry,
        point: CGPoint,
        aspectRatio: CGFloat,
        preservesAspectRatio: Bool
    ) -> CGRect {
        let anchor = oppositeCorner(for: handle, in: geometry.rect)
        let fixedPoint = geometry.rotatedPoint(anchor)
        let alignedPoint = point.applying(
            CGAffineTransform(translationX: fixedPoint.x, y: fixedPoint.y)
                .rotated(by: -CGFloat(geometry.rotationDegrees) * .pi / 180)
                .translatedBy(x: -fixedPoint.x, y: -fixedPoint.y)
        )
        let width = abs(alignedPoint.x - fixedPoint.x)
        let height = preservesAspectRatio ? width / aspectRatio : abs(alignedPoint.y - fixedPoint.y)
        guard width > 0, height > 0 else { return placementRectInOverlay() ?? .zero }

        let x = handle == .topLeft || handle == .bottomLeft ? fixedPoint.x - width : fixedPoint.x
        let y = handle == .topLeft || handle == .topRight ? fixedPoint.y - height : fixedPoint.y
        let candidate = CGRect(x: x, y: y, width: width, height: height)
        let candidateGeometry = PDFPlacementGeometry(
            rect: candidate,
            rotationDegrees: geometry.rotationDegrees
        )
        let rotatedAnchor = candidateGeometry.rotatedPoint(oppositeCorner(for: handle, in: candidate))
        return candidate.offsetBy(
            dx: fixedPoint.x - rotatedAnchor.x,
            dy: fixedPoint.y - rotatedAnchor.y
        )
    }

    private func handleRect(for handle: Handle, in rect: CGRect) -> CGRect {
        let point: CGPoint
        switch handle {
        case .topLeft: point = CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: point = CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: point = CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: point = CGPoint(x: rect.maxX, y: rect.maxY)
        }
        return CGRect(
            x: point.x - handleDiameter / 2,
            y: point.y - handleDiameter / 2,
            width: handleDiameter,
            height: handleDiameter
        )
    }

    private func oppositeCorner(for handle: Handle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: CGPoint(x: rect.maxX, y: rect.maxY)
        case .topRight: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomRight: CGPoint(x: rect.minX, y: rect.minY)
        }
    }

    private func rotationHandleRect(in rect: CGRect) -> CGRect {
        CGRect(
            x: rect.midX - handleDiameter / 2,
            y: rect.minY - handleDiameter * 2,
            width: handleDiameter,
            height: handleDiameter
        )
    }

    private func angle(from center: CGPoint, to point: CGPoint) -> CGFloat {
        atan2(point.y - center.y, point.x - center.x)
    }

    private func publish(_ placement: VisibleSignaturePlacement?) {
        self.placement = placement
        onPlacementChange?(placement)
    }
}

private extension Int {
    var nonNegative: Int? {
        self >= 0 ? self : nil
    }
}
