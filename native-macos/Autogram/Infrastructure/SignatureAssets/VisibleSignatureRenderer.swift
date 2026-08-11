import AppKit
import Foundation

enum VisibleSignatureRendererError: Error {
    case unreadableArtwork
    case unableToRender
    case unableToEncode
}

struct VisibleSignatureRenderer {
    let assetStore: SignatureAssetStore
    let cacheRoot: URL
    let fileManager: FileManager

    init(
        assetStore: SignatureAssetStore = SignatureAssetStore(),
        cacheRoot: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.assetStore = assetStore
        self.fileManager = fileManager
        self.cacheRoot = cacheRoot ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    func render(
        asset: SignatureAsset,
        content: VisibleSignatureCardContent,
        signingTime: Date,
        rotationDegrees: Double
    ) throws -> URL {
        guard let artwork = NSImage(contentsOf: assetStore.fileURL(for: asset)) else {
            throw VisibleSignatureRendererError.unreadableArtwork
        }
        let card = try renderedCard(artwork: artwork, content: content, signingTime: signingTime)
        let rotated = try rotatedImage(card, degrees: rotationDegrees)
        let directory = cacheRoot.appending(path: "Autogram macOS/Visual Signatures", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appending(path: UUID().uuidString).appendingPathExtension("png")
        guard let tiff = rotated.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw VisibleSignatureRendererError.unableToEncode
        }
        try png.write(to: output, options: .withoutOverwriting)
        return output
    }

    private func renderedCard(artwork: NSImage, content: VisibleSignatureCardContent, signingTime: Date) throws -> NSImage {
        let size = NSSize(width: 420, height: 260)
        let image = NSImage(size: size)
        image.lockFocus()
        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            throw VisibleSignatureRendererError.unableToRender
        }
        context.setFillColor(NSColor.clear.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        let cardRect = NSRect(x: 12, y: 12, width: size.width - 24, height: size.height - 24)
        NSColor.labelColor.withAlphaComponent(0.28).setStroke()
        let cardBorder = NSBezierPath(roundedRect: cardRect, xRadius: 14, yRadius: 14)
        cardBorder.lineWidth = 1
        cardBorder.stroke()

        let statusRect = NSRect(x: 28, y: 214, width: 154, height: 20)
        NSColor.systemGreen.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: statusRect, xRadius: 10, yRadius: 10).fill()
        drawSymbol("checkmark.seal.fill", in: NSRect(x: 36, y: 217, width: 14, height: 14), color: .white)
        let statusAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 10),
            .foregroundColor: NSColor.white
        ]
        ("Timestamp required" as NSString).draw(
            in: NSRect(x: 56, y: 218, width: 116, height: 14),
            withAttributes: statusAttributes
        )

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let headingAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        ("Digitally signed by" as NSString).draw(
            in: NSRect(x: 28, y: 188, width: 136, height: 18),
            withAttributes: headingAttributes
        )
        let artworkRect = NSRect(x: 28, y: 86, width: 124, height: 80)
        artwork.draw(in: artworkRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
        NSColor.labelColor.withAlphaComponent(0.18).setStroke()
        NSBezierPath(roundedRect: artworkRect.insetBy(dx: -8, dy: -8), xRadius: 10, yRadius: 10).stroke()
        NSColor.labelColor.withAlphaComponent(0.18).setStroke()
        let divider = NSBezierPath()
        divider.move(to: CGPoint(x: 176, y: 48))
        divider.line(to: CGPoint(x: 176, y: 198))
        divider.stroke()
        let details = [
            (content.signerName, headingAttributes),
            (content.certificateQualification ?? "Certificate qualification unavailable", textAttributes),
            ("PAdES Baseline T", textAttributes),
            ("Qualified timestamp required", textAttributes)
        ]
        var y: CGFloat = 174
        for (line, attributes) in details {
            (line as NSString).draw(in: NSRect(x: 196, y: y, width: 184, height: 18), withAttributes: attributes)
            y -= 26
        }
        drawSymbol("clock.fill", in: NSRect(x: 196, y: 50, width: 13, height: 13), color: .systemGreen)
        let timestampAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        (DateFormatter.localizedString(from: signingTime, dateStyle: .medium, timeStyle: .short) as NSString).draw(
            in: NSRect(x: 216, y: 50, width: 164, height: 14),
            withAttributes: timestampAttributes
        )
        image.unlockFocus()
        return image
    }

    private func drawSymbol(_ name: String, in rect: NSRect, color: NSColor) {
        let configuration = NSImage.SymbolConfiguration(pointSize: rect.height, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else {
            return
        }
        color.set()
        symbol.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    private func rotatedImage(_ image: NSImage, degrees: Double) throws -> NSImage {
        let radians = degrees * .pi / 180
        let sine = abs(sin(radians))
        let cosine = abs(cos(radians))
        let size = image.size
        let canvas = NSSize(
            width: ceil(size.width * cosine + size.height * sine) + 2,
            height: ceil(size.width * sine + size.height * cosine) + 2
        )
        let rotated = NSImage(size: canvas)
        rotated.lockFocus()
        guard let context = NSGraphicsContext.current?.cgContext else {
            rotated.unlockFocus()
            throw VisibleSignatureRendererError.unableToRender
        }
        context.setFillColor(NSColor.clear.cgColor)
        context.fill(CGRect(origin: .zero, size: canvas))
        context.translateBy(x: canvas.width / 2, y: canvas.height / 2)
        context.rotate(by: CGFloat(radians))
        image.draw(
            in: NSRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        rotated.unlockFocus()
        return rotated
    }
}
