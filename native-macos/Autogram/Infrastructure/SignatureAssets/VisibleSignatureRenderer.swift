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
        let size = NSSize(width: 420, height: 300)
        let image = NSImage(size: size)
        image.lockFocus()
        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            throw VisibleSignatureRendererError.unableToRender
        }
        context.setFillColor(NSColor.clear.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        let cardRect = NSRect(x: 12, y: 12, width: size.width - 24, height: size.height - 24)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: cardRect, xRadius: 12, yRadius: 12).fill()
        NSColor(calibratedWhite: 0.78, alpha: 1).setStroke()
        NSBezierPath(roundedRect: cardRect, xRadius: 12, yRadius: 12).stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let headingAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        ("Digitally signed by" as NSString).draw(
            in: NSRect(x: 32, y: 260, width: size.width - 64, height: 18),
            withAttributes: headingAttributes
        )
        let artworkRect = NSRect(x: 162, y: 195, width: 96, height: 48)
        artwork.draw(in: artworkRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
        let details = [
            (content.signerName, headingAttributes),
            (content.certificateQualification ?? "Certificate qualification unavailable", textAttributes),
            ("PAdES Baseline T", textAttributes),
            ("Qualified timestamp required", textAttributes),
            (DateFormatter.localizedString(from: signingTime, dateStyle: .medium, timeStyle: .medium), textAttributes)
        ]
        var y: CGFloat = 170
        for (line, attributes) in details {
            (line as NSString).draw(in: NSRect(x: 32, y: y, width: size.width - 64, height: 18), withAttributes: attributes)
            y -= 25
        }
        image.unlockFocus()
        return image
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
