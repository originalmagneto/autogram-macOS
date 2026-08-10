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

        #expect(asset.fileURL.deletingLastPathComponent() == store.assetsDirectory)
        #expect(asset.fileURL != fixturePNG)
        #expect(try pngHasAlpha(asset.fileURL))
    }
}

@Test func rotatedCardHasTransparentCorners() throws {
    try withTemporaryDirectory { directory in
        let fixturePNG = directory.appending(path: "fixture.png")
        try transparentFixturePNG().write(to: fixturePNG)
        let store = SignatureAssetStore(applicationSupportRoot: directory.appending(path: "Application Support"))
        let asset = try store.importPNG(fixturePNG)
        let renderer = VisibleSignatureRenderer(cacheRoot: directory.appending(path: "Caches"))

        let output = try renderer.render(
            asset: asset,
            content: .init(
                signerName: "Test Signer",
                certificateQualification: "Qualified certificate",
                profile: "PAdES Baseline T",
                timestampStatus: "Qualified timestamp required"
            ),
            signingTime: .now,
            rotationDegrees: 27
        )

        #expect(try cornerPixelsAreTransparent(output))
    }
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
    case unableToEncodePNG
    case unableToReadPNG
}

private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}
