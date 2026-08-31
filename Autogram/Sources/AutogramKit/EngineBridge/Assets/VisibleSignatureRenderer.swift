import AppKit
import Foundation

public enum VisibleSignatureRendererError: Error {
    case unreadableArtwork
    case unableToRender
    case unableToEncode
}

public struct VisibleSignatureRenderer {
    public static let artworkSlot = NSRect(x: 28, y: 116, width: 364, height: 84)

    public let assetStore: SignatureAssetStore
    let cacheRoot: URL
    let fileManager: FileManager

    public init(
        assetStore: SignatureAssetStore = SignatureAssetStore(),
        cacheRoot: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.assetStore = assetStore
        self.fileManager = fileManager
        self.cacheRoot = cacheRoot ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    public static func aspectFitRect(imageSize: CGSize, inside bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    public func render(
        asset: SignatureAsset,
        content: VisibleSignatureCardContent,
        signingTime: Date,
        rotationDegrees: Double,
        isPreview: Bool = false
    ) throws -> URL {
        guard let artwork = NSImage(contentsOf: assetStore.fileURL(for: asset)) else {
            throw VisibleSignatureRendererError.unreadableArtwork
        }
        let card = try renderedCard(
            artwork: artwork,
            content: content,
            signingTime: signingTime,
            isPreview: isPreview
        )
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
    public func renderPNG(
        artworkPNG: Data,
        content: VisibleSignatureCardContent,
        signingTime: Date
    ) throws -> Data {
        guard let artwork = NSImage(data: artworkPNG) else {
            throw VisibleSignatureRendererError.unreadableArtwork
        }
        let card = try renderedCard(
            artwork: artwork,
            content: content,
            signingTime: signingTime,
            isPreview: false)
        guard let tiff = card.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw VisibleSignatureRendererError.unableToEncode
        }
        return png
    }


    private func renderedCard(
        artwork: NSImage,
        content: VisibleSignatureCardContent,
        signingTime: Date,
        isPreview: Bool
    ) throws -> NSImage {
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

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let headingAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        ("Digitally signed by" as NSString).draw(
            in: NSRect(x: 28, y: 210, width: size.width - 56, height: 18),
            withAttributes: headingAttributes
        )
        let artworkRect = Self.aspectFitRect(imageSize: artwork.size, inside: Self.artworkSlot)
        artwork.draw(in: artworkRect, from: .zero, operation: .sourceOver, fraction: 1,
                     respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
        NSColor.labelColor.withAlphaComponent(0.18).setStroke()
        let divider = NSBezierPath()
        divider.move(to: CGPoint(x: 28, y: 106))
        divider.line(to: CGPoint(x: size.width - 28, y: 106))
        divider.stroke()
        var details: [(String, [NSAttributedString.Key: Any])] = [
            (content.signerName, headingAttributes)
        ]
        if let certificateName = content.certificateName, !certificateName.isEmpty {
            details.append(("Certifikát: \(certificateName)", textAttributes))
        }
        if let qualification = content.certificateQualification, !qualification.isEmpty {
            details.append((qualification, textAttributes))
        }
        if let timestampAuthorityName = content.timestampAuthorityName,
           !timestampAuthorityName.isEmpty {
            details.append(("QTS: \(timestampAuthorityName)", textAttributes))
        }
        var y: CGFloat = 88
        for (line, attributes) in details.prefix(4) {
            (line as NSString).draw(
                in: NSRect(x: 28, y: y, width: size.width - 56, height: 17),
                withAttributes: attributes)
            y -= 16
        }
        drawSymbol("clock.fill", in: NSRect(x: 28, y: 34, width: 13, height: 13), color: .systemGreen)
        let timestampAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let timeText = isPreview
            ? "Signing time will be added"
            : DateFormatter.localizedString(from: signingTime, dateStyle: .medium, timeStyle: .short)
        (timeText as NSString).draw(
            in: NSRect(x: 48, y: 34, width: 150, height: 14),
            withAttributes: timestampAttributes
        )
        drawSymbol("checkmark.seal.fill", in: NSRect(x: 214, y: 32, width: 16, height: 16), color: .systemGreen)
        let statusAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 10),
            .foregroundColor: NSColor.systemGreen
        ]
        let statusText = isPreview
            ? "Preview of qualified signature"
            : "Qualified signature and timestamp"
        (statusText as NSString).draw(
            in: NSRect(x: 236, y: 34, width: 156, height: 14),
            withAttributes: statusAttributes
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
