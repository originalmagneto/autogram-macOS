import Foundation
import PDFKit

public struct VisibleSignatureStamper: Sendable {
    public init() {}

    public struct StampData: Sendable {
        public var fullName: String
        public var timestamp: Date
        public var pageIndex: Int
        public var normalizedRect: NormalizedRect
        public var imagePNG: Data?

        public init(fullName: String, timestamp: Date,
                    pageIndex: Int, normalizedRect: NormalizedRect,
                    imagePNG: Data? = nil) {
            self.fullName = fullName
            self.timestamp = timestamp
            self.pageIndex = pageIndex
            self.normalizedRect = normalizedRect
            self.imagePNG = imagePNG
        }
    }

    public func stamp(document: PDFDocument, stamp: StampData, includeTimestamp: Bool) -> Data? {
        guard let page = document.page(at: stamp.pageIndex) else { return nil }
        let bounds = page.bounds(for: .mediaBox)

        let rect = CGRect(x: stamp.normalizedRect.x * bounds.width,
                          y: (1 - stamp.normalizedRect.y - stamp.normalizedRect.height) * bounds.height,
                          width: max(stamp.normalizedRect.width * bounds.width, 120),
                          height: max(stamp.normalizedRect.height * bounds.height, 40))

        let formatter = DateFormatter()
        formatter.dateFormat = "d. M. yyyy HH:mm"

        if let imagePNG = stamp.imagePNG, let image = NSImage(data: imagePNG) {
            let annotation = ImageStampAnnotation(bounds: rect, image: image)
            page.addAnnotation(annotation)
        } else {
            let annotation = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
            annotation.contents = includeTimestamp
                ? "Elektronicky podpísané\n\(stamp.fullName)\n\(formatter.string(from: stamp.timestamp))"
                : "Elektronicky podpísané\n\(stamp.fullName)"
            annotation.font = NSFont.systemFont(ofSize: 8.5)
            annotation.fontColor = NSColor(cgColor: CGColor(gray: 0.15, alpha: 1)) ?? .black
            annotation.color = NSColor(cgColor: CGColor(red: 0.995, green: 0.99, blue: 0.975, alpha: 1)) ?? .white
            let border = PDFBorder()
            border.lineWidth = 1
            border.style = .solid
            annotation.border = border
            page.addAnnotation(annotation)
        }

        return document.dataRepresentation()
    }
}

import AppKit

final class ImageStampAnnotation: PDFAnnotation {
    private let image: NSImage

    init(bounds: CGRect, image: NSImage) {
        self.image = image
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }
}
