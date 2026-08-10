import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum SignatureAssetStoreError: Error {
    case unreadableArtwork
    case emptyArtwork
    case unavailablePDFPage
    case unableToCreateManagedArtwork
}

struct SignatureAssetStore {
    let applicationSupportRoot: URL
    let fileManager: FileManager

    init(
        applicationSupportRoot: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.applicationSupportRoot = applicationSupportRoot ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
    }

    var assetsDirectory: URL {
        applicationSupportRoot
            .appending(path: "Autogram macOS", directoryHint: .isDirectory)
            .appending(path: "Visual Signatures", directoryHint: .isDirectory)
    }

    func importPNG(_ sourceURL: URL) throws -> SignatureAsset {
        let data = try Data(contentsOf: sourceURL)
        let image = try decodedImage(from: data)
        guard image.width > 0, image.height > 0 else { throw SignatureAssetStoreError.emptyArtwork }
        guard containsVisiblePixels(image) else { throw SignatureAssetStoreError.emptyArtwork }

        let id = UUID()
        let managedFilename = managedFilename(for: id)
        let destination = try prepareManagedURL(filename: managedFilename)
        try data.write(to: destination, options: .withoutOverwriting)
        return SignatureAsset(id: id, kind: .png, managedFilename: managedFilename)
    }

    func importPDF(_ sourceURL: URL, pageIndex: Int) throws -> SignatureAsset {
        guard let document = PDFDocument(url: sourceURL),
              let page = document.page(at: pageIndex) else {
            throw SignatureAssetStoreError.unavailablePDFPage
        }
        let image = try rasterizedImage(for: page)
        let cropped = try croppedToVisiblePixels(image)
        let id = UUID()
        let managedFilename = managedFilename(for: id)
        let destination = try prepareManagedURL(filename: managedFilename)
        try pngData(for: cropped).write(to: destination, options: .withoutOverwriting)
        return SignatureAsset(id: id, kind: .pdf, managedFilename: managedFilename)
    }

    func fileURL(for asset: SignatureAsset) -> URL {
        assetsDirectory.appending(path: asset.managedFilename)
    }

    private func managedFilename(for id: UUID) -> String {
        "\(id.uuidString).png"
    }

    private func prepareManagedURL(filename: String) throws -> URL {
        try fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        return assetsDirectory.appending(path: filename)
    }

    private func decodedImage(from data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              UTType(type as String)?.conforms(to: .png) == true,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SignatureAssetStoreError.unreadableArtwork
        }
        return image
    }

    private func rasterizedImage(for page: PDFPage) throws -> CGImage {
        let bounds = page.bounds(for: .mediaBox).integral
        guard bounds.width > 0, bounds.height > 0 else { throw SignatureAssetStoreError.emptyArtwork }
        let scale: CGFloat = 2
        let width = Int((bounds.width * scale).rounded(.up))
        let height = Int((bounds.height * scale).rounded(.up))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw SignatureAssetStoreError.unreadableArtwork }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        guard let image = context.makeImage() else { throw SignatureAssetStoreError.unreadableArtwork }
        return image
    }

    private func croppedToVisiblePixels(_ image: CGImage) throws -> CGImage {
        guard let bounds = visiblePixelBounds(in: image) else { throw SignatureAssetStoreError.emptyArtwork }
        guard let cropped = image.cropping(to: bounds) else { throw SignatureAssetStoreError.unreadableArtwork }
        return cropped
    }

    private func containsVisiblePixels(_ image: CGImage) -> Bool {
        visiblePixelBounds(in: image) != nil
    }

    private func visiblePixelBounds(in image: CGImage) -> CGRect? {
        guard image.width > 0, image.height > 0 else { return nil }
        let alphaInfo = image.alphaInfo
        if alphaInfo == .none || alphaInfo == .noneSkipFirst || alphaInfo == .noneSkipLast {
            return CGRect(x: 0, y: 0, width: image.width, height: image.height)
        }
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data),
              image.bitsPerPixel >= 32 else { return nil }

        var minimumX = image.width
        var minimumY = image.height
        var maximumX = -1
        var maximumY = -1
        let bytesPerPixel = image.bitsPerPixel / 8
        let alphaOffset = alphaInfo == .first || alphaInfo == .premultipliedFirst ? 0 : bytesPerPixel - 1
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = y * image.bytesPerRow + x * bytesPerPixel + alphaOffset
                if bytes[offset] != 0 {
                    minimumX = min(minimumX, x)
                    minimumY = min(minimumY, y)
                    maximumX = max(maximumX, x)
                    maximumY = max(maximumY, y)
                }
            }
        }
        guard maximumX >= minimumX, maximumY >= minimumY else { return nil }
        return CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX + 1,
            height: maximumY - minimumY + 1
        )
    }

    private func pngData(for image: CGImage) throws -> Data {
        let mutableData = CFDataCreateMutable(nil, 0)!
        guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.png.identifier as CFString, 1, nil) else {
            throw SignatureAssetStoreError.unableToCreateManagedArtwork
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw SignatureAssetStoreError.unableToCreateManagedArtwork
        }
        return mutableData as Data
    }
}
