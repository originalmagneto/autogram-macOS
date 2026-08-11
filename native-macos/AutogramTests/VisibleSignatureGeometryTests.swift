import AppKit
import CoreGraphics
import PDFKit
import Testing
@testable import Autogram

@Test func dssFieldConvertsCropBoxLocalPlacementForPageRotations() {
    let placement = VisibleSignaturePlacement(
        pageIndex: 1,
        pageRect: CGRect(x: 72, y: 144, width: 216, height: 108),
        rotationDegrees: 31
    )
    let cropBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    let converter = PDFCoordinateConverter()
    let cases: [(rotation: Int, originX: CGFloat, originY: CGFloat, width: CGFloat, height: CGFloat)] = [
        (0, 72, 540, 216, 108),
        (90, 540, 324, 108, 216),
        (180, 324, 144, 216, 108),
        (270, 144, 72, 108, 216)
    ]

    for testCase in cases {
        let field = converter.dssField(
            placement,
            cropBox: cropBox,
            pageRotation: testCase.rotation
        )

        #expect(field.page == 2)
        #expect(field.originX == testCase.originX)
        #expect(field.originY == testCase.originY)
        #expect(field.width == testCase.width)
        #expect(field.height == testCase.height)
    }
}

@Test func rotatedPlacementGeometryAlignsVisualBoundsAndHitTesting() {
    let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
    let geometry = PDFPlacementGeometry(rect: rect, rotationDegrees: 90)
    let rotatedTopLeft = geometry.rotatedPoint(CGPoint(x: rect.minX, y: rect.minY))

    #expect(approximatelyEqual(rotatedTopLeft, CGPoint(x: 85, y: -5)))
    #expect(approximatelyEqual(geometry.visualBounds, CGRect(x: 35, y: -5, width: 50, height: 100)))
    #expect(approximatelyEqual(geometry.unrotatedPoint(rotatedTopLeft), CGPoint(x: rect.minX, y: rect.minY)))
    #expect(geometry.contains(geometry.rotatedPoint(CGPoint(x: 20, y: 30))))
    #expect(!geometry.contains(CGPoint(x: rect.minX, y: rect.minY)))
}

@Test @MainActor func placementOverlayPublishesDragAndCornerResizeChanges() throws {
    let fixtureURL = FileManager.default.temporaryDirectory.appending(path: "placement-overlay-\(UUID().uuidString).pdf")
    try writeFixturePDF(to: fixtureURL)
    defer { try? FileManager.default.removeItem(at: fixtureURL) }
    let document = try #require(PDFDocument(url: fixtureURL))
    let page = try #require(document.page(at: 0))
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 700, height: 900),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    let pdfView = PDFView(frame: window.contentView?.bounds ?? .zero)
    pdfView.autoScales = false
    pdfView.scaleFactor = 1
    pdfView.document = document
    window.contentView = pdfView
    window.makeKeyAndOrderFront(nil)
    defer { window.orderOut(nil) }
    RunLoop.current.run(until: .now.addingTimeInterval(0.05))

    let documentView = try #require(pdfView.documentView)
    let overlay = PDFPlacementOverlayView(frame: documentView.bounds)
    overlay.pdfView = pdfView
    let initial = VisibleSignaturePlacement(
        pageIndex: 0,
        pageRect: CGRect(x: 72, y: 144, width: 144, height: 72),
        rotationDegrees: 0
    )
    overlay.placement = initial
    documentView.addSubview(overlay)
    overlay.refresh()

    var published: [VisibleSignaturePlacement] = []
    overlay.onPlacementChange = { placement in
        if let placement {
            published.append(placement)
        }
    }

    let pageRect = PDFCoordinateConverter().pageRect(initial.pageRect, in: page.bounds(for: .cropBox))
    let overlayRect = overlay.convert(pdfView.convert(pageRect, from: page), from: pdfView)
    let dragStart = CGPoint(x: overlayRect.midX, y: overlayRect.midY)
    let dragEnd = CGPoint(x: dragStart.x + 24, y: dragStart.y + 18)
    #expect(documentView.hitTest(dragStart) === overlay)
    overlay.mouseDown(with: mouseEvent(.leftMouseDown, at: overlay.convert(dragStart, to: nil), in: window))
    overlay.mouseDragged(with: mouseEvent(.leftMouseDragged, at: overlay.convert(dragEnd, to: nil), in: window))
    overlay.mouseUp(with: mouseEvent(.leftMouseUp, at: overlay.convert(dragEnd, to: nil), in: window))

    let dragged = try #require(published.last)
    #expect(dragged.pageIndex == 0)
    #expect(dragged.pageRect.origin != initial.pageRect.origin)

    overlay.placement = initial
    let resizeStart = CGPoint(x: overlayRect.minX, y: overlayRect.minY)
    let resizeEnd = CGPoint(x: resizeStart.x - 20, y: resizeStart.y - 20)
    #expect(documentView.hitTest(resizeStart) === overlay)
    overlay.mouseDown(with: mouseEvent(.leftMouseDown, at: overlay.convert(resizeStart, to: nil), in: window))
    overlay.mouseDragged(with: mouseEvent(.leftMouseDragged, at: overlay.convert(resizeEnd, to: nil), in: window))
    overlay.mouseUp(with: mouseEvent(.leftMouseUp, at: overlay.convert(resizeEnd, to: nil), in: window))

    let resized = try #require(published.last)
    #expect(resized.pageIndex == 0)
    #expect(resized.pageRect.width > initial.pageRect.width)
}

private func approximatelyEqual(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
    approximatelyEqual(lhs.x, rhs.x) && approximatelyEqual(lhs.y, rhs.y)
}

private func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
    approximatelyEqual(lhs.origin, rhs.origin)
        && approximatelyEqual(lhs.width, rhs.width)
        && approximatelyEqual(lhs.height, rhs.height)
}

private func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
    abs(lhs - rhs) <= CGFloat.ulpOfOne.squareRoot()
}

private func writeFixturePDF(to url: URL) throws {
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
        throw FixturePDFError.unableToEncode
    }
    context.beginPDFPage(nil)
    context.endPDFPage()
    context.closePDF()
}

private enum FixturePDFError: Error {
    case unableToEncode
}

@MainActor
private func mouseEvent(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) -> NSEvent {
    NSEvent.mouseEvent(
        with: type,
        location: point,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 1
    )!
}
