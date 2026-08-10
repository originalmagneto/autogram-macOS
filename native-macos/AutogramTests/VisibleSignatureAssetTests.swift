import AppKit
import Foundation
import Testing
@testable import Autogram

@Test func importedArtworkUsesManagedStorageAndPreservesAlpha() throws {
    try withTemporaryDirectory { directory in
        let fixturePNG = directory.appending(path: "fixture.png")
        try transparentFixturePNG().write(to: fixturePNG)
        let store = SignatureAssetStore(applicationSupportRoot: directory.appending(path: "Application Support"))

        let asset = try store.importPNG(fixturePNG)
        let managedURL = store.fileURL(for: asset)
        let encodedAsset = try JSONEncoder().encode(asset)
        let persistedAsset = try JSONDecoder().decode(SignatureAsset.self, from: encodedAsset)
        let encodedText = String(decoding: encodedAsset, as: UTF8.self)

        #expect(managedURL.deletingLastPathComponent() == store.assetsDirectory)
        #expect(managedURL != fixturePNG)
        #expect(try pngHasAlpha(managedURL))
        #expect(persistedAsset == asset)
        #expect(store.fileURL(for: persistedAsset) == managedURL)
        #expect(!encodedText.contains(fixturePNG.path))
        #expect(!encodedText.contains(store.assetsDirectory.path))

        let fixturePDF = directory.appending(path: "fixture.pdf")
        try writeSelectedPageFixturePDF(to: fixturePDF)
        let pdfAsset = try store.importPDF(fixturePDF, pageIndex: 1)
        let pdfURL = store.fileURL(for: pdfAsset)
        let pdfSize = try pngPixelSize(pdfURL)

        #expect(pdfAsset.kind == .pdf)
        #expect(pdfURL.deletingLastPathComponent() == store.assetsDirectory)
        #expect(pdfSize.width == 40)
        #expect(pdfSize.height == 20)
        #expect(try pngHasAlpha(pdfURL))
    }
}

@Test func rotatedCardHasTransparentCorners() throws {
    try withTemporaryDirectory { directory in
        let fixturePNG = directory.appending(path: "fixture.png")
        try transparentFixturePNG().write(to: fixturePNG)
        let store = SignatureAssetStore(applicationSupportRoot: directory.appending(path: "Application Support"))
        let asset = try store.importPNG(fixturePNG)
        let renderer = VisibleSignatureRenderer(
            assetStore: store,
            cacheRoot: directory.appending(path: "Caches")
        )

        let output = try renderer.render(
            asset: asset,
            content: .init(
                signerName: "Test Signer",
                certificateQualification: "Qualified certificate"
            ),
            signingTime: .now,
            rotationDegrees: 27
        )

        #expect(try cornerPixelsAreTransparent(output))
    }
}

private func writeSelectedPageFixturePDF(to url: URL) throws {
    var mediaBox = CGRect(x: 0, y: 0, width: 200, height: 100)
    guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
        throw FixtureError.unableToEncodePDF
    }
    context.beginPDFPage(nil)
    context.setFillColor(NSColor.systemRed.cgColor)
    context.fill(mediaBox)
    context.endPDFPage()
    context.beginPDFPage(nil)
    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fill(CGRect(x: 40, y: 30, width: 20, height: 10))
    context.endPDFPage()
    context.closePDF()
}

private func transparentFixturePNG() throws -> Data {
    let image = NSImage(size: NSSize(width: 24, height: 24))
    image.lockFocus()
    NSColor.systemPurple.setFill()
    NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 16, height: 16)).fill()
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw FixtureError.unableToEncodePNG
    }
    return png
}

private func pngHasAlpha(_ url: URL) throws -> Bool {
    guard let image = NSImage(contentsOf: url),
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else {
        throw FixtureError.unableToReadPNG
    }
    return bitmap.hasAlpha
}

private func pngPixelSize(_ url: URL) throws -> CGSize {
    guard let image = NSImage(contentsOf: url),
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else {
        throw FixtureError.unableToReadPNG
    }
    return CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
}

private func cornerPixelsAreTransparent(_ url: URL) throws -> Bool {
    guard let image = NSImage(contentsOf: url),
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else {
        throw FixtureError.unableToReadPNG
    }
    let corners = [
        (0, 0),
        (bitmap.pixelsWide - 1, 0),
        (0, bitmap.pixelsHigh - 1),
        (bitmap.pixelsWide - 1, bitmap.pixelsHigh - 1)
    ]
    return corners.allSatisfy { x, y in
        bitmap.colorAt(x: x, y: y)?.alphaComponent == 0
    }
}

private enum FixtureError: Error {
    case unableToEncodePDF
    case unableToEncodePNG
    case unableToReadPNG
}

private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}
